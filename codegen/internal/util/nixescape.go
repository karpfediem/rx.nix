package util

import "strings"

// EscapeIndentedNix escapes a string for use inside Nix indented strings: ” ... ”.
func EscapeIndentedNix(s string) string {
	// Guard against ${...} interpolation in doc strings.
	s = strings.ReplaceAll(s, "${", "''${")
	// Single apostrophes -> doubled (indented string rule).
	s = strings.ReplaceAll(s, "'", "''")
	return s
}

// SanitizeAttrIdent makes a Nix attribute identifier from resource/field names.
func SanitizeAttrIdent(s string) string {
	s = strings.ReplaceAll(s, ":", "-")
	s = strings.ReplaceAll(s, "/", "-")
	s = strings.ReplaceAll(s, ".", "-")
	return s
}
