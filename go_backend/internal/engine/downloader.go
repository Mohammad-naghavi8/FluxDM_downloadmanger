package engine

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	defaultUserAgent      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
	MinSegmentedSizeBytes = 1024 * 1024
)

var (
	contentDispositionRegex = regexp.MustCompile(`(?i)filename\*?=(?:UTF-8''|")?([^";]+)`)
	directExtensions        = map[string]bool{
		"zip": true, "rar": true, "7z": true, "tar": true, "gz": true, "bz2": true,
		"xz": true, "tgz": true, "iso": true, "img": true, "cab": true, "exe": true,
		"msi": true, "msix": true, "appx": true, "apk": true, "dmg": true, "deb": true,
		"rpm": true, "bin": true, "mp4": true, "mkv": true, "avi": true, "mov": true,
		"webm": true, "mp3": true, "wav": true, "flac": true, "aac": true, "ogg": true,
		"m4a": true, "pdf": true, "doc": true, "docx": true, "xls": true, "xlsx": true,
		"ppt": true, "pptx": true, "txt": true, "csv": true, "jpg": true, "jpeg": true,
		"png": true, "gif": true, "webp": true, "svg": true, "torrent": true,
	}
	partExtRegex = regexp.MustCompile(`^(?:part\d+|r\d{2}|\d{3})$`)
	ioBufPool    = sync.Pool{
		New: func() any {
			b := make([]byte, 64*1024)
			return &b
		},
	}
)

type Engine struct {
	dialer *SmartDialer
	client *http.Client
	cfgMu  sync.RWMutex
	cfg    EngineConfig
}

func NewEngine() *Engine {
	dialer := NewSmartDialer()
	return &Engine{
		dialer: dialer,
		client: NewSmartHTTPClient(dialer),
	}
}

func stateFilePath(savePath string) string {
	return savePath + ".dmstate"
}

func partFilePath(savePath string, index int) string {
	return fmt.Sprintf("%s.part%d", savePath, index)
}

func reconnectBackoff(attempt int) time.Duration {
	switch {
	case attempt <= 1:
		return 600 * time.Millisecond
	case attempt == 2:
		return time.Second
	case attempt == 3:
		return 2 * time.Second
	case attempt == 4:
		return 3 * time.Second
	default:
		return 5 * time.Second
	}
}

func applyCommonHeaders(req *http.Request, username, password string) {
	req.Header.Set("User-Agent", defaultUserAgent)
	req.Header.Set("Accept", "*/*")
	if username != "" {
		token := base64.StdEncoding.EncodeToString([]byte(username + ":" + password))
		req.Header.Set("Authorization", "Basic "+token)
	}
}

func evaluateDirectDownload(u *url.URL, contentType, disposition string) (bool, string) {
	if strings.EqualFold(u.Scheme, "ftp") {
		return true, "Direct FTP file link"
	}
	if strings.Contains(strings.ToLower(disposition), "attachment") {
		return true, "Direct download (server attachment)"
	}
	mime := strings.ToLower(strings.TrimSpace(strings.Split(contentType, ";")[0]))
	if mime != "" {
		if mime == "text/html" || mime == "application/xhtml+xml" {
			return false, "Web page (HTML), not a direct file link"
		}
		if mime == "application/octet-stream" ||
			strings.HasPrefix(mime, "video/") ||
			strings.HasPrefix(mime, "audio/") ||
			strings.HasPrefix(mime, "image/") ||
			strings.Contains(mime, "zip") ||
			strings.Contains(mime, "rar") ||
			strings.Contains(mime, "compressed") ||
			strings.Contains(mime, "archive") ||
			strings.Contains(mime, "pdf") ||
			strings.Contains(mime, "msdownload") ||
			strings.Contains(mime, "android.package") {
			return true, "Direct download link"
		}
	}

	base := strings.ToLower(filepath.Base(u.Path))
	if dot := strings.LastIndex(base, "."); dot != -1 && dot < len(base)-1 {
		ext := base[dot+1:]
		if directExtensions[ext] || partExtRegex.MatchString(ext) {
			return true, "Direct download link"
		}
	}
	q := strings.ToLower(u.RawQuery)
	if strings.Contains(q, "download=1") || strings.Contains(q, "attachment") || strings.Contains(q, "export=download") {
		return true, "Direct download link"
	}
	return false, "Could not confirm direct file link"
}

