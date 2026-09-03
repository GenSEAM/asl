# Phase 4 — CI hardening: native parser over every package, full gate chain, zero regressions

Iteration: `asl-selfhosted-runtime-v1`. Repo root for every command: `/Users/purplelephant/projects/asex`.

## Scope correction (explicit, per orchestrator decision)

The roadmap's "all 24 packages" is stale. Measured this session:

```
find packages -name '*.asl' | wc -l   →   37
```

The phase's parse scope is **every `.asl` file under `packages/` — 37 files** (14 packages,
including `asl-parser`'s own `src/ast.asl`, `lexer.asl`, `reader.asl`).

## Acceptance criterion (fixed in roadmap)

```
node /Users/purplelephant/.gemini/config/skills/pcp/scripts/pcp.js actualize && npm run build:web
```

plus the full gate chain (installed 7-gate hook + the AGENTS.md wider gates) recorded green.
`build:web` resolves: `package.json:12` → `npm --prefix web run build` → `web/package.json:8`
(`tsc && vite build`). `pcp.js actualize` takes no args, writes `.pcp/{MAP.json,INVENTORY.json,
INVENTORY.md,INDEX.md}`, validates traces and **exits 1 on any breach**
(`pcp.js:449-477`; breach path `pcp.js:468-475`).

## Baseline fact verified this session

```
$ .venv/bin/python -c "from tools.native_parser import parse_native"
ModuleNotFoundError: No module named 'tools.native_parser'
```

Phase 3 is still in flight; nothing native-parses `packages/` yet. `tools/linter.py:16-18` and
`tools/clone_detector.py:17-19` both parse via Lark; the only native driver is
`packages/asl-parser/tests/harness.py:28-43` (`run_asl`), consumed only by non-gated pytest.
No `parse` subcommand exists in the `agentscript` CLI yet (grep over `add_parser(` — no match).

---

## Work items, in order

### 1. Sync the source hook `tools/hooks/pre-commit` to the installed 7-gate chain

- **What:** Copy gates 5 (`$PYTHON agentscript lint packages/`) and 6
  (`$PYTHON agentscript clone-check packages/ --threshold 0.15`) from the installed
  `.git/hooks/pre-commit:20-27` into `tools/hooks/pre-commit`, placed between the checker gate
  and the token gate; renumber the `--> N/M` echo labels to 1/7..7/7. Nothing else changes.
- **Why:** The installed hook runs 7 gates; its source has 6 and omits lint and clone-check
  (`tools/hooks/pre-commit:20-30`). The next reinstall of the hook would silently drop two
  quality gates. Restoring parity is pure strengthening — no gate is weakened.
- **Gate (fails now):**
  ```
  grep -q "agentscript lint packages/" tools/hooks/pre-commit
  ```
  Currently exits 1: the source hook (`tools/hooks/pre-commit:1-33`) contains no lint step.
  Passes once gate 5 is added.
- **Breaks if run before prior item:** Nothing — item 1 is independent and mechanical; it is
  first so the chain's source of truth is correct before any full-chain run is recorded.

### 2. Native parse-everything test: `tools/tests/test_native_parse_all.py`

- **What:** A pytest that globs `packages/**/*.asl`, feeds each of the 37 files through the
  native parser entry point Phase 3 lands in `tools/native_parser.py`, asserts zero parse
  errors, and on failure reports **every** offending file with its diagnostic (not first-fail).
  The test hard-fails on zero files found, so a broken glob cannot green it.
- **Why:** The phase's core claim — "parse every package with the native parser" — has no
  enforcing artifact today. Lark-based tools (linter, clone-check) and the asl-parser-only
  pytest harness all leave the other 13 packages' `.asl` files unexercised by the native parser.
- **Decision applied (orchestrator asked pytest vs CLI):** **pytest.** `tools/tests` is already
  in the AGENTS.md pytest gate command (`AGENTS.md:33`, `... -m pytest backend/tests bench/algo
  checker/tests tools/tests -q`), so the check self-enforces in CI with zero hook or CLI wiring.
  A CLI subcommand would be opt-in and would need a hook edit to be enforced — a new-gate
  decision this plan does not make (see Out of scope).
- **Gate (fails now):**
  ```
  .venv/bin/python -m pytest tools/tests/test_native_parse_all.py -q
  ```
  Currently fails before the test even runs: `ModuleNotFoundError: No module named
  'tools.native_parser'` (verbatim, probed this session). It stays red until (a) Phase 3 lands
  the module and (b) all 37 files parse natively.
- **Breaks if run before prior item:** Run before Phase 3's `tools/native_parser.py` exists →
  the ModuleNotFoundError above (the gate, working as designed). Item 1 is independent; this
  ordering is for a clean record, not a technical dependency.
