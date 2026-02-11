package detector

import "regexp"

type ToolPattern struct {
	Name    string
	Pattern *regexp.Regexp
}

var builtinPatterns = []ToolPattern{
	{
		Name:    "claude",
		Pattern: regexp.MustCompile(`esc to interrupt`),
	},
	{
		Name:    "codex",
		Pattern: regexp.MustCompile(`esc to interrupt`),
	},
	{
		Name:    "gemini",
		Pattern: regexp.MustCompile(`esc to cancel`),
	},
}

var defaultPattern = regexp.MustCompile(`esc to (interrupt|cancel)`)

func PatternForTool(name string) *regexp.Regexp {
	for _, tp := range builtinPatterns {
		if tp.Name == name {
			return tp.Pattern
		}
	}
	return defaultPattern
}

func CustomPattern(pattern string) (*regexp.Regexp, error) {
	return regexp.Compile(pattern)
}
