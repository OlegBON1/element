package main

import (
	"fmt"
	"io"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/spf13/cobra"

	"github.com/gokbeyinac/element/bridge/internal/bridge"
	"github.com/gokbeyinac/element/bridge/internal/config"
)

func main() {
	cfg := config.NewDefault()

	rootCmd := &cobra.Command{
		Use:   "element-bridge [flags] -- <command> [args...]",
		Short: "Bridge between Element app and terminal AI assistants",
		Long: `element-bridge wraps a terminal AI assistant (Claude Code, Codex, Gemini)
in a pseudo-terminal and exposes an HTTP API for text injection.
The Element macOS app uses this to send element source information
directly into the AI assistant.`,
		Version:            config.Version,
		Args:               cobra.MinimumNArgs(1),
		DisableFlagParsing: false,
		RunE: func(cmd *cobra.Command, args []string) error {
			return run(cfg, args[0], args[1:])
		},
	}

	flags := rootCmd.Flags()
	flags.IntVarP(&cfg.Port, "port", "p", config.DefaultPort, "HTTP server port")
	flags.StringVar(&cfg.Host, "host", config.DefaultHost, "HTTP server bind address")
	flags.StringVar(&cfg.BusyPattern, "busy-pattern", "", "Custom regex for idle detection")
	flags.IntVarP(&cfg.Timeout, "timeout", "t", config.DefaultTimeout, "Injection timeout in seconds")
	flags.IntVar(&cfg.InjectDelay, "inject-delay", config.InjectDelay, "Delay in ms before sending Enter")
	flags.BoolVar(&cfg.Paranoid, "paranoid", false, "Inject text without auto-submit")
	flags.BoolVarP(&cfg.Verbose, "verbose", "v", false, "Enable verbose logging")

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func run(cfg config.Config, command string, args []string) error {
	logger := setupLogger(cfg.Verbose)

	b := bridge.New(cfg, logger)

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM, syscall.SIGWINCH)

	go func() {
		for sig := range sigCh {
			switch sig {
			case syscall.SIGWINCH:
				b.HandleResize()
			case syscall.SIGINT, syscall.SIGTERM:
				b.Shutdown()
				os.Exit(0)
			}
		}
	}()

	if err := b.Start(command, args); err != nil {
		return fmt.Errorf("failed to start bridge: %w", err)
	}

	err := b.Wait()
	b.Shutdown()

	if err != nil {
		return fmt.Errorf("child process exited with error: %w", err)
	}
	return nil
}

func setupLogger(verbose bool) *log.Logger {
	if !verbose {
		return log.New(io.Discard, "", 0)
	}

	logFile, err := os.OpenFile("/tmp/element-bridge.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return log.New(os.Stderr, "[element-bridge] ", log.LstdFlags)
	}

	return log.New(logFile, "[element-bridge] ", log.LstdFlags)
}
