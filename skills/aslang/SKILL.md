---
name: aslang
description: AsLang / AgentScript language reference, S-expression syntax rules, MCP tools, and zero-shot LLM cheat sheet.
---

# AsLang / AgentScript Cheat Sheet (~500 tokens)

Deterministic S-expression language for autonomous AI agents. Compiles to WebAssembly (Main), TypeScript, Rust, Go, Python.

## 1. Syntax & Forms
- **Module:** `(module path/name :doc "..." :export [Sym ...] :import [(path/mod :as alias)])`
- **Schema:** `(defschema Name (:field key Type "doc") ...)` -> Immutable struct/class
- **Enum:** `(defenum Name (:case tag [(arg Type) ...] "doc") ...)` -> Algebraic sum type
- **Function:** `(defun name [(arg Type) ...] -> ReturnType :doc "..." body)`
- **Effect:** `(defun ! main [(args (List String))] -> (Result Unit IoError) body)` (I/O marker `!`)
- **Let:** `(let [(var val) ...] body)` (tail expression is return value)
- **Match:** `(match expr ((tag binder ...) expr) ...)` (must be exhaustive)
- **If/Cond:** `(if test then else)` | `(cond ((test1) val1) (:else fallback))`

## 2. Types
- **Scalars:** `Int32`, `Int64`, `Float64`, `Bool`, `String`, `Unit` (value `()`)
- **ADTs:** `(Option T)` (`(some v)`, `(none)`), `(Result T E)` (`(ok v)`, `(err e)`), `(Pair A B)`
- **Collections:** `(List T)` (`[1, 2]`), `(Map K V)` (`{"k": v}`)

## 3. Built-in Functions
- **Math:** `+`, `-`, `*`, `/`, `mod`, `abs`, `neg`, `f/sqrt`, `f/sin`, `f/cos`
- **String:** `s/concat`, `s/slice`, `s/trim`, `s/upper`, `s/lower`, `s/len`, `string-from-int64`
- **List:** `l/map`, `l/filter`, `l/fold`, `l/len`, `l/head`, `l/tail`, `cons`, `list`
- **Map:** `m/get`, `m/put`, `m/del`, `m/keys`, `m/values`, `m/len`
- **I/O:** `println`, `eprintln`, `file/read`, `file/write`, `file/append`, `file/exists`, `args`

## 4. MCP Server Tools (`tools/mcp/server.py`)
- `asex_check(source=...)`: In-memory type/semantic checker -> `{ valid, diagnostics }`
- `asex_eval(source=..., args=...)`: Instant in-memory interpreter eval (<1ms) -> `{ stdout, stderr, exit_code }`
- `asex_compress_module(source=...)`: AST compressor (-78% prompt tokens) -> `{ compressed }`
- `asex_format(source=...)`: Canonical S-expression layout formatter -> `{ formatted }`

## 5. Build CLI
```bash
agentscript init <dir> --template wasm
agentscript check <file>
agentscript build <file> --target wasm -o dist/main.wasm
agentscript build <file> --target ts|rs|go|py
agentscript fmt <dir>
```
