package main

import (
	"flag"
	"fmt"
	"github.com/karpfediem/rx.nix/codegen/internal/nixgen"
	"github.com/karpfediem/rx.nix/codegen/internal/parse"
	"github.com/karpfediem/rx.nix/codegen/internal/util"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

func main() {
	log.SetFlags(0)
	mgmtDir := flag.String("mgmt-dir", "", "Path to mgmt source root (repo checkout)")
	outDir := flag.String("out-dir", "", "Directory to write generated .nix files into")
	flag.Parse()

	if *mgmtDir == "" || *outDir == "" {
		log.Fatal("usage: nixos -mgmt-dir /path/to/mgmt -out-dir /path/to/out")
	}
	if err := os.MkdirAll(*outDir, 0o755); err != nil {
		log.Fatalf("creating out dir: %v", err)
	}

	resources, err := parse.ParseResources(*mgmtDir)
	if err != nil {
		log.Fatalf("parse resources: %v", err)
	}

	var generated []string
	for _, r := range resources {
		fn := filepath.Join(*outDir, "res-"+util.SanitizeAttrIdent(strings.ToLower(r.Name))+".nix")
		if err := nixgen.WriteResourceNix(fn, r); err != nil {
			log.Fatalf("write %s: %v", fn, err)
		}
		generated = append(generated, filepath.Base(fn))
	}

	sort.Strings(generated)
	if err := nixgen.WriteDefaultNix(filepath.Join(*outDir, "default.nix"), generated); err != nil {
		log.Fatalf("write default.nix: %v", err)
	}

	fmt.Printf("Generated %d resource modules into %s\n", len(generated), *outDir)
}
