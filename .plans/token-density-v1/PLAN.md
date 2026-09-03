# Iteration Plan: asl-token-density-v1
**Goal:** Agent-Native Token Inspection Tooling, 2-Token Ceiling Enforcement, Nano Builtin Aliases, and Self-Hosted ASL Token Analyzer (`asl tokens` & `packages/asl-lint/src/core/tokens.asl`).

---

## 1. Architectural Intent (@pcp:d-2tok)

AgentScript is an agent-centric programming language designed for minimal prompt consumption and maximum reasoning throughput by LLMs.
Human readability is served by the verbose projection, but the default stored and generated code must be **ultra-dense**:
1. **2-Token Ceiling:** No builtin operation or language form in the Nano projection may exceed **2 BPE tokens** under `cl100k_base` and `o200k_base`. 3+ tokens are classified as an architectural defect (token smell).
2. **Standard Library Nano Aliases:** The 40 heavy builtins (currently 3–6 tokens) receive idiomatic 1–2 token aliases (`starts?`, `ends?`, `len`, `head`, `tail`, `rev`, `sum`, `split`, `join`, `trim`, `slice`, `chars`, `f64`, `i64`, `str`, `keys`, `vals`, `has?`, `empty?`, `some?`, `none?`, `ok?`, `err?`).
3. **Self-Hosted Verification (Dogfooding):** In addition to the Python benchmark gate (`bench/token_ceiling.py`), the token inspection engine is implemented natively in pure AgentScript inside `packages/asl-lint/src/core/tokens.asl`.

---

## 2. Work Breakdown

### Item 1: Automated Token Ceiling Pre-Commit Gate (`bench/token_ceiling.py`)
- **Task:** Create `bench/token_ceiling.py --check` that inspects `prelude/prelude.json`.
- **Enforcement:**
  - Evaluates every builtin, option, and special form in call position and option position under `cl100k_base` and `o200k_base`.
  - Fails with exit code 1 if any Nano form exceeds 2 tokens.
  - Wire into the pre-commit gate suite in `AGENTS.md`.
- **Verification:** `.venv/bin/python bench/token_ceiling.py --check`

### Item 2: Extension of `prelude.json` with Nano Builtin Aliases
- **Task:**
  - Add `projection.builtins` table to `prelude/prelude.json` mapping verbose names to 1–2 token Nano spellings.
  - Update `prelude/vocab.py` and `tools/transcoder.py` to support bidirectional translation of builtin aliases.
  - Update `prelude/generate.py` to regenerate `AGENT_SPEC_CORE.md`, `prelude/HANDBOOK.md`, `llms.txt`, and `skills/asl/SKILL.md`.
- **Verification:** `.venv/bin/python prelude/generate.py --check`

### Item 3: Self-Hosted Token Inspection Engine in Pure ASL (`packages/asl-lint/src/core/tokens.asl`)
- **Task:**
  - Implement AST token density metrics in pure AgentScript using `packages/asl-parser`:
    - Counts tokens for identifier names, forms, and literals.
    - Flags symbols exceeding the 2-token threshold.
    - Emits structured `TokenSmell` diagnostic records for `asl-lint`.
  - Transpile to Python and compile with `backend/to_python.py`.
- **Verification:** `.venv/bin/python checker/gate.py` passes on all packages.

### Item 4: CLI Integration (`asl tokens` and `asl lint --tokens`)
- **Task:**
  - Expose `asl tokens <file.asl>` in the unified CLI to inspect any source file's token footprint.
  - Integrate token efficiency scoring into the web Quality Doctor (`web/src/components/AslQualityDoctor.tsx`).
- **Verification:** `asl tokens packages/asl-lint/src/core/tokens.asl` reports 0 token violations.

---

## 3. Acceptance Criteria
- [ ] Every Nano builtin and special form in `prelude.json` takes <= 2 tokens.
- [ ] `bench/token_ceiling.py --check` runs in CI and pre-commit without errors.
- [ ] All 16 existing CI gates remain clean and green.
