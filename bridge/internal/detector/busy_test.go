package detector

import (
	"regexp"
	"sync/atomic"
	"testing"
	"time"
)

func TestProcessOutputMatchesPattern(t *testing.T) {
	var idleCalled atomic.Int32
	bd := NewBusyDetector(
		regexp.MustCompile(`ready>`),
		func() { idleCalled.Add(1) },
	)
	bd.Start()
	defer bd.Stop()

	bd.ProcessOutput([]byte("some output ready> "))

	time.Sleep(600 * time.Millisecond)

	if !bd.IsIdle() {
		t.Error("expected idle after pattern match + threshold")
	}
	if idleCalled.Load() < 1 {
		t.Error("expected idle callback to be called")
	}
}

func TestNoMatchNoIdle(t *testing.T) {
	bd := NewBusyDetector(
		regexp.MustCompile(`ready>`),
		nil,
	)
	bd.Start()
	defer bd.Stop()

	bd.ProcessOutput([]byte("unrelated output"))

	time.Sleep(600 * time.Millisecond)

	if bd.IsIdle() {
		t.Error("should not be idle without pattern match")
	}
}

func TestMarkBusy(t *testing.T) {
	bd := NewBusyDetector(
		regexp.MustCompile(`ready>`),
		nil,
	)
	bd.Start()
	defer bd.Stop()

	bd.ProcessOutput([]byte("ready>"))
	time.Sleep(600 * time.Millisecond)

	if !bd.IsIdle() {
		t.Error("expected idle")
	}

	bd.MarkBusy()

	if bd.IsIdle() {
		t.Error("should not be idle after MarkBusy")
	}
}

func TestPatternForTool(t *testing.T) {
	tests := []struct {
		tool     string
		input    string
		expected bool
	}{
		{"claude", "esc to interrupt", true},
		{"claude", "other text", false},
		{"codex", "esc to interrupt", true},
		{"gemini", "esc to cancel", true},
		{"gemini", "esc to interrupt", false},
		{"unknown", "esc to interrupt", true},
		{"unknown", "esc to cancel", true},
	}

	for _, tt := range tests {
		p := PatternForTool(tt.tool)
		got := p.MatchString(tt.input)
		if got != tt.expected {
			t.Errorf("PatternForTool(%q).Match(%q) = %v, want %v", tt.tool, tt.input, got, tt.expected)
		}
	}
}

func TestCustomPattern(t *testing.T) {
	p, err := CustomPattern(`\$\s*$`)
	if err != nil {
		t.Fatalf("custom pattern failed: %v", err)
	}
	if !p.MatchString("$ ") {
		t.Error("expected pattern to match '$ '")
	}

	_, err = CustomPattern(`[invalid`)
	if err == nil {
		t.Error("expected error for invalid pattern")
	}
}
