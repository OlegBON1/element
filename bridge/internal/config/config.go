package config

const (
	Version        = "0.1.0"
	DefaultPort    = 9999
	DefaultHost    = "127.0.0.1"
	DefaultTimeout = 300
	MaxQueueSize   = 100
	IdleThreshold  = 500  // milliseconds
	InjectDelay    = 50   // milliseconds before sending Enter
	CheckInterval  = 100  // milliseconds between idle checks
)

type Config struct {
	Port         int
	Host         string
	BusyPattern  string
	Timeout      int
	InjectDelay  int
	Paranoid     bool
	Verbose      bool
}

func NewDefault() Config {
	return Config{
		Port:        DefaultPort,
		Host:        DefaultHost,
		Timeout:     DefaultTimeout,
		InjectDelay: InjectDelay,
		Paranoid:    false,
		Verbose:     false,
	}
}
