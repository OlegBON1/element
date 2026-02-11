package queue

import (
	"sync/atomic"
	"testing"
	"time"
)

func TestEnqueueDequeue(t *testing.T) {
	q := NewQueue(nil)

	item, err := q.Enqueue("hello", false)
	if err != nil {
		t.Fatalf("enqueue failed: %v", err)
	}
	if item.Text != "hello" {
		t.Errorf("expected text 'hello', got %q", item.Text)
	}
	if item.ID == "" {
		t.Error("expected non-empty ID")
	}

	got, ok := q.Dequeue()
	if !ok {
		t.Fatal("dequeue returned false")
	}
	if got.Text != "hello" {
		t.Errorf("expected text 'hello', got %q", got.Text)
	}

	_, ok = q.Dequeue()
	if ok {
		t.Error("dequeue from empty queue should return false")
	}
}

func TestPriorityEnqueue(t *testing.T) {
	q := NewQueue(nil)

	_, _ = q.Enqueue("normal1", false)
	_, _ = q.Enqueue("normal2", false)
	_, _ = q.Enqueue("priority", true)

	got, _ := q.Dequeue()
	if got.Text != "priority" {
		t.Errorf("expected priority item first, got %q", got.Text)
	}

	got, _ = q.Dequeue()
	if got.Text != "normal1" {
		t.Errorf("expected normal1, got %q", got.Text)
	}

	got, _ = q.Dequeue()
	if got.Text != "normal2" {
		t.Errorf("expected normal2, got %q", got.Text)
	}
}

func TestQueueLen(t *testing.T) {
	q := NewQueue(nil)

	if q.Len() != 0 {
		t.Errorf("expected len 0, got %d", q.Len())
	}

	_, _ = q.Enqueue("a", false)
	_, _ = q.Enqueue("b", false)

	if q.Len() != 2 {
		t.Errorf("expected len 2, got %d", q.Len())
	}

	q.Dequeue()

	if q.Len() != 1 {
		t.Errorf("expected len 1, got %d", q.Len())
	}
}

func TestClear(t *testing.T) {
	q := NewQueue(nil)

	_, _ = q.Enqueue("a", false)
	_, _ = q.Enqueue("b", false)
	_, _ = q.Enqueue("c", false)

	removed := q.Clear()
	if removed != 3 {
		t.Errorf("expected 3 removed, got %d", removed)
	}
	if q.Len() != 0 {
		t.Errorf("expected empty queue after clear, got %d", q.Len())
	}
}

func TestQueueFull(t *testing.T) {
	q := NewQueue(nil)

	for i := 0; i < 100; i++ {
		_, err := q.Enqueue("item", false)
		if err != nil {
			t.Fatalf("enqueue %d failed: %v", i, err)
		}
	}

	_, err := q.Enqueue("overflow", false)
	if err == nil {
		t.Error("expected error when queue is full")
	}
}

func TestOnReadyCallback(t *testing.T) {
	var called atomic.Int32
	q := NewQueue(func() {
		called.Add(1)
	})

	_, _ = q.Enqueue("test", false)

	time.Sleep(50 * time.Millisecond)

	if called.Load() < 1 {
		t.Error("expected onReady callback to be called")
	}
}

func TestPosition(t *testing.T) {
	q := NewQueue(nil)

	item1, _ := q.Enqueue("first", false)
	item2, _ := q.Enqueue("second", false)

	if q.Position(item1.ID) != 0 {
		t.Errorf("expected position 0, got %d", q.Position(item1.ID))
	}
	if q.Position(item2.ID) != 1 {
		t.Errorf("expected position 1, got %d", q.Position(item2.ID))
	}
	if q.Position("nonexistent") != -1 {
		t.Error("expected -1 for nonexistent ID")
	}
}
