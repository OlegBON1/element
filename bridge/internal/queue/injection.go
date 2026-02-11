package queue

import (
	"fmt"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gokbeyinac/element/bridge/internal/config"
)

type Injection struct {
	ID        string    `json:"id"`
	Text      string    `json:"text"`
	Priority  bool      `json:"priority"`
	CreatedAt time.Time `json:"created_at"`
}

type Queue struct {
	mu       sync.Mutex
	items    []Injection
	onReady  func()
}

func NewQueue(onReady func()) *Queue {
	return &Queue{
		items:   make([]Injection, 0),
		onReady: onReady,
	}
}

func (q *Queue) Enqueue(text string, priority bool) (Injection, error) {
	q.mu.Lock()
	defer q.mu.Unlock()

	if len(q.items) >= config.MaxQueueSize {
		return Injection{}, fmt.Errorf("queue is full (max %d)", config.MaxQueueSize)
	}

	item := Injection{
		ID:        uuid.New().String(),
		Text:      text,
		Priority:  priority,
		CreatedAt: time.Now(),
	}

	if priority {
		q.items = append([]Injection{item}, q.items...)
	} else {
		q.items = append(q.items, item)
	}

	if q.onReady != nil {
		go q.onReady()
	}

	return item, nil
}

func (q *Queue) Dequeue() (Injection, bool) {
	q.mu.Lock()
	defer q.mu.Unlock()

	if len(q.items) == 0 {
		return Injection{}, false
	}

	item := q.items[0]
	q.items = q.items[1:]
	return item, true
}

func (q *Queue) Len() int {
	q.mu.Lock()
	defer q.mu.Unlock()
	return len(q.items)
}

func (q *Queue) Clear() int {
	q.mu.Lock()
	defer q.mu.Unlock()

	removed := len(q.items)
	q.items = make([]Injection, 0)
	return removed
}

func (q *Queue) Position(id string) int {
	q.mu.Lock()
	defer q.mu.Unlock()

	for i, item := range q.items {
		if item.ID == id {
			return i
		}
	}
	return -1
}