func (e *Engine) Probe(ctx context.Context, rawURL, username, password string) (FileInfo, error) {
	u, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil || u.Host == "" {
		return FileInfo{}, errors.New("invalid download URL")
	}
	scheme := strings.ToLower(u.Scheme)
	if scheme == "ftp" {
		return ProbeFTP(ctx, u, username, password)
	}
	if scheme != "http" && scheme != "https" {
		return FileInfo{}, errors.New("unsupported protocol (use HTTP, HTTPS, or FTP)")
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodHead, u.String(), nil)
	if err != nil {
		return FileInfo{}, err
	}
	e.applyConfiguredHeaders(req, username, password)

	resp, err := e.client.Do(req)
	if err != nil {
		return FileInfo{}, err
	}
	_ = resp.Body.Close()

	// Fallback to 1-byte Range GET when servers reject HEAD
	if resp.StatusCode == http.StatusForbidden ||
		resp.StatusCode == http.StatusMethodNotAllowed ||
		resp.StatusCode == http.StatusNotImplemented {
		getReq, gErr := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
		if gErr != nil {
			return FileInfo{}, gErr
		}
		e.applyConfiguredHeaders(getReq, username, password)
		getReq.Header.Set("Range", "bytes=0-0")
		resp, err = e.client.Do(getReq)
		if err != nil {
			return FileInfo{}, err
		}
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 1024))
		_ = resp.Body.Close()
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 400 {
		return FileInfo{}, fmt.Errorf("server returned HTTP %d", resp.StatusCode)
	}

	var fileSize *int64
	if cr := resp.Header.Get("Content-Range"); strings.Contains(cr, "/") {
		parts := strings.Split(cr, "/")
		if parsed, pErr := strconv.ParseInt(strings.TrimSpace(parts[len(parts)-1]), 10, 64); pErr == nil && parsed >= 0 {
			fileSize = &parsed
		}
	}
	if fileSize == nil {
		if cl := resp.Header.Get("Content-Length"); cl != "" {
			if parsed, pErr := strconv.ParseInt(strings.TrimSpace(cl), 10, 64); pErr == nil && parsed >= 0 {
				fileSize = &parsed
			}
		}
	}

	effectiveURL := u
	if resp.Request != nil && resp.Request.URL != nil {
		effectiveURL = resp.Request.URL
	}

	fileName := ""
	disposition := resp.Header.Get("Content-Disposition")
	if disposition != "" {
		if m := contentDispositionRegex.FindStringSubmatch(disposition); len(m) >= 2 {
			decoded, dErr := url.QueryUnescape(strings.Trim(strings.TrimSpace(m[1]), `"`))
			if dErr == nil && decoded != "" {
				fileName = decoded
			}
		}
	}
	if fileName == "" && effectiveURL.Path != "" {
		seg := filepath.Base(effectiveURL.Path)
		if seg != "" && seg != "/" && seg != "." {
			if decoded, dErr := url.PathUnescape(seg); dErr == nil {
				fileName = decoded
			} else {
				fileName = seg
			}
		}
	}
	if fileName == "" {
		fileName = fmt.Sprintf("download_%d", time.Now().UnixMilli())
	}

	fileType := "Unknown"
	if dot := strings.LastIndex(fileName, "."); dot != -1 && dot < len(fileName)-1 {
		fileType = strings.ToUpper(fileName[dot+1:])
	}

	supportsResume := strings.EqualFold(resp.Header.Get("Accept-Ranges"), "bytes") ||
		resp.StatusCode == http.StatusPartialContent

	contentType := resp.Header.Get("Content-Type")
	isDirect, reason := evaluateDirectDownload(effectiveURL, contentType, disposition)

	return FileInfo{
		FileName:             fileName,
		FileSize:             fileSize,
		FileType:             fileType,
		SupportsResume:       supportsResume,
		Protocol:             strings.ToUpper(effectiveURL.Scheme),
		IsDirectDownload:     isDirect,
		DirectDownloadReason: reason,
		ContentType:          contentType,
	}, nil
}

