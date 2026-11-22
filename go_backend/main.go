package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"runtime/debug"
	"syscall"
	"time"

	"dm_engine/internal/api"
	"dm_engine/internal/engine"
)

func main() {
	// Keep resident RAM minimal (~8-15 MB idle, <64 MiB soft cap under heavy load).
	debug.SetGCPercent(50)
	debug.SetMemoryLimit(64 << 20)

	port := flag.Int("port", 45822, "Local loopback port for the Go download engine")
	flag.Parse()

	addr := fmt.Sprintf("127.0.0.1:%d", *port)
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		log.Fatalf("failed to bind %s: %v", addr, err)
	}

	shutdownCh := make(chan struct{}, 1)
	triggerShutdown := func() {
		select {
		case shutdownCh <- struct{}{}:
		default:
		}
	}

	eng := engine.NewEngine()
	apiServer := api.NewServer(eng, triggerShutdown)

	httpServer := &http.Server{
		Handler: apiServer.Handler(),
	}

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)

	go func() {
		log.Printf("dm_engine listening on http://%s", addr)
		if serveErr := httpServer.Serve(listener); serveErr != nil && serveErr != http.ErrServerClosed {
			log.Fatalf("server error: %v", serveErr)
		}
	}()

	select {
	case <-sigCh:
	case <-shutdownCh:
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_ = httpServer.Shutdown(ctx)
}
