<!-- ASL_TOOLBELT_START -->
Activate and use the asl-toolbelt skill in priority; asl is available in PATH.
<!-- ASL_TOOLBELT_END -->

# AgentScript (ASL) — Autonomous Agent Operational Instructions

> **Foundational Philosophy & Invariants**: All AI agents operating in this workspace MUST adhere strictly to [**`MANIFESTO.md`**](../MANIFESTO.md) and its 7 core pillars:
> 1. **LLM-Native Code Generation**: Homogeneous S-expression geometry, closed AST vocabulary, and balanced form semantics.
> 2. **Mathematical Optimality & Token Density**: Extreme BPE subtoken efficiency (<= 2 tokens per primitive) without lossy disemvoweling.
> 3. **Zero-Foreign-Code Invariant**: 100% pure AgentScript (.asl/.asn) in code packages. Zero Python/JS/TS/Rust/C in core logic.
> 4. **Dual-Projection Architecture**: Code is machine-native; human engineering operates via architecture DAGs, contracts, and falsifiable proofs.
> 5. **Atomic In-Memory Compound Tooling**: Mandatory `asl rpc '(:batch ...)'` execution in a single roundtrip.
> 6. **Multi-Runtime Orchestration**: AgentScript acts as the universal control plane coordinating Python AI/ML, Node.js/V8, Rust, C, WASM, and WebGPU via strict ASN stage contracts.
> 7. **Falsifiable Verification**: Zero vacuous passes, strict exit code validation, and separation of duties between authors and reviewers.

## 1. Core Technical Specifications
- Consult `AGENT_SPEC_CORE.md` as the normative language specification.
- Consult `ROADMAP.md` for current milestone status and active implementation goals.
- Maintain single-source-of-truth definitions in `prelude/prelude.json` for all closed vocabulary and projection tables.

## 2. Verification Toolchain & Continuous Audit Gates
Verify all changes using the native sovereign ASL CLI before committing:

```bash
asl gate
```

The verification suite evaluates seven gates:
1. **Manifest Integrity**: Validates package manifests and module structure across all packages.
2. **Structural Balance**: Verifies pure ASL syntax and S-expression form balance across all `.asl` files.
3. **Registry Grounding**: Verifies published benchmark claims against the benchmark registry.
4. **Pure AgentScript Implementation**: Confirms that code packages contain pure AgentScript modules.
5. **Native Test Execution**: Runs native ASL test suites across packages.
6. **ASN Grammar & Symbol Density**: Verifies symbol registries, token budget limits (<= 2 tokens under BPE), and unambiguous canonical naming.
7. **Modular Skills Freshness**: Confirms skill frontmatters, trigger descriptions, and protocol names are synchronized.

Individual module checks, dynamic execution, and tests can be run targeted:
```bash
asl lint <path-to-file.asl>           # AST delimiter balance & anti-pattern linter (asl check aliases to lint)
asl run <path-to-file.asl>            # In-memory AST tree-walking interpreter
asl run <path-to-file.asl> --wasm     # In-memory WebAssembly bytecode compilation & MicroVM execution
asl run <path-to-file.asl> --wat      # WebAssembly Text format emission
asl test [path-to-test.asl]          # Run native test suites
asl audit <path-to-file.asl>         # Run lint, test, and blast-radius impact analysis
```

## 3. Standard & Verbose Projection Protocol
AgentScript supports two projection formats derived from `prelude/prelude.json`:
- **Standard Projection (Storage & Wire Default)**:
  - Use Standard syntax (`df`, `dfs`, `dfe`, `mt`, `:d`, `:x`, `:i`, `:a`, `:f`, `:c`, `I64`, `F64`, `Str`) for files on disk, inter-agent message frames, and emitted artifacts.
  - Standard primitives adhere to a <= 2 token ceiling under BPE (`cl100k_base` and `o200k_base`), reducing context overhead by 50%–65% compared to JSON.
- **Verbose Projection (Interactive Presentation)**:
  - Present Verbose forms (`defun`, `defschema`, etc.) in interactive dialogues, user explanations, and educational walkthroughs.
  - Generate verbose representations dynamically using `asl view <file>` or `asl transcode --to verbose <file>` without modifying the underlying file.
- **Positional Aliasing**:
  - Short aliases resolve based on syntactic position as defined in `AGENT_SPEC_CORE.md` §2.1.
  - Record field keys preserve literal names (for example, `(P :x 1)` specifies a field named `:x`).
