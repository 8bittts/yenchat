# shellcheck shell=bash
# Source-time pure AST helpers and command handlers for yen ide.

ast_supported_language() {
    local root="$1"
    local detected=""
    detected=$(ast_detected_language "${root}" 2>/dev/null || true)
    case "${detected}" in
        python|typescript|javascript|go|swift)
            printf "%s\n" "${detected}"
            ;;
        *)
            return 1
            ;;
    esac
}

ast_detected_language() {
    local root="$1"
    local detected=""
    detected=$(lsp_detected_language "${root}" 2>/dev/null || true)
    detected=$(lsp_normalize_language "${detected}" 2>/dev/null || printf "%s" "${detected}")
    case "${detected}" in
        javascript|typescript|python|go|rust|swift|zig)
            printf "%s\n" "${detected}"
            ;;
        *)
            return 1
            ;;
    esac
}

ast_source_label() {
    local root="$1"
    local language="$2"
    case "${language}" in
        python)
            printf "python-ast\n"
            ;;
        javascript|typescript)
            printf "typescript-compiler-api\n"
            ;;
        go)
            printf "go-parser\n"
            ;;
        swift)
            printf "swiftc-dump-ast-json\n"
            ;;
        *)
            printf "none\n"
            ;;
    esac
}

ast_ready_state() {
    local root="$1"
    local language="$2"
    case "${language}" in
        python)
            printf "yes\n"
            ;;
        javascript|typescript)
            if [[ -n "$(ast_typescript_module_dir "${root}" 2>/dev/null || true)" ]]; then
                printf "yes\n"
            else
                printf "no\n"
            fi
            ;;
        go)
            if command -v go >/dev/null 2>&1; then
                printf "yes\n"
            else
                printf "no\n"
            fi
            ;;
        swift)
            if command -v swiftc >/dev/null 2>&1; then
                printf "yes\n"
            else
                printf "no\n"
            fi
            ;;
        *)
            printf "no\n"
            ;;
    esac
}

ast_install_hint() {
    local language="$1"
    case "${language}" in
        python)
            printf "builtin\n"
            ;;
        javascript|typescript)
            printf "yen ide lsp install typescript\n"
            ;;
        go)
            printf "Install Go so the standard parser/token toolchain is available on PATH\n"
            ;;
        swift)
            printf "xcode-select --install  # or install a full Swift/Xcode toolchain with swiftc\n"
            ;;
        *)
            return 0
            ;;
    esac
}

ast_guidance_text() {
    local root="$1"
    local language="$2"
    local expected_server=""
    expected_server=$(lsp_expected_server "${root}")
    case "${language}" in
        python)
            printf "Python fallback uses the builtin python ast module.\n"
            ;;
        javascript|typescript)
            if [[ "$(ast_ready_state "${root}" "${language}")" == "yes" ]]; then
                printf "TypeScript-family fallback is ready through the local TypeScript compiler API.\n"
            else
                printf "TypeScript-family fallback needs the typescript package. Run: yen ide lsp install typescript\n"
            fi
            ;;
        go)
            if [[ "$(ast_ready_state "${root}" "${language}")" == "yes" ]]; then
                printf "Go fallback uses the standard-library go/parser and token APIs.\n"
            else
                printf "Go fallback needs the Go toolchain on PATH. Install Go and rerun.\n"
            fi
            ;;
        swift)
            if [[ "$(ast_ready_state "${root}" "${language}")" == "yes" ]]; then
                printf "Swift fallback uses swiftc -dump-ast-format json -dump-ast.\n"
            else
                printf "Swift fallback needs swiftc on PATH. Install Xcode command line tools or a full Swift toolchain.\n"
            fi
            ;;
        go|rust|swift|zig)
            printf "AST fallback is not shipped yet for %s. Use LSP status/install to bring %s online.\n" "${language}" "${expected_server:-the expected language server}"
            ;;
        *)
            printf "AST fallback currently supports Python, JavaScript/TypeScript, Go, and Swift projects.\n"
            ;;
    esac
}

