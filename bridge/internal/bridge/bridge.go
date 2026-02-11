package bridge

import (
	"context"
	"fmt"
	"log"
	"regexp"
	"time"

	"github.com/gokbeyinac/element/bridge/internal/config"
	"github.com/gokbeyinac/element/bridge/internal/detector"
	ptymanager "github.com/gokbeyinac/element/bridge/internal/pty"
	"github.com/gokbeyinac/element/bridge/internal/queue"
	"github.com/gokbeyinac/element/bridge/internal/server"
)

type Bridge struct {
	cfg      config.Config
	pty      *ptymanager.Manager
	queue    *queue.Queue
	detector *detector.BusyDetector
	server   *server.Server
	logger   *log.Logger
}

func New(cfg config.Config, logger *log.Logger) *Bridge {
	b := &Bridge{
		cfg:    cfg,
		pty:    ptymanager.NewManager(cfg.InjectDelay),
		logger: logger,
	}

	b.queue = queue.NewQueue(b.tryProcessQueue)

	var pattern *regexp.Regexp
	if cfg.BusyPattern != "" {
		var err error
		pattern, err = detector.CustomPattern(cfg.BusyPattern)
		if err != nil {
			logger.Printf("invalid busy pattern %q, using default: %v", cfg.BusyPattern, err)
			pattern = detector.PatternForTool("")
		}
	} else {
		pattern = detector.PatternForTool("")
	}

	b.detector = detector.NewBusyDetector(pattern, b.tryProcessQueue)

	b.pty.OnOutput(b.detector.ProcessOutput)

	b.server = server.New(cfg.Host, cfg.Port, server.Dependencies{
		Queue:    b.queue,
		Detector: b.detector,
		Inject:   b.pty.InjectText,
		IsAlive:  b.pty.IsRunning,
	})

	return b
}

func (b *Bridge) Start(command string, args []string) error {
	if err := b.server.Start(); err != nil {
		return fmt.Errorf("failed to start server: %w", err)
	}
	b.logger.Printf("HTTP server listening on %s:%d", b.cfg.Host, b.cfg.Port)

	b.detector.Start()
	b.logger.Printf("busy detector started")

	if err := b.pty.Start(command, args); err != nil {
		return fmt.Errorf("failed to start pty: %w", err)
	}
	b.logger.Printf("started child process: %s %v", command, args)

	return nil
}

func (b *Bridge) Wait() error {
	return b.pty.Wait()
}

func (b *Bridge) HandleResize() {
	if err := b.pty.HandleResize(); err != nil {
		b.logger.Printf("resize error: %v", err)
	}
}

func (b *Bridge) Shutdown() {
	b.logger.Printf("shutting down...")

	b.detector.Stop()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := b.server.Shutdown(ctx); err != nil {
		b.logger.Printf("server shutdown error: %v", err)
	}

	b.pty.Stop()
	b.pty.RestoreTerminal()
}

func (b *Bridge) tryProcessQueue() {
	if !b.detector.IsIdle() {
		return
	}
	if !b.pty.IsRunning() {
		return
	}

	item, ok := b.queue.Dequeue()
	if !ok {
		return
	}

	b.detector.MarkBusy()
	autoSubmit := !b.cfg.Paranoid

	b.logger.Printf("injecting [%s] (%d chars, autoSubmit=%v)", item.ID, len(item.Text), autoSubmit)

	if err := b.pty.InjectText(item.Text, autoSubmit); err != nil {
		b.logger.Printf("injection error [%s]: %v", item.ID, err)
	}
}
