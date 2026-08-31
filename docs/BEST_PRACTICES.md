# ASL (AgentScript Language) Best Practices & Integration Recipes

A practical guide for software engineers, AI agent developers, and vibe-coders building production systems with ASL.

---

## 1. Core Idioms & Best Practices

### Rule 1: Single-Pass S-Expression Design
* **Derivations Precede Results:** In ASL, body expressions evaluate sequentially, and the tail expression is the return value. Place bindings and assertions before the final result.
* **Exhaustive Matching:** Always handle every enum variant in `match`. Never rely on default catch-alls unless explicitly necessary.
* **Fixed Bitwidths:** Choose between `Int32`, `Int64`, or `Float64` deliberately. ASL prohibits implicit conversions to eliminate silent numeric drift.

### Rule 2: Explicit Effect Boundaries (`!`)
* Keep computational domain logic **pure**.
* Mark functions that touch files, stdout/stderr, environment variables, or host clocks with the `!` marker:
  ```lisp
  ; Pure function (no marker)
  (defun calculate-discount [(price Float64) (rate Float64)] -> Float64
    (* price (- 1.0 rate)))

  ; Effectful entrypoint (explicit !)
  (defun ! main [(args (List String))] -> (Result Unit IoError)
    (println "Starting calculation...")
    (ok ()))
  ```

---

## 2. Integration Recipes

### Recipe 1: In-Browser WebAssembly Sandbox (React / TypeScript)

Execute user or agent-generated ASL code directly inside a browser without server calls:

```typescript
import { runWasmInBrowser } from './wasm_runner';

async function executeAgentCode(wasmBinaryUrl: string) {
  const response = await fetch(wasmBinaryUrl);
  const wasmBytes = await response.arrayBuffer();

  // Run in lightweight in-memory WASI sandbox (<1ms execution)
  const result = await runWasmInBrowser(wasmBytes, ["app"], "optional stdin");
  
  console.log("Exit Code:", result.exitCode);
  console.log("Stdout:", result.stdout);
  console.log("Duration:", result.durationMs, "ms");
}
```

---

### Recipe 2: Autonomous Agent MCP Tooling Workflow

Connect the ASL MCP Server (`tools/mcp/server.py`) to Claude Desktop, Cursor, or your autonomous agent harness:

```json
{
  "mcpServers": {
    "asl": {
      "command": "python3",
      "args": ["/path/to/asl/tools/mcp/server.py"]
    }
  }
}
```

**Recommended Agent Execution Loop:**
1. Agent generates an S-expression module.
2. Agent calls `asex_check(source)` to verify types in-memory.
3. If errors exist, diagnostic JSON points to exact line/column with rule name (`09-rule`).
4. Agent calls `asex_eval(source)` to verify return values and test assertions.
5. Agent calls `asex_compress_module(source)` before passing contracts to peer subagents (-78% token savings).

---

### Recipe 3: Multi-Target Production CI/CD Pipeline

Compile one ASL business module simultaneously to a React frontend, Go microservice, and Rust native binary:

```bash
# 1. Verify semantics across all files
asl check src/main.agentscript

# 2. Build WebAssembly for browser edge
asl build src/main.agentscript --target wasm -o dist/main.wasm

# 3. Transpile to TypeScript for React web frontend
asl build src/main.agentscript --target ts -o src/generated/main.ts

# 4. Transpile to Go for cloud services
asl build src/main.agentscript --target go -o cmd/server/main.go

# 5. Transpile to Rust for high-throughput native worker
asl build src/main.agentscript --target rs -o crates/core/src/main.rs
```

---

### Recipe 4: Agent In-Memory Scratchpad & Virtual AST Refactoring

Allow autonomous agents to test algorithmic hypotheses in memory without risk:

```lisp
(module agent/scratchpad
  :doc "In-memory combinatorial search test"
  :export [find-optimal-path]
  :import [(core/math :as m)])

(defschema Node
  (:field id Int64 "Node identifier")
  (:field cost Float64 "Path weight"))

(defun find-optimal-path [(nodes (List Node))] -> (Option Node)
  :doc "Filter and select minimum cost node in memory"
  (match nodes
    ((list) (none))
    ((cons head tail) (some head))))
```

---

### Recipe 5: Host FFI & Foreign Declarations (`defextern`)

When integrating with external native libraries or hardware APIs:

```lisp
(module ext/crypto
  :doc "Foreign binding to native host cryptography"
  :export [sha256-hash])

(defextern sha256-hash [(data String)] -> String
  :doc "Platform-specific native SHA-256 implementation"
  :target :rs "native_crypto::sha256"
  :target :ts "crypto.createHash('sha256').update"
  :target :py "hashlib.sha256")
```

---

## 3. Anti-Patterns to Avoid

| Anti-Pattern | Why it Fails in ASL | Recommended Alternative |
| :--- | :--- | :--- |
| **Silent null returns** | Causes runtime crashes | Use `(Option T)` with `(some v)` or `(none)` |
| **Unchecked error codes** | Unsafe error propagation | Use `(Result T E)` with `(ok v)` or `(err e)` |
| **Underscores in symbols** | Violates kebab-case grammar | Use kebab-case: `user-service`, `parse-int` |
| **Side effects in pure funs** | Breaks determinism | Add `!` marker: `(defun ! sync-data ...)` |
| **Catch-all wildcard matching** | Hides missing enum cases | Enumerate all cases explicitly in `match` |