ast_typescript_module_dir() {
    local root="$1"
    local managed_root=""
    managed_root=$(lsp_managed_tool_root "typescript" 2>/dev/null || true)
    if [[ -d "${managed_root}/node_modules/typescript" ]]; then
        printf "%s/node_modules\n" "${managed_root}"
        return 0
    fi
    if [[ -d "${root}/node_modules/typescript" ]]; then
        printf "%s/node_modules\n" "${root}"
        return 0
    fi
    if command -v npm >/dev/null 2>&1; then
        local global_root=""
        global_root=$(npm root -g 2>/dev/null || true)
        if [[ -d "${global_root}/typescript" ]]; then
            printf "%s\n" "${global_root}"
            return 0
        fi
    fi
    return 1
}

ast_query_rows_python() {
    local root="$1"
    local mode="$2"
    local symbol="$3"
    python3 - "${root}" "${mode}" "${symbol}" <<'PY'
import ast
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
mode = sys.argv[2]
symbol = sys.argv[3]
ignored = {".git", ".next", "DerivedData", "build", "dist", "ghostty", "node_modules", "target", "vendor", "zig-out"}

for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = sorted([name for name in dirnames if name not in ignored])
    for filename in sorted(filenames):
        if not filename.endswith(".py"):
            continue
        path = pathlib.Path(dirpath) / filename
        try:
            source_text = path.read_text(encoding="utf-8")
            tree = ast.parse(source_text)
        except Exception:
            continue
        source_lines = source_text.splitlines()
        for node in ast.walk(tree):
            if mode == "definition":
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and getattr(node, "name", "") == symbol:
                    line_text = source_lines[node.lineno - 1] if 0 < node.lineno <= len(source_lines) else ""
                    symbol_col = line_text.find(symbol)
                    col = symbol_col + 1 if symbol_col >= 0 else node.col_offset + 1
                    print("\t".join([str(path), str(node.lineno), str(col), f"{path}:{node.lineno}:{col}"]))
                if isinstance(node, ast.Name) and isinstance(getattr(node, "ctx", None), ast.Store) and node.id == symbol:
                    print("\t".join([str(path), str(node.lineno), str(node.col_offset + 1), f"{path}:{node.lineno}:{node.col_offset + 1}"]))
            elif mode == "references":
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and getattr(node, "name", "") == symbol:
                    line_text = source_lines[node.lineno - 1] if 0 < node.lineno <= len(source_lines) else ""
                    symbol_col = line_text.find(symbol)
                    col = symbol_col + 1 if symbol_col >= 0 else node.col_offset + 1
                    print("\t".join([str(path), str(node.lineno), str(col), f"{path}:{node.lineno}:{col}"]))
                if isinstance(node, ast.Name) and node.id == symbol:
                    print("\t".join([str(path), str(node.lineno), str(node.col_offset + 1), f"{path}:{node.lineno}:{node.col_offset + 1}"]))
PY
}

ast_query_rows_go() {
    local root="$1"
    local mode="$2"
    local symbol="$3"
    local tmp_dir=""
    local helper=""
    local output=""
    local status=0

    if ! command -v go >/dev/null 2>&1; then
        yen_error "Go AST queries require the Go toolchain on PATH. Install Go and rerun."
        return 1
    fi

    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/yen-ide-go-ast.XXXXXX")
    if [[ -z "${tmp_dir}" || ! -d "${tmp_dir}" ]]; then
        yen_error "Failed to create temporary Go AST workspace."
        return 1
    fi
    helper="${tmp_dir}/query.go"
    cat > "${helper}" <<'EOF'
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
)

type row struct {
	file string
	line int
	col  int
}

