package main

import (
	"errors"
	"flag"
	"fmt"
	"go/ast"
	"go/parser"
	"go/printer"
	"go/token"
	"log"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"
)

type FieldInfo struct {
	GoName   string
	LangName string
	GoType   string
	Optional bool
	Doc      string // doc/comment from Go
}

type ResourceInfo struct {
	Name       string // mgmt resource name (e.g. "file", "docker:container")
	StructName string // Go struct name (e.g. "FileRes")
	Doc        string // doc on struct (if found)
	Fields     []FieldInfo
}

// --- flags

var (
	flagMgmtDir = flag.String("mgmt-dir", "", "Path to mgmt source root (repo checkout)")
	flagOutDir  = flag.String("out-dir", "", "Directory to write generated .nix files into")
)

// --- entry

func main() {
	log.SetFlags(0)
	flag.Parse()

	if *flagMgmtDir == "" || *flagOutDir == "" {
		log.Fatal("usage: options-generator -mgmt-dir /path/to/mgmt -out-dir /path/to/out")
	}

	resDir := filepath.Join(*flagMgmtDir, "engine", "resources")
	if st, err := os.Stat(resDir); err != nil || !st.IsDir() {
		log.Fatalf("mgmt resources dir not found: %s", resDir)
	}

	if err := os.MkdirAll(*flagOutDir, 0o755); err != nil {
		log.Fatalf("creating out dir: %v", err)
	}

	// Parse all .go files in the resources dir (non-recursive).
	fset := token.NewFileSet()
	resPkg, err := parsePkgDir(fset, resDir)
	if err != nil {
		log.Fatalf("parse resources: %v", err)
	}

	ifaceDir := filepath.Join(*flagMgmtDir, "engine", "interfaces")
	ifacePkg, err := parsePkgDir(fset, ifaceDir) // ok if missing
	if err != nil {
		// not fatal; some mgmt revisions might differ
		ifacePkg = &parsedPkg{}
	}

	// Build:
	// 1) structMap: struct name -> (doc, fields)
	// 2) regMap: resource name -> struct name (from RegisterResource calls)
	structMap := collectStructs(resPkg.files)
	localConsts := collectStringConsts(resPkg.files)
	ifaceConsts := collectStringConsts(ifacePkg.files)
	regMap := collectRegistrations(resPkg, localConsts, ifaceConsts)

	var resources []ResourceInfo
	for resName, structName := range regMap {
		if si, ok := structMap[structName]; ok {
			resources = append(resources, ResourceInfo{
				Name:       resName,
				StructName: structName,
				Doc:        si.doc,
				Fields:     si.fields,
			})
		}
	}
	// Stable order
	sort.Slice(resources, func(i, j int) bool { return resources[i].Name < resources[j].Name })

	// Generate per-resource nix files
	var generated []string
	for _, r := range resources {
		fn := filepath.Join(*flagOutDir, "res-"+sanitizeName(r.Name)+".nix")
		if err := writeResourceNix(fn, r); err != nil {
			log.Fatalf("write %s: %v", fn, err)
		}
		generated = append(generated, filepath.Base(fn))
	}

	// default.nix with imports
	if err := writeDefaultNix(filepath.Join(*flagOutDir, "default.nix"), generated); err != nil {
		log.Fatalf("write default.nix: %v", err)
	}
}

// --- parsing
type parsedPkg struct {
	files       []*ast.File
	importAlias map[*ast.File]map[string]string // per-file: local import name -> import path
}

