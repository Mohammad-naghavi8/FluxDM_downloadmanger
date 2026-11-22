package engine

import (
	"bytes"
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestSegmentedDownloadPauseResumeAndSpeedLimit(t *testing.T) {
	payload := make([]byte, 256*1024)
	for i := range payload {
		payload[i] = byte((i * 13) % 251)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Accept-Ranges", "bytes")
		w.Header().Set("Content-Disposition", `attachment; filename="test_go.bin"`)

		if r.Method == http.MethodHead {
			w.Header().Set("Content-Length", strconv.Itoa(len(payload)))
			w.WriteHeader(http.StatusOK)
			return
		}

		rangeHdr := r.Header.Get("Range")
		if strings.HasPrefix(rangeHdr, "bytes=") {
			parts := strings.Split(strings.TrimPrefix(rangeHdr, "bytes="), "-")
			start, _ := strconv.Atoi(parts[0])
			end := len(payload) - 1
			if len(parts) > 1 && parts[1] != "" {
				end, _ = strconv.Atoi(parts[1])
			}
			slice := payload[start : end+1]
			w.Header().Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, len(payload)))
			w.Header().Set("Content-Length", strconv.Itoa(len(slice)))
			w.WriteHeader(http.StatusPartialContent)

			flusher, _ := w.(http.Flusher)
			const chunk = 8 * 1024
			for off := 0; off < len(slice); off += chunk {
				hi := off + chunk
				if hi > len(slice) {
					hi = len(slice)
				}
				_, _ = w.Write(slice[off:hi])
				if flusher != nil {
					flusher.Flush()
				}
				time.Sleep(55 * time.Millisecond)
			}
			return
		}

		w.Header().Set("Content-Length", strconv.Itoa(len(payload)))
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(payload)
	}))
	defer server.Close()

	eng := NewEngine()
	ctx := context.Background()

	info, err := eng.Probe(ctx, server.URL+"/test_go.bin", "", "")
	if err != nil {
		t.Fatalf("Probe failed: %v", err)
	}
	if info.FileName != "test_go.bin" || info.FileSize == nil || *info.FileSize != int64(len(payload)) {
		t.Fatalf("unexpected probe info: %+v", info)
	}
	if !info.SupportsResume || !info.IsDirectDownload {
		t.Fatalf("expected resume & direct download true: %+v", info)
	}

	tmpDir := t.TempDir()
	savePath := filepath.Join(tmpDir, "test_go.bin")

	// Start 8-segment download and cancel mid-way to simulate Pause
	pauseCtx, cancelPause := context.WithCancel(ctx)
	maxConns := 0
	err = eng.Download(pauseCtx, DownloadRequest{
		ID:              "dl1",
		URL:             server.URL + "/test_go.bin",
		SavePath:        savePath,
		TotalBytes:      int64(len(payload)),
		ConnectionCount: 8,
		Segmented:       true,
	}, nil, func(ev ProgressEvent) {
		if len(ev.Connections) > maxConns {
			maxConns = len(ev.Connections)
		}
		if ev.Received >= 32*1024 {
			cancelPause()
		}
	})
	if err == nil {
		t.Fatalf("expected context cancel error on pause")
	}
	if maxConns != 8 {
		t.Fatalf("expected 8 parallel connections, got %d", maxConns)
	}

	savedBytes, conns, hasSeg := GetSavedProgress(savePath, "Paused")
	if !hasSeg || len(conns) != 8 || savedBytes <= 0 || savedBytes >= int64(len(payload)) {
		t.Fatalf("unexpected paused state: bytes=%d conns=%d hasSeg=%v", savedBytes, len(conns), hasSeg)
	}

	// Resume with SpeedLimiter and verify exact byte-for-byte file rebuild
	limiter := NewSpeedLimiter(512 * 1024)
	rebuilt := false
	err = eng.Download(ctx, DownloadRequest{
		ID:              "dl1",
		URL:             server.URL + "/test_go.bin",
		SavePath:        savePath,
		TotalBytes:      int64(len(payload)),
		ConnectionCount: 8,
		Segmented:       true,
		ResumeExisting:  true,
	}, limiter, func(ev ProgressEvent) {
		if ev.Type == "rebuilding" {
			rebuilt = true
		}
	})
	if err != nil {
		t.Fatalf("resume failed: %v", err)
	}
	if !rebuilt {
		t.Fatalf("expected rebuilding event")
	}

	got, err := os.ReadFile(savePath)
	if err != nil {
		t.Fatalf("read final file failed: %v", err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatalf("rebuilt file content mismatch")
	}
}