func main() {
	args := os.Args[1:]
	if len(args) > 0 && args[0] == "--" {
		args = args[1:]
	}
	if len(args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: query.go <root> <mode> <symbol>")
		os.Exit(1)
	}

	root, err := filepath.Abs(args[0])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	mode := args[1]
	symbol := args[2]
	ignored := map[string]bool{
		".git": true,
		".next": true,
		"DerivedData": true,
		"build": true,
		"dist": true,
		"ghostty": true,
		"node_modules": true,
		"target": true,
		"vendor": true,
		"zig-out": true,
	}

	files := make([]string, 0)
	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			if ignored[d.Name()] {
				return filepath.SkipDir
			}
			return nil
		}
		if filepath.Ext(d.Name()) == ".go" {
			files = append(files, path)
		}
		return nil
	})
	sort.Strings(files)

	seen := make(map[string]bool)
	rows := make([]row, 0)
	emit := func(pos token.Position) {
		if !pos.IsValid() {
			return
		}
		key := fmt.Sprintf("%s:%d:%d", pos.Filename, pos.Line, pos.Column)
		if seen[key] {
			return
		}
		seen[key] = true
		rows = append(rows, row{file: pos.Filename, line: pos.Line, col: pos.Column})
	}

	for _, filePath := range files {
		fset := token.NewFileSet()
		file, err := parser.ParseFile(fset, filePath, nil, parser.ParseComments)
		if err != nil {
			continue
		}
		ast.Inspect(file, func(n ast.Node) bool {
			switch node := n.(type) {
			case *ast.FuncDecl:
				if mode == "definition" && node.Name != nil && node.Name.Name == symbol {
					emit(fset.Position(node.Name.Pos()))
				}
			case *ast.TypeSpec:
				if mode == "definition" && node.Name != nil && node.Name.Name == symbol {
					emit(fset.Position(node.Name.Pos()))
				}
			case *ast.ValueSpec:
				if mode == "definition" {
					for _, name := range node.Names {
						if name != nil && name.Name == symbol {
							emit(fset.Position(name.Pos()))
						}
					}
				}
			case *ast.AssignStmt:
				if mode == "definition" && node.Tok == token.DEFINE {
					for _, expr := range node.Lhs {
						if ident, ok := expr.(*ast.Ident); ok && ident.Name == symbol {
							emit(fset.Position(ident.Pos()))
						}
					}
				}
			case *ast.Field:
				if mode == "definition" {
					for _, name := range node.Names {
						if name != nil && name.Name == symbol {
							emit(fset.Position(name.Pos()))
						}
					}
				}
			case *ast.Ident:
				if mode == "references" && node.Name == symbol {
					emit(fset.Position(node.Pos()))
				}
			}
			return true
		})
	}

	sort.Slice(rows, func(i, j int) bool {
		if rows[i].file != rows[j].file {
			return rows[i].file < rows[j].file
		}
		if rows[i].line != rows[j].line {
			return rows[i].line < rows[j].line
		}
		return rows[i].col < rows[j].col
	})

	for _, item := range rows {
		fmt.Printf("%s\t%d\t%d\t%s:%d:%d\n", item.file, item.line, item.col, item.file, item.line, item.col)
	}
}
EOF

    set +e
    output=$(go run "${helper}" -- "${root}" "${mode}" "${symbol}" 2>&1)
    status=$?
    set -e
    rm -rf "${tmp_dir}"

    if [[ "${status}" -ne 0 ]]; then
        yen_error "Go AST query failed: ${output}"
        return 1
    fi
    printf "%s\n" "${output}"
}

ast_query_rows_swift() {
    local root="$1"
    local mode="$2"
    local symbol="$3"

    if ! command -v swiftc >/dev/null 2>&1; then
        yen_error "Swift AST queries require swiftc on PATH. Install Xcode command line tools or a full Swift toolchain."
        return 1
    fi

    python3 - "${root}" "${mode}" "${symbol}" <<'PY'
import json
import os
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1]).resolve()
mode = sys.argv[2]
symbol = sys.argv[3]
ignored = {".git", ".next", "DerivedData", "build", "dist", "ghostty", "node_modules", "target", "vendor", "zig-out"}
definition_kinds = {
    "actor_decl",
    "class_decl",
    "enum_decl",
    "func_decl",
    "protocol_decl",
    "struct_decl",
    "subscript_decl",
    "typealias_decl",
    "var_decl",
}
reference_kinds = {
    "call_expr",
    "constructor_ref_call_expr",
    "declref_expr",
    "member_ref_expr",
    "type_expr",
    "unresolved_decl_ref_expr",
}
rows = []
seen = set()

def offset_to_line_col(source_text: str, offset: int):
    if offset < 0 or offset > len(source_text):
        return None
    line = source_text.count("\n", 0, offset) + 1
    line_start = source_text.rfind("\n", 0, offset)
    if line_start < 0:
        line_start = -1
    col = offset - line_start
    return line, col

def emit(path: pathlib.Path, source_text: str, offset: int):
    location = offset_to_line_col(source_text, offset)
    if location is None:
        return
    line, col = location
    key = (str(path), line, col)
    if key in seen:
        return
    seen.add(key)
    rows.append((str(path), line, col, f"{path}:{line}:{col}"))

