package engine

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

type ftpReply struct {
	code    int
	message string
}

type ftpControl struct {
	conn   net.Conn
	reader *bufio.Reader
}

func dialFTPControl(ctx context.Context, host, port string) (*ftpControl, error) {
	dialer := &net.Dialer{Timeout: 15 * time.Second, KeepAlive: 30 * time.Second}
	conn, err := dialer.DialContext(ctx, "tcp", net.JoinHostPort(host, port))
	if err != nil {
		return nil, err
	}
	return &ftpControl{
		conn:   conn,
		reader: bufio.NewReader(conn),
	}, nil
}

func (c *ftpControl) readReply() (ftpReply, error) {
	var expectedCode int
	var sb strings.Builder

	for {
		line, err := c.reader.ReadString('\n')
		if err != nil {
			return ftpReply{}, err
		}
		line = strings.TrimRight(line, "\r\n")
		if sb.Len() > 0 {
			sb.WriteByte('\n')
		}
		sb.WriteString(line)

		if len(line) >= 3 {
			code, convErr := strconv.Atoi(line[:3])
			if convErr == nil {
				if expectedCode == 0 {
					if len(line) == 3 || line[3] == ' ' {
						return ftpReply{code: code, message: sb.String()}, nil
					}
					if line[3] == '-' {
						expectedCode = code
					}
				} else if code == expectedCode && (len(line) == 3 || line[3] == ' ') {
					return ftpReply{code: expectedCode, message: sb.String()}, nil
				}
			}
		}
	}
}

func (c *ftpControl) sendCommand(cmd string) (ftpReply, error) {
	if _, err := fmt.Fprintf(c.conn, "%s\r\n", cmd); err != nil {
		return ftpReply{}, err
	}
	return c.readReply()
}

func (c *ftpControl) close() {
	if c.conn != nil {
		_ = c.conn.Close()
	}
}

func ftpCredentials(u *url.URL, username, password string) (string, string) {
	if u.User != nil {
		user := u.User.Username()
		pass, _ := u.User.Password()
		if user != "" {
			return user, pass
		}
	}
	if username != "" {
		return username, password
	}
	return "anonymous", "download_manager@local"
}

func openAuthenticatedFTP(ctx context.Context, u *url.URL, username, password string) (*ftpControl, error) {
	port := u.Port()
	if port == "" {
		port = "21"
	}
	ctrl, err := dialFTPControl(ctx, u.Hostname(), port)
	if err != nil {
		return nil, err
	}

	greeting, err := ctrl.readReply()
	if err != nil || greeting.code < 200 || greeting.code >= 300 {
		ctrl.close()
		if err != nil {
			return nil, err
		}
		return nil, fmt.Errorf("FTP greeting failed: %s", greeting.message)
	}

	user, pass := ftpCredentials(u, username, password)
	userRep, err := ctrl.sendCommand("USER " + user)
	if err != nil {
		ctrl.close()
		return nil, err
	}
	if userRep.code == 331 {
		passRep, err := ctrl.sendCommand("PASS " + pass)
		if err != nil || passRep.code < 200 || passRep.code >= 300 {
			ctrl.close()
			if err != nil {
				return nil, err
			}
			return nil, fmt.Errorf("FTP login failed: %s", passRep.message)
		}
	} else if userRep.code < 200 || userRep.code >= 300 {
		ctrl.close()
		return nil, fmt.Errorf("FTP USER failed: %s", userRep.message)
	}

	_, _ = ctrl.sendCommand("TYPE I")
	return ctrl, nil
}

var pasvRegex = regexp.MustCompile(`\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)`)

