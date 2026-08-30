# Phase 3 — Rename AgentS → AgentScript

Baseline: all gates green at `b6b43ff` (per ORCHESTRATOR-LOG "Phase 2 closed … 161 tests"). Item I0 re-verifies before any change.

## 1. Target identifier scheme

| Slot | Old | New | Rationale |
|---|---|---|---|
| Language name | AgentS / AgentS-Core | **AgentScript** | Owner directive; "-Core" was v0 title branding, dropped (spec file keeps CORE in filename). |
| File extension | `.agents` | **`.agentscript`** | Fork's `.as` collides with ActionScript and belongs to the `as-lang` identity we're leaving. |
| Reserved prefix | `agents-` | **`agentscript-`** | Rule code stays `rule-7` (spec checklist number, not the name). |
| Lark grammar | `grammar/agents.lark` | `grammar/agentscript.lark` | `grammar/parse.py:15` is the only consumer. |
| tree-sitter | dir `tree-sitter-agents`, name `agents`, scope `source.agents`, file-types `["agents"]` | dir `tree-sitter-agentscript`, name `agentscript`, scope `source.agentscript`, file-types `["agentscript"]` | Both grammars change together; file-types moves with the corpus extension. |
| Module namespace | `core/…`, `text/…` | unchanged | User paths carry no language name. |
| Runtime alias | `_as` | **`_agentscript`** | Emitted code; fixture `; run:` headers move atomically. |
| Env vars | `AGENTS_EXEC_COVERAGE`, `AGENTS_EXEC_SOURCE`, `AGENTS_COVERAGE_LOCK` | `AGENTSCRIPT_*` | Tracer contract crossing a subprocess boundary. |
| npm | root `asex`, `tree-sitter-agents` | `agentscript`, `tree-sitter-agentscript` | Package names name the project. |
| Go module | `module agents` | `module agentscript` | `backend/golang/go.mod:1`. |
| CLI | none | none | Fork's tooling is out of scope for this phase. |
| Repo dir / credential env | `asex`, `ASEX_GATEWAY_KEY` | **unchanged** | External contracts (owner's filesystem + exported credential). |

**Frozen exceptions (in the acceptance rg):** `AGENT_SPEC.md` + `SPEC_REVIEW.md` (v0 provenance pair, frozen per ROADMAP §2) and `.plans/**` (phase history + this plan must spell what was renamed).

**Canaries:** `prelude/coverage.lock` byte-identical (rename changes no lowering semantics); in `backend/cases/*.json` only `"src"` lines change; differential expected stdout/stderr/exit byte-identical.

## 2. File inventory

**88 tracked `.agents` files** = 29 valid + 6 invalid + 44 semantic (incl. `import-cycle/{a,b}`) + 6 modules + 2 bench (`histogram.agents`, `variants/tight.agents`) + 1 `backend/t/smoke.agents`. All `git mv`'d in I1.

- **grammar**: `agents.lark`→`agentscript.lark` (+:1 comment); `parse.py:15`; `modules.py:19` (`+ ".agents"`); `validate.py` (:2,:5-6,:30 TS_DIR,:111 probe ext,:150-165 globs); `closure_audit.py` (:27 TS_DIR,:76 glob,:83 spec ext); `tree-sitter-agents/`→`tree-sitter-agentscript/` (`grammar.js` name+comment, `package.json` name/desc/scope/file-types, `queries/highlights.scm:1`, `queries/searches.scm:2`); `semantic/reserved-prefix.agents` (:2,:5 → I3); `; run:` headers naming `_as` (`23-numeric:12`, `18-pattern-binders:5`, `29-literals:4` comment → I4).
- **prelude**: `prelude.json` (:2 `$comment`, :5-6 `runtime` field, ~150 `_as.` template prefixes); `generate.py:57` handbook title; `HANDBOOK.md` regenerated; `coverage.lock` **untouched**.
- **backend**: `check_corpus.py:27-28`; `differential.py` (:2,:359,:383,:389,:398,:401); `exec_coverage.py` (:215,:383 globs + env vars → I6); `monomorphism.py:222`; `to_python.py` (:2,:335 comments, **:104 `import runtime as _as`, :183 `_as.main_exit`** → I4); `to_rust.py:2`; `runtime.py:1,:5`; `rust/rt.rs:1`; `golang/go.mod:1` + `rt/rt.go:1`; `cases/*.json` (27 files, `"src"` only); `t/` (smoke.agents ext, test_smoke, test_runtime:16, test_modules, test_differential_encoding:37,:76, test_float_ordering, test_imports, test_exec_coverage, test_gate_machinery).
- **checker**: `resolve.py:34` RESERVED (→ I3); `check.py:2`; `gate.py:51,:61`; `t/` (test_types, test_map_keys:21,:119, test_patterns, test_effects).
- **bench**: `histogram.agents` ext; **`histogram_agents.py`→`histogram_agentscript.py`** (regenerate → I4); `test_histogram.py` (import, ids, regenerate cmd); `COMPARISON.md:9,:75`; `variants/tight.agents` ext; `variants/typed_python.py:1`; `harness/run.py` (:2,:68 prompt,:124,:167); `tasks/histogram.json:4`.
- **docs**: `AGENT_SPEC_CORE.md` (:1 title, :105,:744 prefix → I3, :707,:725 → I6; §6 generated, anchors `## 6.`/`## 7.` untouched); `AGENTS.md` (:81,:91 prose, :112-125 grammar paths → I2, :133 prefix → I3); `ROADMAP.md`; `EXPERIMENT.md` (+ dated §9 amendment, before-results); `RESEARCH_REPORT.md`; `AGENT_SPEC.md`+`SPEC_REVIEW.md` frozen.
- **plans/pcp/root**: `PHASES.md` (:1,:38,:44); `.pcp/lang/checker.md:105` + `backends.md:164` fixture paths; mint one `d-` entry + `actualize`; root `package.json:2`; `config.example.json:4` unchanged.

## 3. Ordered work items (one phase commit; items are staged verification units)

**I0 — Baseline capture.** Run all gates + pytest verbatim into `.plans/phase-3/BASELINE.md`; record counts (validate 85 fixtures + 13 probes = 98 `ok`; checker gate 35 clean + 44 semantic = 79 `ok`; check_corpus 31; pytest 161). Gate: `test -s .plans/phase-3/BASELINE.md`.

**I1 — Extension + corpus + every consumer (atomic).** `git mv` 88 `.agents`→`.agentscript`; update every glob/path/temp/`"src"`/file-types. *Fails if wrong:* stale glob reads zero fixtures — `validate.py`/`checker/gate.py` have no empty-set guard (silent pass); `modules.py:19` missed → FileNotFoundError (loud). Gate:
```
test "$(git ls-files '*.agents' | wc -l | tr -d ' ')" = 0
test "$(git ls-files '*.agentscript' | wc -l | tr -d ' ')" = 88
test "$(.venv/bin/python grammar/validate.py | grep -c ' ok$')" = 98
test "$(.venv/bin/python checker/gate.py | grep -c ' ok$')" = 79
.venv/bin/python backend/check_corpus.py && .venv/bin/python grammar/closure_audit.py \
&& .venv/bin/python backend/differential.py && .venv/bin/python backend/exec_coverage.py \
&& .venv/bin/python backend/monomorphism.py && .venv/bin/python prelude/generate.py --check \
&& .venv/bin/python -m pytest backend/t bench/algo checker/t -q
```

**I2 — Grammar filenames + tree-sitter regeneration.** Rename lark + dir + `grammar.js` name + package; `tree-sitter generate`. *Fails if wrong:* missed GRAMMAR/TS_DIR → loud; skipped regeneration → stale parser (hidden). Gate:
```
test -f grammar/agentscript.lark && test ! -e grammar/agents.lark
test "$(git ls-files grammar/tree-sitter-agentscript | wc -l | tr -d ' ')" = 4
(cd grammar/tree-sitter-agentscript && ../../node_modules/.bin/tree-sitter generate)
.venv/bin/python grammar/validate.py && .venv/bin/python grammar/closure_audit.py
rg -n "agents\.lark|tree-sitter-agents\b" --glob '!.plans/**' --glob '!AGENT_SPEC.md' --glob '!SPEC_REVIEW.md' .
```

**I3 — Reserved prefix, rule and fixture together.** `resolve.py:34` RESERVED→`"agentscript-"`; fixture; `AGENT_SPEC_CORE.md:105,:744`; `AGENTS.md:133`. Code stays `rule-7`. *Fails if wrong:* either half alone → fixture not rejected → gate fails (the `c-099a` trap). Gate:
```
.venv/bin/python checker/gate.py | grep 'reserved-prefix' | grep 'rule-7' | grep -q ' ok$'
rg -n '\bagents-' --glob '!.plans/**' --glob '!AGENT_SPEC.md' --glob '!SPEC_REVIEW.md' .
.venv/bin/python -m pytest checker/t -q
```

**I4 — Runtime alias `_as`→`_agentscript` (atomic).** prelude templates + runtime field; `to_python.py:104,:183`; `; run:` headers; test aliases; regenerate+rename `histogram_agents.py`→`histogram_agentscript.py`; regenerate `smoke.py`. *Fails if wrong:* split → `check_corpus` run column NameError + byte-equality tests fail. Gate:
```
rg -n '_as\b' prelude backend bench grammar checker
.venv/bin/python backend/check_corpus.py && .venv/bin/python backend/differential.py
.venv/bin/python -m pytest backend/t bench/algo -q
```

**I5 — Regenerate vocabulary artifacts.** Edit `prelude.json:2` + `generate.py:57`, run generator. *Fails if wrong:* stale artifact → `--check` fails. Gate:
```
.venv/bin/python prelude/generate.py && .venv/bin/python prelude/generate.py --check
rg -n 'AgentS' prelude/HANDBOOK.md
git diff <baseline> HEAD -- prelude/coverage.lock
```

**I6 — Prose, comments, env vars, packages, PCP.** Everything remaining in §2; EXPERIMENT dated amendment first; env vars in exec_coverage + test_exec_coverage (recorder text + setters same item); PCP mint + actualize. Gate: §4 battery.

## 4. Acceptance gate

```
rg -n 'AgentS' --glob '!.plans/**' --glob '!AGENT_SPEC.md' --glob '!SPEC_REVIEW.md' .
rg -n '\.agents\b|agents\.lark|tree-sitter-agents' --glob '!.plans/**' --glob '!AGENT_SPEC.md' --glob '!SPEC_REVIEW.md' .
rg -n '\bagents-' --glob '!.plans/**' --glob '!AGENT_SPEC.md' --glob '!SPEC_REVIEW.md' .
rg -n '_as\b|AGENTS_(EXEC|COVERAGE)' --glob '!.plans/**' --glob '!AGENT_SPEC.md' --glob '!SPEC_REVIEW.md' .
rg -n 'asex' --glob '!.plans/**' .   # only config.example.json:4 (justified)
git ls-files '*.agents'   # empty
test "$(git ls-files '*.agentscript' | wc -l | tr -d ' ')" = 88
git diff <baseline> HEAD -- prelude/coverage.lock   # empty
git diff <baseline> HEAD -- backend/cases | grep '^[+-]' | grep -v '"src"'   # empty
git diff <baseline> HEAD -- backend/differential.py | grep '^[+-]' | grep -E '"stdout"|"stderr"|"exit"'   # empty
.venv/bin/python grammar/validate.py
.venv/bin/python grammar/closure_audit.py
.venv/bin/python prelude/generate.py --check
.venv/bin/python checker/gate.py
.venv/bin/python backend/check_corpus.py
.venv/bin/python backend/monomorphism.py
.venv/bin/python backend/differential.py
.venv/bin/python backend/exec_coverage.py
.venv/bin/python -m pytest backend/t bench/algo checker/t -q
node pcp/scripts/pcp.js actualize
```

## 5. Risks

1. Gates not run by the planner (no shell); baseline asserted from ORCHESTRATOR-LOG at `b6b43ff`; counts derived from listings. I0 re-verifies.
2. `prelude.json` `runtime` field has no consumer found; renamed for consistency, `rg '_as\b'` is the backstop.
3. tree-sitter extension→file-types coupling unverified; `file-types` moves in I1 so a mis-scope fails loudly.
4. `grammar.js` names ast-grep as a query consumer; no ast-grep config in tree — external consumers unverified.
5. `.plans/phase-3/FEASIBILITY.md` is the Wasm doc but phase-3 is now the rename; filing is an orchestrator housekeeping decision.
6. Handbook cost neutral: `AgentS-Core`→`AgentScript` is 11→11 chars.
