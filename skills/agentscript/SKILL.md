---
name: agentscript
description: Developer skill and AI agent superpowers for AgentScript, including S-expression syntax rules, MCP tools, and zero-shot reference.
---

# AgentScript Developer Skill & Agent Superpowers

AgentScript is a strongly-typed, S-expression systems language designed specifically for **autonomous AI agents, single-pass LLM code generation, and zero-overhead WebAssembly execution**.

---

## 1. Agent Superpowers (Why Agents Use AgentScript)

1. **Zero Syntax Repair Loops (First-Run Pass Rate):**
   - S-expressions eliminate indentation pitfalls (Python), borrow-checker fights (Rust), and undefined-drift (JavaScript).
   - Balanced parentheses and explicit type signatures allow models to emit valid, working code on the **very first try**.
2. **Instant In-Memory Scratchpad (<1ms Execution):**
   - Agents can draft exploratory functions (math simulations, combinatorial searches, vector calculations) and run them in memory instantly via the reference interpreter or WebAssembly sandbox without risking host files or spinning up heavy Docker containers.
3. **Safe Batch VFS & AST Refactorings:**
   - Agents can perform mass code transformations in a virtual filesystem, validate them with `asex_check`, and synchronize to disk only when 100% verified clean.
4. **-78% Prompt Context Footprint (`asex_compress_module`):**
   - The entire language handbook (`prelude/HANDBOOK.md`) is only **~2,600 tokens** (compared to 30,000+ tokens for full language manuals), fitting easily into system prompts for zero-shot authoring.
   - Interface compression reduces loaded dependency context by 78%, enabling 4x larger multi-agent workspaces.

---

## 2. Core Language Rules & Cheat Sheet

```lisp
(module math/geometry
  :doc "2D Geometric calculations and shapes"
  :export [Point Shape area distance]
  :import [(core/math :as m)])

(defschema Point
  :doc "A 2D coordinate point"
  (:field x Float64 "X coordinate")
  (:field y Float64 "Y coordinate"))

(defenum Shape
  (:case circle    [(radius Float64)]                 "A circle")
  (:case rectangle [(width Float64) (height Float64)] "An axis-aligned rectangle")
  (:case point     []                                 "A zero-area point"))

(defun area [(s Shape)] -> Float64
  :doc "Calculate area with exhaustive pattern matching"
  (match s
    ((circle r)    (* (* r r) 3.141592653589793))
    ((rectangle w h) (* w h))
    ((point)       0.0)))

(defun ! main [(args (List String))] -> (Result Unit IoError)
  :doc "Effectful entrypoint tracking host I/O"
  (println "Calculations ready")
  (ok ()))
```

### Essential Syntax Rules:
1. **Modules Required:** Every file begins with `(module name/path :doc "..." :export [...] :import [...])`.
2. **Totality & Exhaustiveness:**
   - `match` must cover all enum/union cases exhaustively.
   - `if` always requires both then and else branches: `(if cond then-val else-val)`.
   - `cond` always requires `:else` branch.
3. **Fixed Numeric Types:** `Int32`, `Int64`, `Float64`. No implicit widening or narrowing.
4. **Let Bindings:** `(let [(var expr) ...] body)`.
5. **Effect Tracking (`!`):** Functions interacting with host/I/O must carry the effect marker `!` on their signature.

---

## 3. MCP Developer Tools (`tools/mcp/server.py`)
Available over JSON-RPC 2.0 stdio:
- **`asex_check(source=...)`**: Type-check and validate semantics in-memory.
- **`asex_eval(source=..., args=...)`**: Execute in-memory with reference interpreter (<1ms).
- **`asex_format(source=...)`**: Canonicalize S-expression formatting.
- **`asex_compress_module(source=...)`**: Compress module to interface signature (-78% tokens).
- **`asex_ast_query(source=..., query=...)`**: Execute Tree-sitter AST queries.

---

## 4. Multi-Target Compilation
```bash
# Build WebAssembly binary (Primary target)
agentscript build src/main.as --target wasm -o dist/main.wasm

# Transpile to TypeScript / Rust / Go / Python
agentscript build src/main.as --target ts
agentscript build src/main.as --target rs
agentscript build src/main.as --target go
agentscript build src/main.as --target py
```

---

## 5. Project Gates (Must pass before every commit)
```bash
.venv/bin/python grammar/validate.py
.venv/bin/python grammar/closure_audit.py
.venv/bin/python checker/gate.py
.venv/bin/python backend/check_corpus.py
.venv/bin/python backend/monomorphism.py
.venv/bin/python backend/differential.py
.venv/bin/pytest backend/tests checker/tests tools/tests -q
```