def node_kind(node):
    if not isinstance(node, dict):
        return ""
    return str(node.get("_kind") or node.get("kind") or "")

def node_name(node):
    if not isinstance(node, dict):
        return ""
    name = node.get("name")
    if isinstance(name, str):
        return name
    if isinstance(name, dict):
        base_name = name.get("base_name")
        if isinstance(base_name, dict):
            value = base_name.get("name")
            if isinstance(value, str):
                return value
        value = name.get("name")
        if isinstance(value, str):
            return value
    return ""

def node_range(node):
    range_info = node.get("range") if isinstance(node, dict) else None
    if not isinstance(range_info, dict):
        return None, None
    start = range_info.get("start")
    end = range_info.get("end")
    if not isinstance(start, int):
        start = None
    if not isinstance(end, int):
        end = start
    return start, end

def find_name_offset(source_text: str, start: int, end: int, target: str):
    if start is None:
        return None
    start = max(0, start)
    if end is None or end < start:
        end = start
    search_end = min(len(source_text), end + len(target) + 64)
    location = source_text.find(target, start, search_end)
    if location >= 0:
        return location
    return None

def reference_offset(source_text: str, node):
    start, end = node_range(node)
    if start is not None and source_text.startswith(symbol, start):
        return start
    if start is None:
        return None
    return find_name_offset(source_text, start, end, symbol)

def visit(node, path: pathlib.Path, source_text: str):
    if isinstance(node, dict):
        kind = node_kind(node)
        if node_name(node) == symbol and kind in definition_kinds:
            start, end = node_range(node)
            offset = find_name_offset(source_text, start, end, symbol)
            if offset is not None:
                emit(path, source_text, offset)
        if mode == "references" and kind in reference_kinds:
            offset = reference_offset(source_text, node)
            if offset is not None:
                emit(path, source_text, offset)
        for value in node.values():
            visit(value, path, source_text)
    elif isinstance(node, list):
        for item in node:
            visit(item, path, source_text)

for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = sorted([name for name in dirnames if name not in ignored])
    for filename in sorted(filenames):
        if not filename.endswith(".swift"):
            continue
        path = pathlib.Path(dirpath) / filename
        try:
            source_text = path.read_text(encoding="utf-8")
        except Exception:
            continue
        result = subprocess.run(
            ["swiftc", "-dump-ast-format", "json", "-dump-ast", str(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if result.returncode != 0 or not result.stdout.strip():
            continue
        try:
            payload = json.loads(result.stdout)
        except Exception:
            continue
        visit(payload, path, source_text)

rows.sort(key=lambda item: (item[0], item[1], item[2]))
for file_path, line, col, location in rows:
    print("\t".join([file_path, str(line), str(col), location]))
PY
}

ast_query_rows_typescript() {
    local root="$1"
    local language="$2"
    local mode="$3"
    local symbol="$4"
    local node_modules_dir=""
    node_modules_dir=$(ast_typescript_module_dir "${root}" 2>/dev/null || true)
    if [[ -z "${node_modules_dir}" ]]; then
        yen_error "TypeScript AST queries require the typescript package. Run: yen ide lsp install typescript"
        return 1
    fi
    NODE_PATH="${node_modules_dir}" node - "${root}" "${language}" "${mode}" "${symbol}" <<'JS'
const fs = require("fs");
const path = require("path");
const ts = require("typescript");

const root = path.resolve(process.argv[2]);
const language = process.argv[3];
const mode = process.argv[4];
const symbol = process.argv[5];
const allowed = language === "typescript"
  ? new Set([".ts", ".tsx", ".mts", ".cts"])
  : new Set([".js", ".jsx", ".mjs", ".cjs"]);
const ignored = new Set([".git", ".next", "DerivedData", "build", "dist", "ghostty", "node_modules", "target", "vendor", "zig-out"]);

function walk(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!ignored.has(entry.name)) {
        walk(path.join(dir, entry.name), out);
      }
      continue;
    }
    if (allowed.has(path.extname(entry.name))) {
      out.push(path.join(dir, entry.name));
    }
  }
}

const files = [];
walk(root, files);
files.sort();