func parsePkgDir(fset *token.FileSet, dir string) (*parsedPkg, error) {
	ents, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var out []*ast.File
	alias := make(map[*ast.File]map[string]string)
	for _, e := range ents {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			continue
		}
		fn := filepath.Join(dir, name)
		f, err := parser.ParseFile(fset, fn, nil, parser.ParseComments)
		if err != nil {
			continue
		}
		out = append(out, f)
		m := make(map[string]string)
		for _, is := range f.Imports {
			path, _ := strconvUnquote(is.Path.Value)
			local := ""
			if is.Name != nil && is.Name.Name != "_" && is.Name.Name != "." {
				local = is.Name.Name
			} else {
				// default local name from last path segment
				local = path
				if i := strings.LastIndex(local, "/"); i >= 0 {
					local = local[i+1:]
				}
			}
			m[local] = path
		}
		alias[f] = m
	}
	return &parsedPkg{files: out, importAlias: alias}, nil
}
func collectStringConsts(files []*ast.File) map[string]string {
	out := make(map[string]string)
	// First pass: direct string literals
	for _, f := range files {
		for _, d := range f.Decls {
			gd, ok := d.(*ast.GenDecl)
			if !ok || gd.Tok != token.CONST {
				continue
			}
			for _, sp := range gd.Specs {
				vs, ok := sp.(*ast.ValueSpec)
				if !ok {
					continue
				}
				for i, name := range vs.Names {
					if name == nil {
						continue
					}
					if i >= len(vs.Values) {
						continue
					}
					switch v := vs.Values[i].(type) {
					case *ast.BasicLit:
						if v.Kind == token.STRING {
							if s, err := strconvUnquote(v.Value); err == nil {
								out[name.Name] = s
							}
						}
					}
				}
			}
		}
	}
	// Second pass: resolve simple identifier chaining (A = B, B = "file")
	changed := true
	for changed {
		changed = false
		for _, f := range files {
			for _, d := range f.Decls {
				gd, ok := d.(*ast.GenDecl)
				if !ok || gd.Tok != token.CONST {
					continue
				}
				for _, sp := range gd.Specs {
					vs, ok := sp.(*ast.ValueSpec)
					if !ok {
						continue
					}
					for i, name := range vs.Names {
						if name == nil {
							continue
						}
						if _, done := out[name.Name]; done {
							continue
						}
						if i >= len(vs.Values) {
							continue
						}
						if id, ok := vs.Values[i].(*ast.Ident); ok {
							if val, ok := out[id.Name]; ok {
								out[name.Name] = val
								changed = true
							}
						}
					}
				}
			}
		}
	}
	return out
}

func parseGoFiles(fset *token.FileSet, dir string) ([]*ast.File, error) {
	ents, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var out []*ast.File
	for _, e := range ents {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			continue
		}
		// Parse with comments; we don’t care about build tags—this is best-effort AST only.
		fn := filepath.Join(dir, name)
		f, err := parser.ParseFile(fset, fn, nil, parser.ParseComments)
		if err != nil {
			// Don’t fail the whole run on a single file; mgmt includes some platform-specific code.
			continue
		}
		out = append(out, f)
	}
	return out, nil
}

// --- scan structs

type structInfo struct {
	doc    string
	fields []FieldInfo
}

func collectStructs(files []*ast.File) map[string]structInfo {
	result := make(map[string]structInfo)

	for _, f := range files {
		for _, decl := range f.Decls {
			gd, ok := decl.(*ast.GenDecl)
			if !ok || gd.Tok != token.TYPE {
				continue
			}
			for _, spec := range gd.Specs {
				ts, ok := spec.(*ast.TypeSpec)
				if !ok {
					continue
				}
				st, ok := ts.Type.(*ast.StructType)
				if !ok {
					continue
				}

				doc := strings.TrimSpace(docText(gd.Doc, ts.Doc))
				fields := extractLangFields(st)

				// Only store if there is at least one lang-tagged field; otherwise it’s probably not a resource
				if len(fields) > 0 {
					result[ts.Name.Name] = structInfo{
						doc:    doc,
						fields: fields,
					}
				}
			}
		}
	}
	return result
}

func extractLangFields(st *ast.StructType) []FieldInfo {
	var out []FieldInfo
	if st.Fields == nil {
		return out
	}
	for _, f := range st.Fields.List {
		// Skip embedded or unnamed fields
		if len(f.Names) == 0 {
			continue
		}
		goName := f.Names[0].Name
		lang := ""
		if f.Tag != nil {
			tag, err := strconvUnquote(f.Tag.Value)
			if err == nil {
				lang = reflect.StructTag(tag).Get("lang")
			}
		}
		if lang == "" {
			continue // only include lang-tagged fields
		}
		typ := exprToString(f.Type)
		optional := isPointerType(f.Type)

		doc := strings.TrimSpace(docText(f.Doc, f.Comment))

		out = append(out, FieldInfo{
			GoName:   goName,
			LangName: strings.ToLower(lang), // mgmt tags are already lower, normalize
			GoType:   typ,
			Optional: optional,
			Doc:      doc,
		})
	}
	// stable order by lang name
	sort.Slice(out, func(i, j int) bool { return out[i].LangName < out[j].LangName })
	return out
}

// --- scan RegisterResource calls