func parsePASV(reply ftpReply, fallbackHost string) (string, string, error) {
	m := pasvRegex.FindStringSubmatch(reply.message)
	if len(m) != 7 {
		return "", "", fmt.Errorf("invalid FTP PASV reply: %s", reply.message)
	}
	ip := fmt.Sprintf("%s.%s.%s.%s", m[1], m[2], m[3], m[4])
	if ip == "0.0.0.0" {
		ip = fallbackHost
	}
	p1, _ := strconv.Atoi(m[5])
	p2, _ := strconv.Atoi(m[6])
	port := strconv.Itoa(p1*256 + p2)
	return ip, port, nil
}

func ProbeFTP(ctx context.Context, u *url.URL, username, password string) (FileInfo, error) {
	ctrl, err := openAuthenticatedFTP(ctx, u, username, password)
	if err != nil {
		return FileInfo{}, err
	}
	defer ctrl.close()

	remotePath := u.Path
	if remotePath == "" {
		remotePath = "/"
	}

	var fileSize *int64
	if sizeRep, err := ctrl.sendCommand("SIZE " + remotePath); err == nil && sizeRep.code == 213 {
		fields := strings.Fields(sizeRep.message)
		if len(fields) >= 2 {
			if parsed, err := strconv.ParseInt(fields[1], 10, 64); err == nil && parsed >= 0 {
				fileSize = &parsed
			}
		}
	}

	supportsResume := false
	if restRep, err := ctrl.sendCommand("REST 0"); err == nil && restRep.code == 350 {
		supportsResume = true
	}

	_, _ = ctrl.sendCommand("QUIT")

	fileName := filepath.Base(remotePath)
	if fileName == "" || fileName == "/" || fileName == "." {
		fileName = fmt.Sprintf("ftp_download_%d", time.Now().UnixMilli())
	}
	fileType := "Unknown"
	if dot := strings.LastIndex(fileName, "."); dot != -1 && dot < len(fileName)-1 {
		fileType = strings.ToUpper(fileName[dot+1:])
	}

	return FileInfo{
		FileName:             fileName,
		FileSize:             fileSize,
		FileType:             fileType,
		SupportsResume:       supportsResume,
		Protocol:             "FTP",
		IsDirectDownload:     true,
		DirectDownloadReason: "Direct FTP file link",
	}, nil
}

