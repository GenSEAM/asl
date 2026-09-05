# Comprehensive Gap Audit: Pure ASL & Ephemeral Architecture

**Verdict**: `APPROVE-WITH-AMENDMENTS`
**Lenses**: Completeness (Omission), Consistency (Invariants), Anti-Overengineering (Adequacy)

---

## 1. Completeness Analysis (Gap Detection)

| Area | Finding / Evidence | Risk / Impact | Amendment / Remedy |
|---|---|---|---|
| **Ephemeral Test Leaks** | `pack/bridges/asl_runner.js` creates runners | Process crash or SIGINT could leave `/tmp/asl_*.mjs` files on disk | Implement `process.on('exit')` and `try...finally` auto-unlink in ephemeral execution loop |
| **Chrome Extension Manifest** | Chrome requires physical `manifest.json` on disk | Unpacked extension cannot load directly from `manifest.asn` | Direct emission to `dist/manifest.json` on build; strictly add `dist/` to `.gitignore` |
| **Bytecode Cache In Git** | `harness/bridges/__pycache__/*.pyc` committed in git | Pollutes repository with binary cache artifacts | Run `git rm` on all `.pyc` files and enforce global ignore |
| **Token Bloat in FFI** | Multi-token `:turn` (2 tokens) and `(ffi:import ...)` (3 tokens) | Wastes LLM context budget during agent tool calling | Standardize single-letter directives: `:k` (kernel syscall) and `:t` (turn frame) |

---

## 2. Architectural Consistency & Invariants

* **Single Source of Truth Invariant**:
  - Code: exclusively **`.asl`** (AgentScript).
  - Data / Schemas / Manifests: exclusively **`.asn`** (AgentScript Notation).
  - JSON usage eliminated across all internal packages (`asl.json` $\rightarrow$ `manifest.asn`).
* **Source vs Artifact Separation**:
  - `build/`: transient execution, test runners, and ephemeral benchmarks (deleted on exit).
  - `dist/`: compiled targets (Wasm, TSX, Python/Rust). Completely ignored in git.
* **Effective Decision Mode Compliance**:
  - Minimal diff, zero external dependencies, no complex macro wrappers.

---

## 3. Anti-Overengineering (Critic Filter)

* **YAGNI Pass**:
  - No speculative schema generators.
  - S-expression parser in `tools/project.py` is under 25 lines of direct regex/parsing logic without adding third-party YAML/JSON parsers.
* **Diff Efficiency**:
  - Single-letter directives (`:k`, `:t`) eliminate boilerplate while enforcing 1 BPE token density.

---

## 4. Execution Readiness

- **Phase 1 (`asn-metadata-migration`)**: Manifests created across all satellite repos, `tools/project.py` updated.
- **Phase 2 (`ephemeral-runner-pipeline`)**: Implement ephemeral runner with auto-unlink in `pack/`.
- **Phase 3 (`dist-git-isolation-hygiene`)**: Gitignore enforcement and `.pyc` removal.
- **Phase 4 (`single-token-ffi-spec`)**: Implement `:k` and `:t` single-token directives in grammar & runtime.
