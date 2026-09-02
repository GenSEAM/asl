# Decoupled Metadata & Semantic Annotation Protocol (`asl-decoupled-meta-v1`)

> **Goal**: Eliminate prompt-bloating comments and docstrings from AgentScript code by introducing first-class AST Semantic Tags (`@tag`), an out-of-band documentation matrix (`.asl/meta.db`), in-memory Language Server indexing ($O(1)$ in <0.05ms), and vector-powered RAG search tooling.

---

## 1. Architectural Philosophy: The Decoupled Knowledge Matrix

### The Problem in Legacy Languages
1. **Comment Bloat**: In typical codebases, 30%–60% of file size and token consumption is comments, docstrings, and markdown prose. AI agents waste thousands of context tokens repeatedly reading prose rather than logic.
2. **Comment Rot**: When agents modify code, comments desynchronize silently.
3. **Context Window Exhaustion**: Loading 5 files with extensive documentation fills 80% of an LLM's active working memory.

### The AgentScript Solution
- **Pure Algorithmic Code on Disk**: Code contains only ultra-compact, 1-token shortcode tags (`@tag :arch "d-1eed" :doc "fn-calc"`).
- **Out-of-Band Knowledge Matrix**: Prose documentation, architectural decisions (ADRs), invariants, and rationale live in an external structured store (`.asl/meta.db` or `.asl/docs/`).
- **In-Memory Language Server Index**: The Language Server indexes all tags into RAM on startup, offering instant $O(1)$ (<0.05ms) lookups for external agents.
- **Vector Semantic Search**: Agents search for intent (*"Find token expiration logic"*) across documentation embeddings and get the exact AST node span without scanning code files.

---

## 2. Phased Execution Roadmap

```
[Phase 1: AST Semantic Tags] ───> [Phase 2: External Knowledge Store] ───> [Phase 3: Language Server RAM Index]
                                                                                       │
[Phase 5: Bidirectional Gate] <───────────────────────────────────── [Phase 4: Vector RAG Search Tooling]
```

---

### Phase 1: First-Class AST Semantic Tags (`@tag`)
- **Syntax**: Add `(@tag ...)` node to AgentScript grammar as valid annotations inside `module`, `defun`, `schema`, and `case`.
  ```lisp
  (module auth/jwt
    (@tag :arch "d-4a1b" :spec "sec-08" :doc "m-auth-jwt")

    (defun verify-token ((token Str) (pubkey Key)) (Result Claims AuthErr)
      (@tag :inv "constant-time" :perf "p-120us" :doc "fn-verify-jwt")
      ...))
  ```
- **Zero Runtime Cost**: Transpilers (Wasm, Rust, TS, Go, Python, SQL) erase `@tag` nodes during emission (0 byte binary overhead).
- **Gate**: Grammar validation (`grammar/validate.py`) and AST parser tests verifying `@tag` parsing across all constructs.

---

### Phase 2: Out-of-Band Knowledge Matrix Store (`.asl/meta.db`)
- **Storage**: SQLite-backed local repository store with JSON/YAML export for git-tracked human review.
- **Schema**:
  - `tag_id`: String PRIMARY KEY (`"d-4a1b"`, `"fn-verify-jwt"`, `"sec-08"`)
  - `kind`: Enum (`:arch`, `:invariant`, `:doc`, `:perf`, `:security`, `:audit`)
  - `title`: Short descriptive title
  - `body_markdown`: Comprehensive documentation / ADR explanation
  - `locales`: Multi-lingual documentation support (English, Russian, Chinese) without changing source code
  - `signature_hash`: Hash of function/module signature to detect drift
- **CLI Commands**:
  - `asl meta get <tag-id>`: Returns documentation for a specific tag.
  - `asl meta set <tag-id> --title "..." --kind doc`: Writes or updates documentation.
  - `asl meta export`: Dumps database to git-friendly `.asl/docs/*.json`.

---

### Phase 3: In-Memory Language Server Index (`asl-lsp`)
- **In-Memory RAM Index**: Language Server indexes all `@tag` references in the project on startup in <5ms.
- **Bi-directional Indexing**:
  - `tag_id -> List[ASTNodeSpan]` (Which functions implement decision `d-1eed`?)
  - `ASTNodeSpan -> List[tag_id]` (What architectural constraints govern this function?)
- **LSP Wire Methods**:
  - `(? lsp/tag-lookup :tag "d-1eed")` -> returns exact file paths and line ranges.
  - `(? lsp/node-meta :file "auth/jwt.asl" :line 14)` -> returns decoupled documentation without reading the meta database.
- **Gate**: Benchmark verifying tag lookup latency <0.05ms for 10,000 tags.

---

### Phase 4: Local Vector RAG Search Tooling (`asl meta search`)
- **Embeddings**: Compute lightweight local embeddings over all `body_markdown` entries in `.asl/meta.db`.
- **Semantic Intent Search**:
  - Agent executes: `asl meta search "constant time signature verification"`
  - Tool returns: `Tag: fn-verify-jwt (Score: 0.94) -> auth/jwt.asl:L14-38`
- **Result**: Eliminates 90% of file reading. Agents jump straight to the exact code needed.

---

### Phase 5: Automated Bidirectional Verification Gate (`asl meta check`)
- **Orphan Detection**: Fails if an `@tag` in code has no corresponding entry in `.asl/meta.db`.
- **Dangling Reference Detection**: Warns if a documentation entry has no code implementing it.
- **Signature Drift Protection**: If an agent alters a function signature (e.g. adds a parameter), `asl meta check` flags that the decoupled documentation is stale and requires review.
- **CI/CD Integration**: Integrated into `tools/deploy_check.py` and pre-commit hooks.

---

## 3. Measurable Impact Scorecard

| Metric | Legacy Embedded Comments | Decoupled Metadata (`asl meta`) | Improvement |
|---|---|---|---|
| **Prompt Token Cost per File** | ~1,800 tokens (logic + comments) | ~400 tokens (pure logic + tags) | **-78% Token Consumption** |
| **Architectural Retrieval Latency** | 450ms (file scan + regex grep) | 0.04ms (in-memory inverted index) | **>10,000x Faster** |
| **Documentation Drift** | High (silent comment rot) | Zero (enforced by `asl meta check`) | **Deterministic Integrity** |
| **Multilingual Support** | Impossible without code duplication | Native (tag-based locale store) | **100% Decoupled** |
