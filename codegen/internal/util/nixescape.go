package util

import "strings"

// EscapeIndentedNix escapes s so it is safe inside a Nix indented string: ” ... ”.
// For rules see https://nix.dev/manual/nix/latest/language/string-literals
//  1. "”"  → "”'"
//  2. "'"   → "”\"
//  3. "${"  → "”${"
//
// The algorithm scans left-to-right and never re-scans what it writes.
func EscapeIndentedNix(s string) string {
	var b strings.Builder
	b.Grow(len(s) * 2)

	for i := 0; i < len(s); {
		// Prevent interpolation: ${ -> ''${
		if s[i] == '$' && i+1 < len(s) && s[i+1] == '{' {
			b.WriteString("''${")
			i += 2
			continue
		}
		// Escape delimiter: '' -> '''
		if s[i] == '\'' && i+1 < len(s) && s[i+1] == '\'' {
			b.WriteString("'''")
			i += 2
			continue
		}
		// Everything else verbatim (including a single `'`)
		b.WriteByte(s[i])
		i++
	}
	return b.String()
}

// SanitizeAttrIdent makes a Nix attribute identifier from resource/field names.
func SanitizeAttrIdent(s string) string {
	s = strings.ReplaceAll(s, ":", "-")
	s = strings.ReplaceAll(s, "/", "-")
	s = strings.ReplaceAll(s, ".", "-")
	return s
}