function printNode(filePath, node) {
  const source = sourceFileMap.get(filePath);
  const position = ts.getLineAndCharacterOfPosition(source, node.getStart(source));
  const line = position.line + 1;
  const col = position.character + 1;
  process.stdout.write(`${filePath}\t${line}\t${col}\t${filePath}:${line}:${col}\n`);
}

const sourceFileMap = new Map();
for (const filePath of files) {
  let sourceText = "";
  try {
    sourceText = fs.readFileSync(filePath, "utf8");
  } catch {
    continue;
  }
  const sourceFile = ts.createSourceFile(filePath, sourceText, ts.ScriptTarget.Latest, true);
  sourceFileMap.set(filePath, sourceFile);
  function visit(node) {
    if (mode === "definition") {
      if (
        (ts.isFunctionDeclaration(node) ||
          ts.isClassDeclaration(node) ||
          ts.isInterfaceDeclaration(node) ||
          ts.isTypeAliasDeclaration(node) ||
          ts.isEnumDeclaration(node)) &&
        node.name &&
        node.name.text === symbol
      ) {
        printNode(filePath, node.name);
      }
      if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.name.text === symbol) {
        printNode(filePath, node.name);
      }
    } else if (mode === "references") {
      if (ts.isIdentifier(node) && node.text === symbol) {
        printNode(filePath, node);
      }
    }
    ts.forEachChild(node, visit);
  }
  visit(sourceFile);
}
JS
}

ast_query_rows() {
    local root="$1"
    local language="$2"
    local mode="$3"
    local symbol="$4"

    case "${language}" in
        python)
            ast_query_rows_python "${root}" "${mode}" "${symbol}"
            ;;
        go)
            ast_query_rows_go "${root}" "${mode}" "${symbol}"
            ;;
        swift)
            ast_query_rows_swift "${root}" "${mode}" "${symbol}"
            ;;
        javascript|typescript)
            ast_query_rows_typescript "${root}" "${language}" "${mode}" "${symbol}"
            ;;
        *)
            yen_error "AST queries are unsupported for ${language}."
            return 1
            ;;
    esac
}

cmd_ast_status() {
    local target=""
    local root=""
    local language=""
    local supported_language=""
    local ready_state=""
    local source_label=""
    local install_hint=""
    local guidance=""
    local expected_server=""
    local typescript_modules=""
    local lsp_install_hint=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            *)
                target="$1"
                ;;
        esac
        shift
    done

    root=$(find_project_root "${target}")
    language=$(ast_detected_language "${root}" 2>/dev/null || true)
    supported_language=$(ast_supported_language "${root}" 2>/dev/null || true)
    source_label=$(ast_source_label "${root}" "${language:-unknown}")
    ready_state=$(ast_ready_state "${root}" "${language:-unknown}")
    install_hint=$(ast_install_hint "${language:-unknown}")
    guidance=$(ast_guidance_text "${root}" "${language:-unknown}")
    expected_server=$(lsp_expected_server "${root}")
    lsp_install_hint=$(lsp_install_command_text "${language:-unknown}" 2>/dev/null || true)
    echo ""
    yen_header "IDE AST Status"
    echo "Root:     ${root}"
    if [[ -z "${supported_language}" ]]; then
        if [[ -n "${language}" ]]; then
            echo "Language:  ${language}"
        fi
        echo "Supported: no"
        echo "Ready:     no"
        echo "Source:    ${source_label}"
        if [[ -n "${expected_server}" ]]; then
            echo "LSP:       ${expected_server}"
        fi
        if [[ -n "${lsp_install_hint}" ]]; then
            echo "Install:   ${lsp_install_hint}"
        fi
        echo "Guidance:  ${guidance}"
        echo ""
        return 0
    fi
    echo "Supported: yes"
    echo "Language:  ${supported_language}"
    echo "Ready:     ${ready_state}"
    if [[ "${supported_language}" == "python" ]]; then
        echo "Source:    ${source_label}"
        echo "Install:   ${install_hint}"
    elif [[ "${supported_language}" == "javascript" || "${supported_language}" == "typescript" ]]; then
        typescript_modules=$(ast_typescript_module_dir "${root}" 2>/dev/null || true)
        echo "Source:    ${source_label}"
        if [[ -n "${typescript_modules}" ]]; then
            echo "Module:    ${typescript_modules}"
        else
            echo "Install:   ${install_hint}"
        fi
    else
        echo "Source:    ${source_label}"
        if [[ "${ready_state}" != "yes" && -n "${install_hint}" ]]; then
            echo "Install:   ${install_hint}"
        fi
    fi
    if [[ -n "${expected_server}" ]]; then
        echo "LSP:       ${expected_server}"
    fi
    echo "Guidance:  ${guidance}"
    echo ""
}