func CleanupPartialFiles(savePath string) error {
	segCount := 16
	sf := stateFilePath(savePath)
	if data, err := os.ReadFile(sf); err == nil {
		var saved SavedStateFile
		if json.Unmarshal(data, &saved) == nil && len(saved.Segments) > segCount {
			segCount = len(saved.Segments)
		}
		_ = os.Remove(sf)
	}
	for i := 0; i < segCount; i++ {
		_ = os.Remove(partFilePath(savePath, i))
	}
	_ = os.Remove(savePath)
	return nil
}

func GetSavedProgress(savePath, pausedLabel string) (int64, []ConnectionState, bool) {
	if pausedLabel == "" {
		pausedLabel = "Paused"
	}
	sf := stateFilePath(savePath)
	data, err := os.ReadFile(sf)
	if err == nil {
		var saved SavedStateFile
		if json.Unmarshal(data, &saved) == nil && len(saved.Segments) > 0 {
			var total int64
			conns := make([]ConnectionState, 0, len(saved.Segments))
			for _, spec := range saved.Segments {
				var savedBytes int64
				if fi, statErr := os.Stat(partFilePath(savePath, spec.Index)); statErr == nil {
					savedBytes = fi.Size()
				}
				if savedBytes > spec.Length() {
					savedBytes = spec.Length()
				}
				total += savedBytes
				done := savedBytes >= spec.Length()
				info := pausedLabel
				if done {
					info = "Completed"
				}
				endVal := spec.EndByte
				conns = append(conns, ConnectionState{
					Number:          spec.Index + 1,
					StartByte:       spec.StartByte,
					EndByte:         &endVal,
					DownloadedBytes: savedBytes,
					Info:            info,
					IsActive:        false,
					IsCompleted:     done,
				})
			}
			return total, conns, true
		}
	}

	if fi, err := os.Stat(savePath); err == nil {
		return fi.Size(), nil, false
	}
	return 0, nil, false
}

func buildSegments(totalBytes int64, requested int) []SegmentSpec {
	if requested < 1 {
		requested = 1
	}
	if requested > 16 {
		requested = 16
	}
	if totalBytes < int64(requested) {
		requested = 1
	}
	base := totalBytes / int64(requested)
	rem := totalBytes % int64(requested)
	specs := make([]SegmentSpec, 0, requested)
	var offset int64
	for i := 0; i < requested; i++ {
		size := base
		if int64(i) < rem {
			size++
		}
		end := offset + size - 1
		specs = append(specs, SegmentSpec{Index: i, StartByte: offset, EndByte: end})
		offset = end + 1
	}
	return specs
}

func (e *Engine) Download(
	ctx context.Context,
	req DownloadRequest,
	limiter *SpeedLimiter,
	emit func(ProgressEvent),
) error {
	u, err := url.Parse(strings.TrimSpace(req.URL))
	if err != nil || u.Host == "" {
		return errors.New("invalid download URL")
	}

	if strings.EqualFold(u.Scheme, "ftp") {
		return DownloadFTP(ctx, u, req, limiter, emit)
	}

	if req.Segmented && req.TotalBytes > 0 && req.ConnectionCount > 1 {
		req.ConnectionCount = e.effectiveConnectionCount(req.URL, req.ConnectionCount)
		return e.downloadSegmented(ctx, req, limiter, emit)
	}
	return e.downloadSingle(ctx, req, limiter, emit)
}