- **Not permitted:** editing the test, the fixtures, or a gate to make this pass. If package
  files fail native parse, the fix belongs in the parser (Phase 3's artifact) — see Risks.

### 3. Run the AGENTS.md wider gates and record output

- **What:** Run, in order, and record verbatim output:
  ```
  .venv/bin/python backend/check_corpus.py
  .venv/bin/python backend/monomorphism.py
  .venv/bin/python backend/differential.py
  .venv/bin/python -m pytest backend/tests bench/algo checker/tests tools/tests -q
  ```
- **Why:** "Zero regressions" is only provable by these; the installed hook runs none of them
  (`.git/hooks/pre-commit` runs gates 1-7 only), and AGENTS.md:23-33 requires them before any
  commit. The pytest arm includes item 2's new test.
- **Gate:** the four commands themselves. Status **unverified-by-me** — planning ran no gates.
  The failing-now property of the pytest arm is supplied by item 2's test; if any of the other
  three already pass, the item still must run to produce the recorded evidence.
- **Breaks if run before item 2:** the pytest arm would go green without containing the
  native-parse check — a "zero regressions" record missing the phase's core evidence.

### 4. Run the installed 7-gate pre-commit chain and record output

- **What:**
  ```
  bash .git/hooks/pre-commit
  ```
- **Why:** This is the chain named in the phase goal; the recorded green output is the
  regression evidence for gates 1-7 (grammar parity, closure, prelude, checker, lint,
  clone-check, tokens + deploy check).
- **Gate:** the command itself. Status **unverified-by-me** — not run during planning.
  Gates 5 and 6 (`agentscript lint packages/`, `clone-check`) already parse all 37 package
  files — via Lark, which is why item 2 exists on top of this.
- **Breaks if run before items 2-3:** nothing technically — but the full-chain green would be
  recorded before the wider-gate evidence exists, inverting the proof order the phase demands.

### 5. Re-run the phase acceptance criterion, then the full chain once more

- **What:**
  ```
  node /Users/purplelephant/.gemini/config/skills/pcp/scripts/pcp.js actualize
  npm run build:web
  bash .git/hooks/pre-commit
  ```
- **Why:** The literal acceptance criterion, executed last so every prior item's evidence is on
  disk when it runs. `pcp.js actualize` writes `.pcp/` artifacts and exits 1 on any trace breach
  (`pcp.js:449-477`); `build:web` is the delegated `tsc && vite build`
  (`package.json:12`, `web/package.json:8`). The final hook run confirms nothing in the
  acceptance step regressed the chain.
- **Gate:** `node .../pcp.js actualize` — status **unverified-by-me**. Expected failure modes if
  the phase is not done: a PCP `DeadConnectionBreachException` (`pcp.js:468-475`), or any of
  items 2-4's commands failing. Success prints `PCP validation successful: 0 breaches detected.`
- **Breaks if run before items 2-4:** it would stamp the phase's criterion green while the
  native-parse evidence (item 2) and the wider-gate record (item 3) do not exist — exactly the
  "green exit code without verification" failure the project's gates exist to prevent.

---

## Risks / unverified

- **Phase 3 API unknown.** `tools/native_parser.py` does not exist yet (verified: import
  probe above). The entry-point name this plan assumed (`parse_native`) was a probe guess;
  the implementer must bind to whatever Phase 3 actually lands and adjust the test import —
  the gate command does not change.
- **No gate was run during planning** (evidence standard). Items 3-5's current pass/fail
  status is unverified; several may already be green. Only item 1's grep and item 2's
  ModuleNotFoundError are verified failing now.
- **Real possibility of genuine native-parse failures.** Some of the 37 files may fail the
  native parser — that is the discovery this phase exists to make. The plan forbids weakening
  the test or touching fixtures; a parser defect lands back in Phase 3's artifact. If the
  defect is structural, the orchestrator should expect a fix loop before the criterion can go
  green.
- **PCP trace state unverified.** Whether the current `.pcp/` shortcodes are breach-free is
  unknown; `pcp.js actualize` both writes artifacts and is the criterion's first half, so a
  breach surfaces only at item 5.
- **Node 22 LTS assumed.** `build:web` requires Node ≥22 (`package.json` engines,
  `AGENTS.md:147`); not verified this session.
- **Installed-hook echo labels are stale** (`1/5` ... `5/7`, `.git/hooks/pre-commit:14-31`).
  Cosmetic only; this plan syncs the source hook's structure, not the installed file's labels.

## Out of scope

- **Promoting the native-parse test into the pre-commit hook as an 8th gate.** New-gate
  decision — flagged to the orchestrator. It is already enforced via the AGENTS.md pytest gate
  (`tools/tests` is in the sweep), so nothing enforces less by omitting it.
- **Fixing any parser defect item 2 surfaces** — that is Phase 3's deliverable; this phase
  only proves the test's verdict is real.
- **Changing any gate command, threshold, or fixture.** Every gate here runs as-is.
- **The other Lark-based tools** (`linter.py`, `clone_detector.py`, `module_graph.py`)
  migrating to the native parser — a separate, larger migration this phase does not open.
