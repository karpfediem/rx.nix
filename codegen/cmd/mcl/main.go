package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"github.com/karpfediem/rx.nix/codegen/internal/ir"
	"github.com/karpfediem/rx.nix/codegen/internal/mclgen"
	"io"
	"log"
	"os"
	"path/filepath"
	"sort"
)

func main() {
	log.SetFlags(0)

	inPath := flag.String("in", "-", "Input IR JSON file ('-' for stdin)")
	outDir := flag.String("out", "", "Output directory for generated <host>.mcl files (required)")
	flag.Parse()

	if *outDir == "" {
		log.Fatal("-out is required (directory where <host>.mcl files will be written)")
	}
	if err := os.MkdirAll(*outDir, 0o755); err != nil {
		log.Fatalf("create out dir: %v", err)
	}

	raw, err := readAll(*inPath)
	if err != nil {
		log.Fatalf("read IR: %v", err)
	}
	shape, err := detectShape(raw)
	if err != nil {
		log.Fatalf("detect IR shape: %v", err)
	}

	switch shape {
	case irShapeSingle:
		var h ir.Host
		if err := json.Unmarshal(raw, &h); err != nil {
			log.Fatalf("decode single-host IR: %v", err)
		}
		writeHost(*outDir, "main", h)

	case irShapeMulti:
		var doc ir.Document
		if err := json.Unmarshal(raw, &doc); err != nil {
			log.Fatalf("decode multi-host IR: %v", err)
		}
		hosts := make([]string, 0, len(doc))
		for k := range doc {
			hosts = append(hosts, k)
		}
		sort.Strings(hosts)
		for _, hn := range hosts {
			writeHost(*outDir, hn, doc[hn])
		}

	default:
		log.Fatalf("unsupported IR JSON: expected object")
	}
}

func writeHost(outDir, host string, h ir.Host) {
	data, err := mclgen.RenderHost(host, h)
	if err != nil {
		log.Fatalf("render host %q: %v", host, err)
	}
	fn := filepath.Join(outDir, host+".mcl")
	if err := os.WriteFile(fn, data, 0o644); err != nil {
		log.Fatalf("write %s: %v", fn, err)
	}
}

func readAll(path string) ([]byte, error) {
	if path == "-" || path == "" {
		return io.ReadAll(os.Stdin)
	}
	return os.ReadFile(path)
}

type irShape int

const (
	irShapeUnknown irShape = iota
	irShapeSingle
	irShapeMulti
)

func detectShape(raw []byte) (irShape, error) {
	// Must be a JSON object at top level
	i := 0
	for i < len(raw) && (raw[i] == ' ' || raw[i] == '\n' || raw[i] == '\t' || raw[i] == '\r') {
		i++
	}
	if i >= len(raw) || raw[i] != '{' {
		return irShapeUnknown, fmt.Errorf("top-level JSON must be an object")
	}
	// Probe minimal shape
	var probe map[string]any
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	if err := dec.Decode(&probe); err != nil {
		return irShapeUnknown, err
	}
	if hasAny(probe, "imports", "res", "raw", "vars") {
		return irShapeSingle, nil
	}
	return irShapeMulti, nil
}

func hasAny(m map[string]any, keys ...string) bool {
	for _, k := range keys {
		if _, ok := m[k]; ok {
			return true
		}
	}
	return false
}