cmd_ast_definition() {
    local symbol="${1:-}"
    local target="${2:-}"
    local root=""
    local language=""
    local source_label=""
    local rows=""
    local count="0"
    if [[ -z "${symbol}" ]]; then
        yen_error "ast definition requires a symbol. Example: yen ide ast definition settingsController"
        return 1
    fi
    root=$(find_project_root "${target}")
    language=$(ast_supported_language "${root}" 2>/dev/null || true)
    source_label=$(ast_source_label "${root}" "${language:-unknown}")
    if [[ -z "${language}" ]]; then
        yen_error "AST definition is unsupported for this project."
        return 1
    fi
    if ! rows=$(ast_query_rows "${root}" "${language}" "definition" "${symbol}" 2>&1); then
        yen_error "${rows}"
        return 1
    fi
    if [[ -z "${rows}" ]]; then
        yen_info "No AST definition match for '${symbol}'"
        return 0
    fi
    count=$(printf "%s\n" "${rows}" | sed '/^$/d' | wc -l | tr -d '[:space:]')
    timeline_log "ast-definition" "${root}" "hits=${count}" "symbol=${symbol};language=${language}"
    echo ""
    yen_header "IDE AST Definition"
    echo "Root:      ${root}"
    echo "Language:  ${language}"
    echo "Source:    ast"
    echo "Engine:    ${source_label}"
    echo "Results:   ${count}"
    echo ""
    printf "%-7s %-7s %s\n" "LINE" "COL" "LOCATION"
    while IFS=$'\t' read -r _ line_value col_value location; do
        [[ -z "${location}" ]] && continue
        printf "%-7s %-7s %s\n" "${line_value}" "${col_value}" "${location}"
    done << EOF
${rows}
EOF
    echo ""
}

cmd_ast_references() {
    local symbol="${1:-}"
    local target="${2:-}"
    local root=""
    local language=""
    local source_label=""
    local rows=""
    local count="0"
    if [[ -z "${symbol}" ]]; then
        yen_error "ast references requires a symbol. Example: yen ide ast references settingsController"
        return 1
    fi
    root=$(find_project_root "${target}")
    language=$(ast_supported_language "${root}" 2>/dev/null || true)
    source_label=$(ast_source_label "${root}" "${language:-unknown}")
    if [[ -z "${language}" ]]; then
        yen_error "AST references are unsupported for this project."
        return 1
    fi
    if ! rows=$(ast_query_rows "${root}" "${language}" "references" "${symbol}" 2>&1); then
        yen_error "${rows}"
        return 1
    fi
    if [[ -z "${rows}" ]]; then
        yen_info "No AST references found for '${symbol}'"
        return 0
    fi
    count=$(printf "%s\n" "${rows}" | sed '/^$/d' | wc -l | tr -d '[:space:]')
    timeline_log "ast-references" "${root}" "hits=${count}" "symbol=${symbol};language=${language}"
    echo ""
    yen_header "IDE AST References"
    echo "Root:      ${root}"
    echo "Language:  ${language}"
    echo "Source:    ast"
    echo "Engine:    ${source_label}"
    echo "Results:   ${count}"
    echo ""
    printf "%-7s %-7s %s\n" "LINE" "COL" "LOCATION"
    while IFS=$'\t' read -r _ line_value col_value location; do
        [[ -z "${location}" ]] && continue
        printf "%-7s %-7s %s\n" "${line_value}" "${col_value}" "${location}"
    done << EOF
${rows}
EOF
    echo ""
}

cmd_ast() {
    local sub="${1:-status}"
    shift || true
    case "${sub}" in
        status)
            cmd_ast_status "$@"
            ;;
        definition)
            cmd_ast_definition "$@"
            ;;
        references)
            cmd_ast_references "$@"
            ;;
        *)
            yen_error "Unknown ast subcommand: ${sub}"
            return 1
            ;;
    esac
}