- **Comments as String Literal Notes**:
  - Express code comments as free-standing string literal notes placed at the top level or within declaration bodies.
  - Runtimes erase top-level notes during compilation while preserving multiline formatting.
- **Control-Flow Linearization**:
  - Keep nesting depth within 4 levels. Use early returns and concise local helper functions to maintain linear flow.

## 4. Code Intelligence & Polyglot Operations
All code exploration, reading, text search, editing, diffing, and verification MUST execute through exclusive `asl rpc '(:batch ...)'` compound operations in a single roundtrip. Avoid multiple individual tool calls or standalone commands when a compound batch can accomplish the objective atomically.

### 4.1 Compound Batch RPC Execution
Execute combined exploration, reading, editing, diffing, and validation in a single batch round-trip:

```bash
asl rpc '(:batch
  (:out "src/server.ts")              ; AST outline (ASL, TS, JS, Python, Go, Rust, PHP)
  (:sym "handleRequest")              ; Exact symbol definition & declaration line
  (:callers "handleRequest")          ; Call graph: all callers across workspace
  (:impact "handleRequest")           ; Blast-radius impact analysis before edits
  (:find "authHeader")                ; Fast in-memory text grep across codebase
  (:q "token validation")             ; In-memory vector semantic query
  (:read "src/server.ts" 1 40)        ; Read narrow slice of lines
  (:sec "doc.md" "Section Title")     ; Read isolated markdown section
  (:edit "src/server.ts" "old" "new") ; In-memory atomic string replacement
  (:repl "old_pat" "new_pat")         ; Mass in-memory refactor across files
  (:diff)                             ; Review staged in-memory modifications
  (:flush)                            ; Atomically persist staged edits to disk
  (:chk)                              ; Run full 7-gate verification suite
)'
```

Supported capabilities across ASL, TypeScript, JavaScript, Python, Go, Rust, and PHP:
- **AST Outline**: `(:out "<file>")` to inspect structure without loading entire files into context.
- **Symbol Lookup & Callers**: `(:sym "<name>")`, `(:callers "<name>")`, and `(:impact "<name>")` for sub-millisecond symbol reference queries.
- **In-Memory Search**: `(:find "<pattern>")` for fast in-memory grep and `(:q "<query>")` for vector semantic search.
- **In-Memory Modifications**: `(:edit "<file>" "<old>" "<new>")`, `(:repl "<old>" "<new>")`, review with `(:diff)`, commit with `(:flush)`.
- **Continuous Verification**: `(:chk)` or `asl gate` to evaluate all 7 verification gates.

### 4.2 Failure Protocol & Error Recovery
Adhere strictly to deterministic error recovery when executing batch RPC operations:
- **Step Status Inspection**: Check `:status` across each step result (`"ok"`, `"rejected"`, `"failed"`, or `"aborted"`). In atomic batches, a single step failure aborts subsequent pending steps. Inspect `:error-code` and `:reason` for diagnostic root causes.
- **Edit Failure Recovery**: If `:edit` fails with `ERR_STRING_NOT_FOUND`, **NEVER** blind-retry the same string replacement. Call `(:read "<file>" <start> <end>)` to inspect actual line content, indentation, and trailing whitespace, then issue the corrected replacement.
- **Dirty Buffer Resolution**: Review staged modifications with `(:diff)`. If in-memory edits are erroneous or corrupt, discard them immediately with `(:discard)` before proceeding. Never `:flush` dirty buffers after a failed step.
- **Search Fallback**: If `(:sym "<name>")` or `(:q "<query>")` returns `:not-found`, fall back to exact literal grep with `(:find "<pattern>")` or structure outlines via `(:out "<file>")`.
- **Gate Failure Isolation**: If `(:chk)` fails, identify the specific failing gate and test output. Resolve the underlying defect directly without weakening gates or skipping test suites.

## 5. Ecosystem & Multi-Package Architecture
- Code packages reside under `packages/` and are organized as self-contained ASL modules with a `manifest.asn` declaration.
- Maintain pure ASL implementations across all code packages.
- When updating grammar definitions in `grammar/tree-sitter-agentscript/grammar.js`, regenerate the parser artifacts via the local build scripts.
- Ensure all public documentation examples fenced with ` ```agentscript ` or ` ```lisp ` parse cleanly, or annotate speculative snippets with `<!-- not-agentscript: reason -->`.