func collectRegistrations(resPkg *parsedPkg, localConsts, ifaceConsts map[string]string) map[string]string {
	out := make(map[string]string)

	for _, f := range resPkg.files {
		imports := resPkg.importAlias[f]

		ast.Inspect(f, func(n ast.Node) bool {
			call, ok := n.(*ast.CallExpr)
			if !ok {
				return true
			}
			sel, ok := call.Fun.(*ast.SelectorExpr)
			if !ok {
				return true
			}
			ident, ok := sel.X.(*ast.Ident)
			if !ok || ident.Name != "engine" || sel.Sel.Name != "RegisterResource" {
				return true
			}
			if len(call.Args) != 2 {
				return true
			}

			resName := ""
			switch a := call.Args[0].(type) {
			case *ast.BasicLit:
				if a.Kind == token.STRING {
					if s, err := strconvUnquote(a.Value); err == nil {
						resName = s
					}
				}
			case *ast.Ident:
				// local const
				resName = localConsts[a.Name]
			case *ast.SelectorExpr:
				// qualified const, eg: interfaces.PanicResKind
				pkgIdent, ok := a.X.(*ast.Ident)
				if ok {
					pkgPath := imports[pkgIdent.Name] // resolve local alias to full path
					// we only need interfaces for now
					if strings.HasSuffix(pkgPath, "/engine/interfaces") {
						resName = ifaceConsts[a.Sel.Name]
					}
				}
			}
			if resName == "" {
				return true
			}

			fn, ok := call.Args[1].(*ast.FuncLit)
			if !ok || fn.Body == nil {
				return true
			}
			structName := returnStructName(fn.Body)
			if structName == "" {
				return true
			}
			out[resName] = structName
			return true
		})
	}
	return out
}

// Try to find `return &SomeStruct{}` in the function body.
func returnStructName(body *ast.BlockStmt) string {
	for _, stmt := range body.List {
		ret, ok := stmt.(*ast.ReturnStmt)
		if !ok || len(ret.Results) == 0 {
			continue
		}
		ue, ok := ret.Results[0].(*ast.UnaryExpr)
		if !ok || ue.Op != token.AND {
			continue
		}
		cl, ok := ue.X.(*ast.CompositeLit)
		if !ok {
			continue
		}
		switch t := cl.Type.(type) {
		case *ast.Ident:
			return t.Name
		case *ast.SelectorExpr:
			// pkg.Type — we only need the Type
			return t.Sel.Name
		}
	}
	return ""
}

// --- helpers

func docText(groups ...*ast.CommentGroup) string {
	var sb strings.Builder
	for _, g := range groups {
		if g == nil {
			continue
		}
		for _, c := range g.List {
			// Trim leading // or /* */ and keep lines
			text := strings.TrimSpace(strings.TrimPrefix(c.Text, "//"))
			text = strings.TrimSpace(strings.TrimSuffix(strings.TrimPrefix(text, "/*"), "*/"))
			if sb.Len() > 0 {
				sb.WriteByte('\n')
			}
			sb.WriteString(text)
		}
	}
	return sb.String()
}

func isPointerType(e ast.Expr) bool {
	_, ok := e.(*ast.StarExpr)
	return ok
}

func exprToString(e ast.Expr) string {
	var sb strings.Builder
	printer.Fprint(&sb, token.NewFileSet(), e)
	return sb.String()
}

func strconvUnquote(s string) (string, error) {
	// ast gives us raw literal tokens like `"foo"` or '`bar`'
	if len(s) < 2 {
		return "", errors.New("short string literal")
	}
	quote := s[0]
	if quote != '"' && quote != '`' && quote != '\'' {
		return "", errors.New("not a quoted string")
	}
	return strings.TrimSuffix(strings.TrimPrefix(s, string(quote)), string(quote)), nil
}

var nonAlnum = regexp.MustCompile(`[^a-zA-Z0-9]+`)

func sanitizeName(s string) string {
	s = strings.ToLower(s)
	s = nonAlnum.ReplaceAllString(s, "-")
	s = strings.Trim(s, "-")
	if s == "" {
		s = "res"
	}
	return s
}

// --- emit Nix

