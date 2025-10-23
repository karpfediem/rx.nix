package parse

import (
	"errors"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
)

type FieldInfo struct {
	GoName   string
	LangName string
	GoType   string
	Optional bool   // pointer type in Go
	Doc      string // field doc
}

type ResourceInfo struct {
	Name       string // e.g. "file"
	StructName string // e.g. "FileRes"
	Doc        string // struct doc
	Fields     []FieldInfo
}

type parsedPkg struct {
	files       []*ast.File
	importAlias map[*ast.File]map[string]string
}

func ParseResources(mgmtRoot string) (resources []ResourceInfo, err error) {
	resDir := filepath.Join(mgmtRoot, "engine", "resources")
	if st, e := os.Stat(resDir); e != nil || !st.IsDir() {
		return nil, errors.New("mgmt resources dir not found: " + resDir)
	}

	fset := token.NewFileSet()
	resPkg, err := parsePkgDir(fset, resDir)
	if err != nil {
		return nil, err
	}

	ifaceDir := filepath.Join(mgmtRoot, "engine", "interfaces")
	ifacePkg, _ := parsePkgDir(fset, ifaceDir) // ok if missing

	structMap := collectStructs(resPkg.files)
	localConsts := collectStringConsts(resPkg.files)
	ifaceConsts := collectStringConsts(ifacePkg.files)
	regMap := collectRegistrations(resPkg, localConsts, ifaceConsts)

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

	sort.Slice(resources, func(i, j int) bool { return resources[i].Name < resources[j].Name })
	return resources, nil
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
				if len(fields) > 0 {
					result[ts.Name.Name] = structInfo{doc: doc, fields: fields}
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
			continue
		}
		typ := exprToString(f.Type)
		optional := isPointerType(f.Type)
		doc := strings.TrimSpace(docText(f.Doc, f.Comment))
		out = append(out, FieldInfo{
			GoName:   goName,
			LangName: strings.ToLower(lang),
			GoType:   typ,
			Optional: optional, // not used for Nix nullability but kept for completeness
			Doc:      doc,
		})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].LangName < out[j].LangName })
	return out
}
