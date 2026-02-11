package server

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"

	"github.com/gokbeyinac/element/bridge/internal/detector"
	"github.com/gokbeyinac/element/bridge/internal/queue"
)

func newTestHandler() *Handler {
	q := queue.NewQueue(nil)
	bd := detector.NewBusyDetector(regexp.MustCompile(`test`), nil)

	return &Handler{
		queue:    q,
		detector: bd,
		inject:   func(text string, autoSubmit bool) error { return nil },
		isAlive:  func() bool { return true },
	}
}

func TestHealthEndpoint(t *testing.T) {
	h := newTestHandler()
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()

	h.Health(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}

	var resp healthResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode failed: %v", err)
	}
	if resp.Status != "ok" {
		t.Errorf("expected status 'ok', got %q", resp.Status)
	}
}

func TestStatusEndpoint(t *testing.T) {
	h := newTestHandler()
	req := httptest.NewRequest(http.MethodGet, "/status", nil)
	w := httptest.NewRecorder()

	h.Status(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}

	var resp statusResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode failed: %v", err)
	}
	if resp.ChildAlive != true {
		t.Error("expected child alive")
	}
	if resp.QueueLen != 0 {
		t.Errorf("expected queue len 0, got %d", resp.QueueLen)
	}
}

func TestInjectEndpoint(t *testing.T) {
	h := newTestHandler()

	body, _ := json.Marshal(injectRequest{Text: "hello world", Priority: false})
	req := httptest.NewRequest(http.MethodPost, "/inject", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	h.Inject(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}

	var resp injectResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode failed: %v", err)
	}
	if !resp.Success {
		t.Error("expected success")
	}
	if resp.ID == "" {
		t.Error("expected non-empty ID")
	}
}

func TestInjectEmptyText(t *testing.T) {
	h := newTestHandler()

	body, _ := json.Marshal(injectRequest{Text: ""})
	req := httptest.NewRequest(http.MethodPost, "/inject", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	h.Inject(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestInjectChildDead(t *testing.T) {
	h := newTestHandler()
	h.isAlive = func() bool { return false }

	body, _ := json.Marshal(injectRequest{Text: "test"})
	req := httptest.NewRequest(http.MethodPost, "/inject", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	h.Inject(w, req)

	if w.Code != http.StatusServiceUnavailable {
		t.Errorf("expected 503, got %d", w.Code)
	}
}

func TestClearQueueEndpoint(t *testing.T) {
	h := newTestHandler()

	body, _ := json.Marshal(injectRequest{Text: "item1"})
	injectReq := httptest.NewRequest(http.MethodPost, "/inject", bytes.NewReader(body))
	injectReq.Header.Set("Content-Type", "application/json")
	h.Inject(httptest.NewRecorder(), injectReq)

	req := httptest.NewRequest(http.MethodDelete, "/queue", nil)
	w := httptest.NewRecorder()

	h.ClearQueue(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}

	var resp clearResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode failed: %v", err)
	}
	if !resp.Success {
		t.Error("expected success")
	}
	if resp.Removed != 1 {
		t.Errorf("expected 1 removed, got %d", resp.Removed)
	}
}

func TestInjectInvalidJSON(t *testing.T) {
	h := newTestHandler()

	req := httptest.NewRequest(http.MethodPost, "/inject", bytes.NewReader([]byte("not json")))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	h.Inject(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}
