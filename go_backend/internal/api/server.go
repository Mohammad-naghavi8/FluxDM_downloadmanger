package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"sync"
	"sync/atomic"

	"dm_engine/internal/engine"
)

type activeTask struct {
	cancel  context.CancelFunc
	limiter *engine.SpeedLimiter
	paused  atomic.Bool
}

type Server struct {
	eng        *engine.Engine
	onShutdown func()

	mu     sync.Mutex
	active map[string]*activeTask
}

func NewServer(eng *engine.Engine, onShutdown func()) *Server {
	return &Server{
		eng:        eng,
		onShutdown: onShutdown,
		active:     make(map[string]*activeTask),
	}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.handleHealth)
	mux.HandleFunc("/api/probe", s.handleProbe)
	mux.HandleFunc("/api/downloads/stream", s.handleDownloadStream)
	mux.HandleFunc("/api/downloads/pause", s.handlePause)
	mux.HandleFunc("/api/downloads/cancel", s.handleCancel)
	mux.HandleFunc("/api/downloads/stop-all", s.handleStopAll)
	mux.HandleFunc("/api/downloads/limit", s.handleLimit)
	mux.HandleFunc("/api/downloads/cleanup", s.handleCleanup)
	mux.HandleFunc("/api/downloads/saved-progress", s.handleSavedProgress)
	mux.HandleFunc("/api/rss/fetch", s.handleRSSFetch)
	mux.HandleFunc("/api/torrent/parse", s.handleTorrentParse)
	mux.HandleFunc("/api/config", s.handleConfig)
	mux.HandleFunc("/api/archive/extract", s.handleArchiveExtract)
	mux.HandleFunc("/api/grab/links", s.handleGrabLinks)
	mux.HandleFunc("/api/grab/video", s.handleGrabVideo)
	mux.HandleFunc("/shutdown", s.handleShutdown)
	return mux
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":      true,
		"engine":  "go",
		"version": "1.0.0",
	})
}

func (s *Server) handleProbe(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST required"})
		return
	}
	var body struct {
		URL      string `json:"url"`
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}

	info, err := s.eng.Probe(r.Context(), body.URL, body.Username, body.Password)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, info)
}

func (s *Server) handleDownloadStream(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST required"})
		return
	}

	var req engine.DownloadRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	if req.ID == "" {
		req.ID = req.SavePath
	}

	flusher, ok := w.(http.Flusher)
	if !ok {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "streaming unsupported"})
		return
	}

	ctx, cancel := context.WithCancel(r.Context())
	limiter := engine.NewSpeedLimiter(req.SpeedLimitBytesPerSec)
	task := &activeTask{cancel: cancel, limiter: limiter}

	s.mu.Lock()
	if prev, exists := s.active[req.ID]; exists {
		prev.cancel()
	}
	s.active[req.ID] = task
	s.mu.Unlock()

	defer func() {
		cancel()
		s.mu.Lock()
		if current, exists := s.active[req.ID]; exists && current == task {
			delete(s.active, req.ID)
		}
		s.mu.Unlock()
	}()

	w.Header().Set("Content-Type", "application/x-ndjson")
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(http.StatusOK)

	var writeMu sync.Mutex
	sendEvent := func(ev engine.ProgressEvent) {
		writeMu.Lock()
		defer writeMu.Unlock()
		line, err := json.Marshal(ev)
		if err != nil {
			return
		}
		_, _ = w.Write(append(line, '\n'))
		flusher.Flush()
	}

	err := s.eng.Download(ctx, req, limiter, sendEvent)
	if err == nil {
		sendEvent(engine.ProgressEvent{
			Type:     "completed",
			Received: req.TotalBytes,
			Total:    req.TotalBytes,
		})
		return
	}

	if errors.Is(err, context.Canceled) || ctx.Err() != nil {
		if task.paused.Load() {
			dlBytes, conns, _ := engine.GetSavedProgress(req.SavePath, "Paused")
			sendEvent(engine.ProgressEvent{
				Type:        "paused",
				Received:    dlBytes,
				Total:       req.TotalBytes,
				Connections: conns,
			})
		} else {
			_ = engine.CleanupPartialFiles(req.SavePath)
			sendEvent(engine.ProgressEvent{
				Type:     "stopped",
				Received: 0,
				Total:    req.TotalBytes,
			})
		}
		return
	}

	sendEvent(engine.ProgressEvent{
		Type:  "error",
		Error: err.Error(),
	})
}

func (s *Server) handlePause(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ID string `json:"id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	s.mu.Lock()
	task := s.active[body.ID]
	s.mu.Unlock()
	if task != nil {
		task.paused.Store(true)
		task.cancel()
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) handleCancel(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ID string `json:"id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	s.mu.Lock()
	task := s.active[body.ID]
	s.mu.Unlock()
	if task != nil {
		task.paused.Store(false)
		task.cancel()
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) handleStopAll(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	for _, task := range s.active {
		task.paused.Store(false)
		task.cancel()
	}
	s.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) handleRSSFetch(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST required"})
		return
	}
	var body struct {
		URL string `json:"url"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	res, err := s.eng.FetchRSS(r.Context(), body.URL)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) handleTorrentParse(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST required"})
		return
	}
	var body struct {
		Source string `json:"source"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	info, err := engine.ParseTorrentSource(body.Source)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, info)
}

func (s *Server) handleConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST required"})
		return
	}
	var cfg engine.EngineConfig
	if err := json.NewDecoder(r.Body).Decode(&cfg); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	s.eng.ApplyConfig(cfg)
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) handleArchiveExtract(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST required"})
		return
	}
	var body struct {
		ArchivePath string `json:"archivePath"`
		TargetMode  string `json:"targetMode"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	res, err := engine.ExtractArchive(body.ArchivePath, body.TargetMode)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) handleGrabLinks(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST required"})
		return
	}
	var body struct {
		Input        string `json:"input"`
		ProbeOnline  bool   `json:"probeOnline"`
		HideWebPages bool   `json:"hideWebPages"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	res, err := s.eng.GrabLinks(r.Context(), body.Input, body.ProbeOnline, body.HideWebPages)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) handleGrabVideo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST required"})
		return
	}
	var body struct {
		URL string `json:"url"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	res, err := s.eng.GrabVideo(r.Context(), body.URL)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) handleLimit(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ID             string `json:"id"`
		BytesPerSecond int64  `json:"bytesPerSecond"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	s.mu.Lock()
	task := s.active[body.ID]
	s.mu.Unlock()
	if task != nil {
		task.limiter.SetLimit(body.BytesPerSecond)
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) handleCleanup(w http.ResponseWriter, r *http.Request) {
	var body struct {
		SavePath string `json:"savePath"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	_ = engine.CleanupPartialFiles(body.SavePath)
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) handleSavedProgress(w http.ResponseWriter, r *http.Request) {
	var body struct {
		SavePath    string `json:"savePath"`
		PausedLabel string `json:"pausedLabel"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	dlBytes, conns, hasSeg := engine.GetSavedProgress(body.SavePath, body.PausedLabel)
	writeJSON(w, http.StatusOK, map[string]any{
		"downloadedBytes":   dlBytes,
		"connections":       conns,
		"hasSegmentedState": hasSeg,
	})
}

func (s *Server) handleShutdown(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	for _, task := range s.active {
		task.cancel()
	}
	s.mu.Unlock()

	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	if s.onShutdown != nil {
		go s.onShutdown()
	}
}
