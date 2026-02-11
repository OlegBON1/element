package server

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"time"

	"github.com/gokbeyinac/element/bridge/internal/detector"
	"github.com/gokbeyinac/element/bridge/internal/queue"
)

type Server struct {
	httpServer *http.Server
	handler    *Handler
}

type Dependencies struct {
	Queue    *queue.Queue
	Detector *detector.BusyDetector
	Inject   func(text string, autoSubmit bool) error
	IsAlive  func() bool
}

func New(host string, port int, deps Dependencies) *Server {
	handler := &Handler{
		queue:    deps.Queue,
		detector: deps.Detector,
		inject:   deps.Inject,
		isAlive:  deps.IsAlive,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", handler.Health)
	mux.HandleFunc("GET /status", handler.Status)
	mux.HandleFunc("POST /inject", handler.Inject)
	mux.HandleFunc("DELETE /queue", handler.ClearQueue)

	wrapped := corsMiddleware(mux)

	addr := fmt.Sprintf("%s:%d", host, port)
	httpServer := &http.Server{
		Addr:              addr,
		Handler:           wrapped,
		ReadHeaderTimeout: 10 * time.Second,
	}

	return &Server{
		httpServer: httpServer,
		handler:    handler,
	}
}

func (s *Server) Start() error {
	ln, err := net.Listen("tcp", s.httpServer.Addr)
	if err != nil {
		return fmt.Errorf("failed to listen on %s: %w", s.httpServer.Addr, err)
	}
	go func() {
		_ = s.httpServer.Serve(ln)
	}()
	return nil
}

func (s *Server) Shutdown(ctx context.Context) error {
	return s.httpServer.Shutdown(ctx)
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}
