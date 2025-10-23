package ir

type Host struct {
	Imports []string                             `json:"imports"`
	Vars    map[string]any                       `json:"vars"`
	Raw     []string                             `json:"raw"`
	Res     map[string]map[string]map[string]any `json:"res"`
}

// Top-level: map[hostname]Host
type Document map[string]Host
