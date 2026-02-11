package detector

import (
	"regexp"
	"sync"
	"time"

	"github.com/gokbeyinac/element/bridge/internal/config"
)

type IdleCallback func()

type BusyDetector struct {
	pattern       *regexp.Regexp
	mu            sync.RWMutex
	lastMatchTime time.Time
	idle          bool
	onIdle        IdleCallback
	stopCh        chan struct{}
	threshold     time.Duration
}

func NewBusyDetector(pattern *regexp.Regexp, onIdle IdleCallback) *BusyDetector {
	return &BusyDetector{
		pattern:   pattern,
		idle:      false,
		onIdle:    onIdle,
		stopCh:    make(chan struct{}),
		threshold: time.Duration(config.IdleThreshold) * time.Millisecond,
	}
}

func (bd *BusyDetector) ProcessOutput(data []byte) {
	if bd.pattern.Match(data) {
		bd.mu.Lock()
		bd.lastMatchTime = time.Now()
		bd.idle = false
		bd.mu.Unlock()
	}
}

func (bd *BusyDetector) Start() {
	ticker := time.NewTicker(time.Duration(config.CheckInterval) * time.Millisecond)
	go func() {
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				bd.checkIdle()
			case <-bd.stopCh:
				return
			}
		}
	}()
}

func (bd *BusyDetector) checkIdle() {
	bd.mu.Lock()
	defer bd.mu.Unlock()

	if bd.lastMatchTime.IsZero() {
		return
	}

	wasIdle := bd.idle
	bd.idle = time.Since(bd.lastMatchTime) >= bd.threshold

	if bd.idle && !wasIdle && bd.onIdle != nil {
		go bd.onIdle()
	}
}

func (bd *BusyDetector) IsIdle() bool {
	bd.mu.RLock()
	defer bd.mu.RUnlock()
	return bd.idle
}

func (bd *BusyDetector) MarkBusy() {
	bd.mu.Lock()
	defer bd.mu.Unlock()
	bd.idle = false
	bd.lastMatchTime = time.Time{}
}

func (bd *BusyDetector) Stop() {
	close(bd.stopCh)
}
