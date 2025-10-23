package mclgen

import (
	"bytes"
	"encoding/json"
	"fmt"
	"github.com/karpfediem/rx.nix/codegen/internal/ir"
	"sort"
	"strconv"
	"strings"
)

func RenderHost(name string, h ir.Host) ([]byte, error) {
	var buf bytes.Buffer
	fmt.Fprintf(&buf, "# Generated MCL for host %q\n\n", name)

	// imports
	if len(h.Imports) > 0 {
		imp := append([]string(nil), h.Imports...)
		sort.Strings(imp)
		for _, s := range imp {
			fmt.Fprintf(&buf, "import %q\n", s)
		}
		fmt.Fprintln(&buf)
	}

	// vars (strings treated as expressions)
	if len(h.Vars) > 0 {
		keys := sortedKeysAny(h.Vars)
		for _, k := range keys {
			v := h.Vars[k]
			switch vv := v.(type) {
			case string:
				fmt.Fprintf(&buf, "$%s = %s\n", k, strings.TrimSpace(vv))
			default:
				fmt.Fprintf(&buf, "$%s = %s\n", k, renderValue(v, 0, true))
			}
		}
		fmt.Fprintln(&buf)
	}

	// raw
	for _, s := range h.Raw {
		if !strings.HasSuffix(s, "\n") {
			s += "\n"
		}
		fmt.Fprint(&buf, s)
		if !strings.HasSuffix(s, "\n\n") {
			fmt.Fprintln(&buf)
		}
	}

	// resources
	if len(h.Res) > 0 {
		rKinds := sortedKeysMap(h.Res)
		for _, kind := range rKinds {
			insts := h.Res[kind]
			if len(insts) == 0 {
				continue
			}
			names := sortedKeysMap(insts)
			for _, inst := range names {
				fields := insts[inst]
				nonNull := make(map[string]any, len(fields))
				for k, v := range fields {
					if v != nil {
						nonNull[k] = v
					}
				}
				if len(nonNull) == 0 {
					continue
				}
				fmt.Fprintf(&buf, "%s %q {\n", kind, inst)
				fk := sortedKeysAny(nonNull)
				for _, k := range fk {
					lit := renderValue(nonNull[k], 1, false)
					fmt.Fprintf(&buf, "  %-8s => %s,\n", k, lit)
				}
				fmt.Fprintln(&buf, "}\n")
			}
		}
	}

	return buf.Bytes(), nil
}

func sortedKeysMap[K ~string, V any](m map[K]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, string(k))
	}
	sort.Strings(keys)
	return keys
}
func sortedKeysAny(m map[string]any) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func renderValue(v any, indentLevel int, topVar bool) string {
	switch x := v.(type) {
	case nil:
		return "null"
	case string:
		if topVar {
			return strings.TrimSpace(x)
		}
		return strconv.Quote(x)
	case bool:
		if x {
			return "true"
		}
		return "false"
	case json.Number:
		if _, err := x.Int64(); err == nil {
			return x.String()
		}
		if _, err := x.Float64(); err == nil {
			return x.String()
		}
		return strconv.Quote(x.String())
	case float64:
		s := fmt.Sprintf("%v", x)
		if strings.HasSuffix(s, ".0") {
			s = strings.TrimSuffix(s, ".0")
		}
		return s
	case int, int8, int16, int32, int64:
		return fmt.Sprintf("%d", x)
	case uint, uint8, uint16, uint32, uint64:
		return fmt.Sprintf("%d", x)
	case []any:
		if len(x) == 0 {
			return "[]"
		}
		var b strings.Builder
		b.WriteString("[")
		for i, el := range x {
			if i > 0 {
				b.WriteString(", ")
			}
			b.WriteString(renderValue(el, indentLevel+1, false))
		}
		b.WriteString("]")
		return b.String()
	case map[string]any:
		if len(x) == 0 {
			return "{}"
		}
		keys := make([]string, 0, len(x))
		for k := range x {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		indent := strings.Repeat("  ", indentLevel)
		inner := strings.Repeat("  ", indentLevel+1)
		var b strings.Builder
		b.WriteString("{\n")
		for _, k := range keys {
			b.WriteString(inner)
			if isBareIdent(k) {
				b.WriteString(k)
			} else {
				b.WriteString(strconv.Quote(k))
			}
			b.WriteString(": ")
			b.WriteString(renderValue(x[k], indentLevel+1, false))
			b.WriteString(",\n")
		}
		b.WriteString(indent)
		b.WriteString("}")
		return b.String()
	default:
		buf, err := json.Marshal(x)
		if err != nil {
			return strconv.Quote(fmt.Sprintf("%v", x))
		}
		return string(buf)
	}
}

func isBareIdent(s string) bool {
	if s == "" {
		return false
	}
	for i, r := range s {
		if !(r == '_' || r == '-' || r == '.' || r == ':' || r == '/' || r == '$' || isAlphaNum(r)) {
			return false
		}
		if i == 0 && (r >= '0' && r <= '9') {
			return false
		}
	}
	return true
}
func isAlphaNum(r rune) bool {
	return (r >= 'a' && r <= 'z') ||
		(r >= 'A' && r <= 'Z') ||
		(r >= '0' && r <= '9')
}