func (e *Engine) downloadSingle(
	ctx context.Context,
	req DownloadRequest,
	limiter *SpeedLimiter,
	emit func(ProgressEvent),
) error {
	if err := os.MkdirAll(filepath.Dir(req.SavePath), 0o755); err != nil {
		return err
	}

	maxRetries := req.MaxReconnectAttempts
	if maxRetries <= 0 {
		maxRetries = 10
	}

	received := req.InitialOffset
	var total int64 = req.TotalBytes
	if total <= 0 {
		total = -1
	}
	serverSupportsRange := req.InitialOffset > 0
	attempt := 0
	lastEmit := time.Time{}

	for {
		if ctx.Err() != nil {
			return ctx.Err()
		}

		isResuming := received > 0 && serverSupportsRange
		httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, req.URL, nil)
		if err != nil {
			return err
		}
		e.applyConfiguredHeaders(httpReq, req.Username, req.Password)
		if isResuming {
			httpReq.Header.Set("Range", fmt.Sprintf("bytes=%d-", received))
		}

		resp, err := e.client.Do(httpReq)
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

		if isResuming && resp.StatusCode != http.StatusPartialContent {
			_ = resp.Body.Close()
			return fmt.Errorf("server returned HTTP %d instead of 206 Partial Content", resp.StatusCode)
		}
		if !isResuming && (resp.StatusCode < 200 || resp.StatusCode >= 300) {
			_ = resp.Body.Close()
			return fmt.Errorf("server returned HTTP %d", resp.StatusCode)
		}

		if strings.EqualFold(resp.Header.Get("Accept-Ranges"), "bytes") || resp.StatusCode == http.StatusPartialContent {
			serverSupportsRange = true
		}

		if isResuming {
			if cr := resp.Header.Get("Content-Range"); strings.Contains(cr, "/") {
				parts := strings.Split(cr, "/")
				if parsed, pErr := strconv.ParseInt(strings.TrimSpace(parts[len(parts)-1]), 10, 64); pErr == nil && parsed > 0 {
					total = parsed
				}
			}
		} else {
			received = 0
			if resp.ContentLength > 0 {
				total = resp.ContentLength
			}
		}

		flags := os.O_CREATE | os.O_WRONLY
		if isResuming {
			flags |= os.O_APPEND
		} else {
			flags |= os.O_TRUNC
		}
		file, fileErr := os.OpenFile(req.SavePath, flags, 0o644)
		if fileErr != nil {
			_ = resp.Body.Close()
			return fileErr
		}

		bufPtr := ioBufPool.Get().(*[]byte)
		buf := *bufPtr
		var streamErr error
		for {
			n, rErr := resp.Body.Read(buf)
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

		ioBufPool.Put(bufPtr)
		_ = file.Sync()
		_ = file.Close()
		_ = resp.Body.Close()

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
			return errors.New("connection closed prematurely")
		}

		attempt++
		emit(ProgressEvent{Type: "reconnecting", Received: received, Total: total, Attempt: attempt})
		if sleepErr := CancellableSleep(ctx, reconnectBackoff(attempt)); sleepErr != nil {
			return sleepErr
		}
	}
}

