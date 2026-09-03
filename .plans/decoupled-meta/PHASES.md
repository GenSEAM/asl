# Decoupled Metadata & Semantic Annotation Protocol (`asl-decoupled-meta-v1`)

> **Goal**: Eliminate prompt-bloating comments and docstrings from AgentScript code by introducing first-class AST semantic tags (`:tag`), an out-of-band documentation matrix (`.asl/meta.db`), in-memory Language Server indexing ($O(1)$ in <0.05ms), and vector-powered RAG search tooling.

---

## 1. Architectural Philosophy: The Decoupled Knowledge Matrix

### The Problem in Legacy Languages
1. **Comment Bloat**: In typical codebases, 30%–60% of file size and token consumption is comments, docstrings, and markdown prose. AI agents waste thousands of context tokens repeatedly reading prose rather than logic.
2. **Comment Rot**: When agents modify code, comments desynchronize silently.
3. **Context Window Exhaustion**: Loading 5 files with extensive documentation fills 80% of an LLM's active working memory.

### The AgentScript Solution
- **Pure Algorithmic Code on Disk**: Code contains only ultra-compact, 1-token shortcode tags (`(:tag :arch "d-1eed" :doc "fn-calc")`).
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

### Phase 1: First-Class AST Semantic Tags (`:tag`)
- **Syntax**: Add a `(:tag ...)` node to both grammars, admitted inside `module`, `defun`,
  `defschema` and `defenum` case positions. **`@` is not an identifier character and lexes as
  its own token, so `@tag` costs two BPE tokens** — the opposite of this iteration's goal.
  Commit `acb2ef3` already replaced every `@` prefix in the repository with a `:` keyword;
  this plan must not reintroduce one.
  ```lisp
  (module auth/jwt
    (:tag :arch "d-4a1b" :spec "sec-08" :doc "m-auth-jwt")

    (df verify-token [(token Str) (pubkey Key)] -> (Result Claims AuthErr)
      :d "Verify a JWT against a public key."
      (:tag :inv "constant-time" :perf "p-120us" :doc "fn-verify-jwt")
      (ok (Claims :sub "u1"))))
  ```
- **Zero Runtime Cost**: every backend erases `:tag` nodes during emission.
- **Gate**: `grammar/validate.py` (both grammars agree), `checker/gate.py` (a tag binds nothing
  and resolves nothing), `tools/tests/test_native_parity.py` (the self-hosted parser reads it
  too), and a transcoder round-trip. There are four encodings of the syntax — Lark,
  tree-sitter, `packages/asl-parser`, and `tools/transcoder.py` — and a new node reaching
  only the first is the drift this project has already been bitten by.

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
- **In-Memory RAM Index**: Language Server indexes all `:tag` references in the project on startup in <5ms.
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
- **Orphan Detection**: Fails if a `:tag` in code has no corresponding entry in `.asl/meta.db`.
- **Dangling Reference Detection**: Warns if a documentation entry has no code implementing it.
- **Signature Drift Protection**: If an agent alters a function signature (e.g. adds a parameter), `asl meta check` flags that the decoupled documentation is stale and requires review.
- **CI/CD Integration**: Integrated into `tools/deploy_check.py` and pre-commit hooks.

---

## 3. Measurable Impact Scorecard

| Metric | Legacy Embedded Comments | Decoupled Metadata (`asl meta`) | Improvement |
|---|---|---|---|
| **Prompt token cost per file** | logic + prose | logic + tags | to be measured |
| **Architectural retrieval** | file scan + grep | in-memory inverted index | to be measured |
| **Documentation drift** | silent comment rot | rejected by `asl meta check` | enforced, not measured |
| **Multilingual support** | code duplication | tag-keyed locale store | structural |

Every "to be measured" above is a number this iteration must produce with a command, in the shape
of `bench/token_frames.py` and its lock file: a figure on a page with no way to re-derive it is the
thing `DESIGN.md` §5 forbids. The earlier draft of this table asserted -78%, 0.04ms and >10,000x
with nothing behind any of them.