func DownloadFTP(
	ctx context.Context,
	u *url.URL,
	req DownloadRequest,
	limiter *SpeedLimiter,
	emit func(ProgressEvent),
) error {
	if err := os.MkdirAll(filepath.Dir(req.SavePath), 0o755); err != nil {
		return err
	}

	remotePath := u.Path
	if remotePath == "" {
		remotePath = "/"
	}

	maxRetries := req.MaxReconnectAttempts
	if maxRetries <= 0 {
		maxRetries = 8
	}

	received := req.InitialOffset
	var total int64 = -1
	attempt := 0
	lastEmit := time.Time{}

	for {
		if ctx.Err() != nil {
			return ctx.Err()
		}

		ctrl, err := openAuthenticatedFTP(ctx, u, req.Username, req.Password)
		if err != nil {
			if ctx.Err() != nil || attempt >= maxRetries {
				return err
			}
			attempt++
			emit(ProgressEvent{Type: "reconnecting", Received: received, Total: total, Attempt: attempt})
			if sleepErr := CancellableSleep(ctx, reconnectBackoff(attempt)); sleepErr != nil {
				return sleepErr
			}
			continue
		}

		if sizeRep, err := ctrl.sendCommand("SIZE " + remotePath); err == nil && sizeRep.code == 213 {
			fields := strings.Fields(sizeRep.message)
			if len(fields) >= 2 {
				if parsed, err := strconv.ParseInt(fields[1], 10, 64); err == nil && parsed > 0 {
					total = parsed
				}
			}
		}

		pasvRep, err := ctrl.sendCommand("PASV")
		if err != nil || pasvRep.code != 227 {
			ctrl.close()
			if err == nil {
				err = fmt.Errorf("FTP PASV failed: %s", pasvRep.message)
			}
			return err
		}

		dataHost, dataPort, err := parsePASV(pasvRep, u.Hostname())
		if err != nil {
			ctrl.close()
			return err
		}

		dialer := &net.Dialer{Timeout: 15 * time.Second}
		dataConn, err := dialer.DialContext(ctx, "tcp", net.JoinHostPort(dataHost, dataPort))
		if err != nil {
			ctrl.close()
			if ctx.Err() != nil || attempt >= maxRetries {
				return err
			}
			attempt++
			emit(ProgressEvent{Type: "reconnecting", Received: received, Total: total, Attempt: attempt})
			if sleepErr := CancellableSleep(ctx, reconnectBackoff(attempt)); sleepErr != nil {
				return sleepErr
			}
			continue
		}

		// Close sockets immediately on context cancel
		stopWatch := make(chan struct{})
		go func() {
			select {
			case <-ctx.Done():
				_ = dataConn.Close()
				ctrl.close()
			case <-stopWatch:
			}
		}()

		isResuming := received > 0
		if isResuming {
			restRep, restErr := ctrl.sendCommand(fmt.Sprintf("REST %d", received))
			if restErr != nil || restRep.code != 350 {
				close(stopWatch)
				_ = dataConn.Close()
				ctrl.close()
				if restErr != nil {
					return restErr
				}
				return errors.New("FTP server does not support resume (REST)")
			}
		}

		retrRep, retrErr := ctrl.sendCommand("RETR " + remotePath)
		if retrErr != nil || (retrRep.code != 125 && retrRep.code != 150) {
			close(stopWatch)
			_ = dataConn.Close()
			ctrl.close()
			if retrErr != nil {
				return retrErr
			}
			return fmt.Errorf("FTP RETR failed: %s", retrRep.message)
		}

		flags := os.O_CREATE | os.O_WRONLY
		if isResuming {
			flags |= os.O_APPEND
		} else {
			flags |= os.O_TRUNC
		}
		file, fileErr := os.OpenFile(req.SavePath, flags, 0o644)
		if fileErr != nil {
			close(stopWatch)
			_ = dataConn.Close()
			ctrl.close()
			return fileErr
		}

		buf := make([]byte, 64*1024)
		var streamErr error
		for {
			n, rErr := dataConn.Read(buf)
			if n > 0 {
				if _, wErr := file.Write(buf[:n]); wErr != nil {
					streamErr = wErr
					break
				}
				received += int64(n)
				now := time.Now()
				if (total > 0 && received >= total) || now.Sub(lastEmit) >= 150*time.Millisecond {
					lastEmit = now
					emit(ProgressEvent{Type: "progress", Received: received, Total: total})
				}
				if limiter != nil {
					if tErr := limiter.Throttle(ctx, int64(n)); tErr != nil {
						streamErr = tErr
						break
					}
				}
			}
			if rErr != nil {
				if !errors.Is(rErr, io.EOF) {
					streamErr = rErr
				}
				break
			}
		}

		_ = file.Sync()
		_ = file.Close()
		close(stopWatch)
		_ = dataConn.Close()

		if streamErr == nil {
			_, _ = ctrl.readReply() // 226 transfer complete
			_, _ = ctrl.sendCommand("QUIT")
		}
		ctrl.close()

		if ctx.Err() != nil {
			return ctx.Err()
		}

		if streamErr == nil && (total <= 0 || received >= total) {
			finalTotal := total
			if finalTotal <= 0 {
				finalTotal = received
			}
			emit(ProgressEvent{Type: "progress", Received: received, Total: finalTotal})
			return nil
		}

		if attempt >= maxRetries {
			if streamErr != nil {
				return streamErr
			}
			return errors.New("FTP connection closed prematurely")
		}

		attempt++
		emit(ProgressEvent{Type: "reconnecting", Received: received, Total: total, Attempt: attempt})
		if sleepErr := CancellableSleep(ctx, reconnectBackoff(attempt)); sleepErr != nil {
			return sleepErr
		}
	}
}