func writeResourceNix(path string, r ResourceInfo) error {
	var b strings.Builder
	fmt.Fprintf(&b, "# Auto-generated by options-generator. Do not edit.\n")
	fmt.Fprintf(&b, "{ lib, ... }:\n")
	fmt.Fprintf(&b, "let\n  inherit (lib) mkOption types;\nin\n{\n")
	// Header option: options.rx.res.<name> = attrsOf (submodule …);
	fmt.Fprintf(&b, "  options.rx.res.%s = mkOption {\n", sanitizeIdent(r.Name))
	desc := r.Doc
	if desc == "" {
		desc = fmt.Sprintf("mgmt resource: %s (struct %s).", r.Name, r.StructName)
	}
	fmt.Fprintf(&b, "    description = ''%s'';\n", escapeNix(desc))
	fmt.Fprintf(&b, "    type = types.attrsOf (types.submodule ({ name, ... }: {\n")
	fmt.Fprintf(&b, "      options = {\n")

	for _, f := range r.Fields {
		nixType := nixTypeForGo(f.GoType, f.Optional)
		fmt.Fprintf(&b, "        %s = mkOption {\n", sanitizeIdent(f.LangName))
		fmt.Fprintf(&b, "          type = %s;\n", nixType)
		if f.Doc != "" {
			fmt.Fprintf(&b, "          description = ''%s'';\n", escapeNix(f.Doc))
		} else {
			fmt.Fprintf(&b, "          description = \"\";\n")
		}
		// No default here: optionality is expressed by types.nullOr; leaving it unset
		// keeps the option truly optional for downstream merges.
		fmt.Fprintf(&b, "        };\n")
	}

	fmt.Fprintf(&b, "      };\n")
	fmt.Fprintf(&b, "    }));\n")
	fmt.Fprintf(&b, "    default = {};\n")
	fmt.Fprintf(&b, "  };\n")
	fmt.Fprintf(&b, "}\n")

	return os.WriteFile(path, []byte(b.String()), 0o644)
}

func sanitizeIdent(s string) string {
	// Nix attribute names: we’ll allow letters, digits, _, -, and replace others with '-'.
	s = strings.ReplaceAll(s, ":", "-")
	s = strings.ReplaceAll(s, "/", "-")
	s = strings.ReplaceAll(s, ".", "-")
	return s
}

func escapeNix(s string) string {
	// First, escape any existing double single quotes (rare edge case)
	s = strings.ReplaceAll(s, "''", "''''")
	// Then escape single quotes to Nix's doubled prefix
	s = strings.ReplaceAll(s, "'", "'''")
	s = strings.ReplaceAll(s, "${", "''${")
	return s
}

func nixTypeForGo(goType string, _ bool) string {
	// Base type for the non-null case
	base := func() string {
		switch {
		case strings.HasPrefix(goType, "[]"):
			inner := strings.TrimPrefix(goType, "[]")
			return fmt.Sprintf("types.listOf %s", nixPrim(inner))
		case strings.HasPrefix(goType, "map["):
			return "types.attrsOf types.str" // simplification
		default:
			return nixPrim(goType)
		}
	}()

	// Make every field nullable in the generated Nix options.
	// The resulting modules are checked at runtime with custom validation logic.
	// This keeps our nix code much leaner.
	// We might still check this during generation of the MCL code by using the same validation function of mgmt.
	return fmt.Sprintf("types.nullOr (%s)", base)
}

func nixPrim(goType string) string {
	gt := strings.TrimSpace(goType)
	switch gt {
	case "string", "*string":
		return "types.str"
	case "bool", "*bool":
		return "types.bool"
	case "int", "int8", "int16", "int32", "int64",
		"uint", "uint8", "uint16", "uint32", "uint64":
		return "types.int"
	case "float32", "float64":
		return "types.float"
	default:
		// unknown/complex — accept as freeform string for now (can iterate later)
		return "types.str"
	}
}

func writeDefaultNix(path string, files []string) error {
	sort.Strings(files)
	var b strings.Builder
	fmt.Fprintf(&b, "# Auto-generated by options-generator. Do not edit.\n")
	fmt.Fprintf(&b, "{ lib, ... }: {\n")
	fmt.Fprintf(&b, "  imports = [\n")
	for _, f := range files {
		// skip any non .nix, just in case
		if !strings.HasSuffix(f, ".nix") || f == "default.nix" {
			continue
		}
		fmt.Fprintf(&b, "    ./%s\n", f)
	}
	fmt.Fprintf(&b, "  ];\n")
	fmt.Fprintf(&b, "}\n")
	return os.WriteFile(path, []byte(b.String()), 0o644)
}
