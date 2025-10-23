package parse

import (
	"errors"
	"go/ast"
	"go/printer"
	"go/token"
	"strings"
)

func collectStringConsts(files []*ast.File) map[string]string {
	out := make(map[string]string)
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
					if name == nil || i >= len(vs.Values) {
						continue
					}
					if bl, ok := vs.Values[i].(*ast.BasicLit); ok && bl.Kind == token.STRING {
						if s, err := strconvUnquote(bl.Value); err == nil {
							out[name.Name] = s
						}
					}
				}
			}
		}
	}
	// Resolve simple A=B chains
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
						if name == nil || i >= len(vs.Values) {
							continue
						}
						if _, done := out[name.Name]; done {
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
				resName = localConsts[a.Name]
			case *ast.SelectorExpr:
				if pkgIdent, ok := a.X.(*ast.Ident); ok {
					pkgPath := imports[pkgIdent.Name]
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
			if structName := returnStructName(fn.Body); structName != "" {
				out[resName] = structName
			}
			return true
		})
	}
	return out
}

func returnStructName(body *ast.BlockStmt) string {
	for _, stmt := range body.List {
		if ret, ok := stmt.(*ast.ReturnStmt); ok && len(ret.Results) != 0 {
			if ue, ok := ret.Results[0].(*ast.UnaryExpr); ok && ue.Op == token.AND {
				if cl, ok := ue.X.(*ast.CompositeLit); ok {
					switch t := cl.Type.(type) {
					case *ast.Ident:
						return t.Name
					case *ast.SelectorExpr:
						return t.Sel.Name
					}
				}
			}
		}
	}
	return ""
}

func docText(groups ...*ast.CommentGroup) string {
	var sb strings.Builder
	for _, g := range groups {
		if g == nil {
			continue
		}
		for _, c := range g.List {
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

func isPointerType(e ast.Expr) bool { _, ok := e.(*ast.StarExpr); return ok }

func exprToString(e ast.Expr) string {
	var sb strings.Builder
	printer.Fprint(&sb, token.NewFileSet(), e)
	return sb.String()
}

func strconvUnquote(s string) (string, error) {
	if len(s) < 2 {
		return "", errors.New("short string")
	}
	q := s[0]
	if q != '"' && q != '`' && q != '\'' {
		return "", errors.New("not quoted")
	}
	return strings.TrimSuffix(strings.TrimPrefix(s, string(q)), string(q)), nil
}
