# Gap Analysis: Pure ASL & Ephemeral Architecture

**Verdict**: `APPROVE-WITH-AMENDMENTS`

## 1. Completeness Gaps & Edge Cases
- **Gap 1 (Backward Compatibility in Tooling)**:
  - *Finding*: If `asl.json` is removed, existing compiler tools like `grammar/validate.py` or legacy scripts might expect `asl.json` in root package paths.
  - *Remedy*: Ensure `pack/bridges/asl_runner.js` and `agentscript` look for `manifest.asn` first, and support graceful fallback during migration.
- **Gap 2 (Ephemeral Cleanup Guarantees)**:
  - *Finding*: If a test crashes via `SIGKILL` or unhandled rejection, a temporary file in `/tmp/` could theoretically leak.
  - *Remedy*: Use Node's `fs.mkdtempSync(path.join(os.tmpdir(), 'asl-'))` with `process.on('exit', ...)` and `try...finally` cleanup hook.
- **Gap 3 (Browser Extension Manifest Emission)**:
  - *Finding*: Chrome requires `manifest.json` physically on disk in the directory passed to `--load-extension`.
  - *Remedy*: Provide `asl build --target ext` or an ephemeral build step that writes `dist/manifest.json`, ensuring `dist/` is added to `.gitignore`.

## 2. Consistency & Invariants
- Conforms to **Effective Decision Mode — Radical Simplicity & Pragmatism**:
  - No new dependencies.
  - S-expression ASN format reuses existing ASN parser.
  - Single-token FFI directive (`(:sys ...)`) preserves <= 2 BPE tokens per operation invariant.

## 3. Anti-Overengineering Filter
- Zero new abstract layers.
- Direct file cleanup and standard `dist/` gitignoring across all 15 repos.
