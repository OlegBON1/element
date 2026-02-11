package pty

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"sync"
	"time"

	"github.com/creack/pty"
	"golang.org/x/term"
)

type OutputCallback func(data []byte)

type Manager struct {
	cmd        *exec.Cmd
	ptmx       *os.File
	mu         sync.Mutex
	running    bool
	onOutput   []OutputCallback
	oldState   *term.State
	injectDelay time.Duration
}

func NewManager(injectDelayMs int) *Manager {
	return &Manager{
		injectDelay: time.Duration(injectDelayMs) * time.Millisecond,
	}
}

func (m *Manager) OnOutput(cb OutputCallback) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.onOutput = append(m.onOutput, cb)
}

func (m *Manager) Start(command string, args []string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.cmd = exec.Command(command, args...)
	m.cmd.Env = os.Environ()

	ptmx, err := pty.Start(m.cmd)
	if err != nil {
		return fmt.Errorf("failed to start pty: %w", err)
	}
	m.ptmx = ptmx
	m.running = true

	oldState, err := term.MakeRaw(int(os.Stdin.Fd()))
	if err != nil {
		m.cleanup()
		return fmt.Errorf("failed to set raw terminal: %w", err)
	}
	m.oldState = oldState

	if err := m.syncSize(); err != nil {
		return fmt.Errorf("failed to sync terminal size: %w", err)
	}

	go m.copyStdinToPty()
	go m.copyPtyToStdout()

	return nil
}

func (m *Manager) syncSize() error {
	rows, cols, err := term.GetSize(int(os.Stdin.Fd()))
	if err != nil {
		return err
	}
	return pty.Setsize(m.ptmx, &pty.Winsize{
		Rows: uint16(rows),
		Cols: uint16(cols),
	})
}

func (m *Manager) HandleResize() error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.ptmx == nil {
		return nil
	}
	return m.syncSize()
}

func (m *Manager) copyStdinToPty() {
	_, _ = io.Copy(m.ptmx, os.Stdin)
}

func (m *Manager) copyPtyToStdout() {
	buf := make([]byte, 4096)
	for {
		n, err := m.ptmx.Read(buf)
		if n > 0 {
			data := make([]byte, n)
			copy(data, buf[:n])

			_, _ = os.Stdout.Write(data)

			m.mu.Lock()
			callbacks := make([]OutputCallback, len(m.onOutput))
			copy(callbacks, m.onOutput)
			m.mu.Unlock()

			for _, cb := range callbacks {
				cb(data)
			}
		}
		if err != nil {
			break
		}
	}
}

func (m *Manager) InjectText(text string, autoSubmit bool) error {
	m.mu.Lock()
	ptmx := m.ptmx
	running := m.running
	delay := m.injectDelay
	m.mu.Unlock()

	if !running || ptmx == nil {
		return fmt.Errorf("child process not running")
	}

	if _, err := ptmx.Write([]byte(text)); err != nil {
		return fmt.Errorf("failed to write text: %w", err)
	}

	if autoSubmit {
		time.Sleep(delay)
		if _, err := ptmx.Write([]byte("\r")); err != nil {
			return fmt.Errorf("failed to send enter: %w", err)
		}
	}

	return nil
}

func (m *Manager) IsRunning() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.running
}

func (m *Manager) Wait() error {
	if m.cmd == nil {
		return nil
	}
	err := m.cmd.Wait()

	m.mu.Lock()
	m.running = false
	m.mu.Unlock()

	return err
}

func (m *Manager) Stop() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.cleanup()
}

func (m *Manager) RestoreTerminal() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.oldState != nil {
		_ = term.Restore(int(os.Stdin.Fd()), m.oldState)
		m.oldState = nil
	}
}

func (m *Manager) cleanup() {
	if m.ptmx != nil {
		_ = m.ptmx.Close()
		m.ptmx = nil
	}
	if m.cmd != nil && m.cmd.Process != nil {
		_ = m.cmd.Process.Kill()
	}
	m.running = false
}