func (e *Engine) downloadSegmented(
	ctx context.Context,
	req DownloadRequest,
	limiter *SpeedLimiter,
	emit func(ProgressEvent),
) error {
	if err := os.MkdirAll(filepath.Dir(req.SavePath), 0o755); err != nil {
		return err
	}

	sf := stateFilePath(req.SavePath)
	resolvedTotal := req.TotalBytes
	var segments []SegmentSpec

	if req.ResumeExisting {
		if data, err := os.ReadFile(sf); err == nil {
			var saved SavedStateFile
			if json.Unmarshal(data, &saved) == nil && saved.TotalBytes > 0 && len(saved.Segments) > 0 {
				resolvedTotal = saved.TotalBytes
				segments = saved.Segments
			}
		}
	}

	if len(segments) == 0 {
		_ = CleanupPartialFiles(req.SavePath)
		segments = buildSegments(resolvedTotal, req.ConnectionCount)
		stateData, _ := json.Marshal(SavedStateFile{
			URL:        req.URL,
			TotalBytes: resolvedTotal,
			Segments:   segments,
		})
		if err := os.WriteFile(sf, stateData, 0o644); err != nil {
			return err
		}
	}

	// Resolve redirects once so all N goroutines hit the resolved CDN edge directly
	effectiveURL := req.URL
	if headReq, err := http.NewRequestWithContext(ctx, http.MethodHead, req.URL, nil); err == nil {
		e.applyConfiguredHeaders(headReq, req.Username, req.Password)
		if headResp, hErr := e.client.Do(headReq); hErr == nil {
			_ = headResp.Body.Close()
			if headResp.Request != nil && headResp.Request.URL != nil {
				effectiveURL = headResp.Request.URL.String()
			}
		}
	}
	if ctx.Err() != nil {
		return ctx.Err()
	}

	segCount := len(segments)
	var mu sync.Mutex
	segDownloaded := make([]int64, segCount)
	segInfo := make([]string, segCount)
	segActive := make([]bool, segCount)
	segCompleted := make([]bool, segCount)
	segError := make([]bool, segCount)

	for _, spec := range segments {
		var existing int64
		if fi, err := os.Stat(partFilePath(req.SavePath, spec.Index)); err == nil {
			existing = fi.Size()
			if existing > spec.Length() {
				_ = os.Remove(partFilePath(req.SavePath, spec.Index))
				existing = 0
			}
		}
		done := existing >= spec.Length()
		segDownloaded[spec.Index] = existing
		if done {
			segInfo[spec.Index] = "Completed"
			segActive[spec.Index] = false
			segCompleted[spec.Index] = true
		} else {
			segInfo[spec.Index] = "Connecting..."
			segActive[spec.Index] = true
		}
	}

	var lastEmit time.Time
	emitSnapshot := func(force bool) {
		mu.Lock()
		now := time.Now()
		if !force && now.Sub(lastEmit) < 150*time.Millisecond {
			mu.Unlock()
			return
		}
		lastEmit = now

		var totalReceived int64
		conns := make([]ConnectionState, segCount)
		for i, spec := range segments {
			dl := segDownloaded[i]
			totalReceived += dl
			endVal := spec.EndByte
			conns[i] = ConnectionState{
				Number:          i + 1,
				StartByte:       spec.StartByte,
				EndByte:         &endVal,
				DownloadedBytes: dl,
				Info:            segInfo[i],
				IsActive:        segActive[i],
				IsCompleted:     segCompleted[i],
				HasError:        segError[i],
			}
		}
		mu.Unlock()

		emit(ProgressEvent{
			Type:        "progress",
			Received:    totalReceived,
			Total:       resolvedTotal,
			Connections: conns,
		})
	}

	emitSnapshot(true)

	segCtx, cancelAll := context.WithCancel(ctx)
	defer cancelAll()

	maxRetries := req.MaxReconnectAttempts
	if maxRetries <= 0 {
		maxRetries = 10
	}

	var wg sync.WaitGroup
	var firstErrMu sync.Mutex
	var firstErr error
	setErr := func(err error) {
		firstErrMu.Lock()
		if firstErr == nil {
			firstErr = err
		}
		firstErrMu.Unlock()
		cancelAll()
	}

	for _, spec := range segments {
		wg.Add(1)
		go func(spec SegmentSpec) {
			defer wg.Done()
			idx := spec.Index
			pPath := partFilePath(req.SavePath, idx)
			attempt := 0

			for {
				if segCtx.Err() != nil {
					mu.Lock()
					segActive[idx] = false
					if !segCompleted[idx] {
						segInfo[idx] = "Disconnected"
					}
					mu.Unlock()
					return
				}

				var currentSaved int64
				if fi, err := os.Stat(pPath); err == nil {
					currentSaved = fi.Size()
				}
				if currentSaved >= spec.Length() {
					mu.Lock()
					segDownloaded[idx] = spec.Length()
					segInfo[idx] = "Completed"
					segActive[idx] = false
					segCompleted[idx] = true
					mu.Unlock()
					emitSnapshot(true)
					return
				}

				rangeStart := spec.StartByte + currentSaved
				rangeEnd := spec.EndByte

				mu.Lock()
				segDownloaded[idx] = currentSaved
				if attempt == 0 {
					segInfo[idx] = "Connecting..."
				} else {
					segInfo[idx] = fmt.Sprintf("Reconnecting (%d/%d)...", attempt, maxRetries)
				}
				segActive[idx] = true
				segError[idx] = false
				mu.Unlock()
				emitSnapshot(true)

				httpReq, err := http.NewRequestWithContext(segCtx, http.MethodGet, effectiveURL, nil)
				if err != nil {
					setErr(err)
					return
				}
				e.applyConfiguredHeaders(httpReq, req.Username, req.Password)
				httpReq.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", rangeStart, rangeEnd))

				resp, err := e.client.Do(httpReq)
				if err != nil {
					if segCtx.Err() != nil {
						return
					}
					if attempt < maxRetries {
						attempt++
						mu.Lock()
						segInfo[idx] = fmt.Sprintf("Waiting for network (%d/%d)...", attempt, maxRetries)
						mu.Unlock()
						emitSnapshot(true)
						emit(ProgressEvent{Type: "reconnecting", Attempt: attempt})
						if CancellableSleep(segCtx, reconnectBackoff(attempt)) != nil {
							return
						}
						continue
					}
					mu.Lock()
					segInfo[idx] = "Error"
					segActive[idx] = false
					segError[idx] = true
					mu.Unlock()
					emitSnapshot(true)
					setErr(err)
					return
				}

				if resp.StatusCode != http.StatusPartialContent {
					_ = resp.Body.Close()
					err = fmt.Errorf("connection %d: server returned HTTP %d instead of 206", idx+1, resp.StatusCode)
					mu.Lock()
					segInfo[idx] = "Error"
					segActive[idx] = false
					segError[idx] = true
					mu.Unlock()
					emitSnapshot(true)
					setErr(err)
					return
				}

				mu.Lock()
				segInfo[idx] = "Receiving data..."
				segActive[idx] = true
				segError[idx] = false
				mu.Unlock()
				emitSnapshot(true)

				file, fErr := os.OpenFile(pPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
				if fErr != nil {
					_ = resp.Body.Close()
					setErr(fErr)
					return
				}

				bufPtr := ioBufPool.Get().(*[]byte)
				buf := *bufPtr
				var readErr error
				for {
					n, rErr := resp.Body.Read(buf)
					if n > 0 {
						rem := spec.Length() - currentSaved
						if rem <= 0 {
							break
						}
						writeN := int64(n)
						if writeN > rem {
							writeN = rem
						}
						if _, wErr := file.Write(buf[:writeN]); wErr != nil {
							readErr = wErr
							break
						}
						currentSaved += writeN
						mu.Lock()
						segDownloaded[idx] = currentSaved
						mu.Unlock()
						emitSnapshot(false)

						if limiter != nil {
							if tErr := limiter.Throttle(segCtx, writeN); tErr != nil {
								readErr = tErr
								break
							}
						}
						if currentSaved >= spec.Length() {
							break
						}
					}
					if rErr != nil {
						if !errors.Is(rErr, io.EOF) {
							readErr = rErr
						}
						break
					}
				}

				ioBufPool.Put(bufPtr)
				_ = file.Sync()
				_ = file.Close()
				_ = resp.Body.Close()

				if segCtx.Err() != nil {
					mu.Lock()
					segDownloaded[idx] = currentSaved
					segActive[idx] = false
					if !segCompleted[idx] {
						segInfo[idx] = "Disconnected"
					}
					mu.Unlock()
					return
				}

				if currentSaved >= spec.Length() {
					mu.Lock()
					segDownloaded[idx] = spec.Length()
					segInfo[idx] = "Completed"
					segActive[idx] = false
					segCompleted[idx] = true
					segError[idx] = false
					mu.Unlock()
					emitSnapshot(true)
					return
				}

				if attempt < maxRetries {
					attempt++
					mu.Lock()
					segInfo[idx] = fmt.Sprintf("Reconnecting (%d/%d)...", attempt, maxRetries)
					mu.Unlock()
					emitSnapshot(true)
					emit(ProgressEvent{Type: "reconnecting", Attempt: attempt})
					if CancellableSleep(segCtx, reconnectBackoff(attempt)) != nil {
						return
					}
					continue
				}

				if readErr == nil {
					readErr = fmt.Errorf("connection %d ended early (%d/%d bytes)", idx+1, currentSaved, spec.Length())
				}
				mu.Lock()
				segInfo[idx] = "Error"
				segActive[idx] = false
				segError[idx] = true
				mu.Unlock()
				emitSnapshot(true)
				setErr(readErr)
				return
			}
		}(spec)
	}

	wg.Wait()

	if ctx.Err() != nil {
		return ctx.Err()
	}
	if firstErr != nil {
		return firstErr
	}

	// Rebuild final file from segments
	emit(ProgressEvent{Type: "rebuilding", Received: resolvedTotal, Total: resolvedTotal})

	outFile, err := os.OpenFile(req.SavePath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	mergeBuf := make([]byte, 256*1024)
	for _, spec := range segments {
		inFile, inErr := os.Open(partFilePath(req.SavePath, spec.Index))
		if inErr != nil {
			_ = outFile.Close()
			return inErr
		}
		_, copyErr := io.CopyBuffer(outFile, inFile, mergeBuf)
		_ = inFile.Close()
		if copyErr != nil {
			_ = outFile.Close()
			return copyErr
		}
	}
	if err := outFile.Sync(); err != nil {
		_ = outFile.Close()
		return err
	}
	if err := outFile.Close(); err != nil {
		return err
	}

	for _, spec := range segments {
		_ = os.Remove(partFilePath(req.SavePath, spec.Index))
	}
	_ = os.Remove(sf)

	emitSnapshot(true)
	return nil
}
