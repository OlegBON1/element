package server

import (
	"encoding/json"
	"net/http"

	"github.com/gokbeyinac/element/bridge/internal/config"
	"github.com/gokbeyinac/element/bridge/internal/detector"
	"github.com/gokbeyinac/element/bridge/internal/queue"
)

type Handler struct {
	queue    *queue.Queue
	detector *detector.BusyDetector
	inject   func(text string, autoSubmit bool) error
	isAlive  func() bool
}

type healthResponse struct {
	Status  string `json:"status"`
	Version string `json:"version"`
}

type statusResponse struct {
	Idle       bool   `json:"idle"`
	QueueLen   int    `json:"queue_length"`
	ChildAlive bool   `json:"child_alive"`
	Version    string `json:"version"`
}

type injectRequest struct {
	Text     string `json:"text"`
	Priority bool   `json:"priority"`
}

type injectResponse struct {
	Success  bool   `json:"success"`
	ID       string `json:"id,omitempty"`
	Position int    `json:"position,omitempty"`
	Error    string `json:"error,omitempty"`
}

type clearResponse struct {
	Success bool `json:"success"`
	Removed int  `json:"removed"`
}

func (h *Handler) Health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, healthResponse{
		Status:  "ok",
		Version: config.Version,
	})
}

func (h *Handler) Status(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, statusResponse{
		Idle:       h.detector.IsIdle(),
		QueueLen:   h.queue.Len(),
		ChildAlive: h.isAlive(),
		Version:    config.Version,
	})
}

func (h *Handler) Inject(w http.ResponseWriter, r *http.Request) {
	var req injectRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, injectResponse{
			Success: false,
			Error:   "invalid request body",
		})
		return
	}

	if req.Text == "" {
		writeJSON(w, http.StatusBadRequest, injectResponse{
			Success: false,
			Error:   "text is required",
		})
		return
	}

	if !h.isAlive() {
		writeJSON(w, http.StatusServiceUnavailable, injectResponse{
			Success: false,
			Error:   "child process not running",
		})
		return
	}

	item, err := h.queue.Enqueue(req.Text, req.Priority)
	if err != nil {
		writeJSON(w, http.StatusTooManyRequests, injectResponse{
			Success: false,
			Error:   err.Error(),
		})
		return
	}

	writeJSON(w, http.StatusOK, injectResponse{
		Success:  true,
		ID:       item.ID,
		Position: h.queue.Position(item.ID),
	})
}

func (h *Handler) ClearQueue(w http.ResponseWriter, _ *http.Request) {
	removed := h.queue.Clear()
	writeJSON(w, http.StatusOK, clearResponse{
		Success: true,
		Removed: removed,
	})
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}
