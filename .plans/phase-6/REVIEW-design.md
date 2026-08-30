# REVIEW-design — Phase 6 PLAN.md (lens: design & feasibility)

Reviewer: steps-architect-pro. Scope: soundness and buildability of the six recorded
decisions (D1–D6) and the W1–W8 ordering. All cited files read this session; every probe
below was run read-only against the current tree (nothing was written except this file).

## Verdict: **approve-with-amendments**

0 blockers, 4 major, 4 minor. The plan's mechanisms are real where it claims them
(`_ambig` counting works and is deterministic; `tree-sitter build` emits a loadable
shared lib; the span baseline 1/17 is accurate), and every gate fails now as stated.
Four amendments are needed before implementation: the ambiguity baseline is not
reproducible, W2's line range would delete live grammar, W1/W2 ratchet semantics
contradict each other, and W5's shim adaptation is much larger than described because
the stashed shim's contracts no longer exist in the tree.

## Findings

### MAJOR-1 — Baseline 219 is not reproducible under the plan's own mechanism
The plan states the Earley ambiguity baseline as 219 over "all 43 parseable fixtures"
(PLAN.md §1; "213 + 6"). I re-ran the mechanism as specified — same Lark (1.3.1, confirmed
by `.venv/bin/pip list`), `parser="earley", ambiguity="explicit"` over the same grammar
(`grammar/agentscript.lark`), counting `_ambig` nodes over
`grammar/corpus/{valid,semantic,modules}`. Result: **79 fixture files (29 valid + 44
semantic + 6 modules), total 196**, with the largest contributor 14-sequenced-bodies at 21
(plan says 25). Neither the fixture count nor the total matches. The mechanism itself is
verified sound — `_ambig` nodes are countable and the count is deterministic (repeat parse
of the most ambiguous fixture gave 21/21) — so this does not block the phase, but the
"measured baseline" is stale or was taken against a different corpus state/glob. Amendment:
W1 must record whatever the auditor measures via `--write` and the plan must stop asserting
219 as the figure; the lock, not the prose, is the baseline.

### MAJOR-2 — W2's line range deletes live grammar and misses dead lines
PLAN.md §3 W2 and D2 name the dead alternatives as `grammar/agentscript.lark:93-101`.
Actual rule (read this session):

- lines 91–97 are the per-case alternatives `OK`/`ERR`/`SOME`/`NONE`/`LIST`/`CONS`/`PAIR`
  (the dead set per PCP `l-b1b8`, `.pcp/lang/lexical.md:40`);
- lines 98–100 are `literal | IDENT | WILDCARD` — **live**; deleting them removes bare-id,
  literal and wildcard patterns entirely.

An implementer following 93–101 literally breaks pattern parsing (and leaves `OK`/`ERR`
behind). I simulated the correct removal in memory (drop exactly 91–97): all 79 fixtures in
valid/semantic/modules still parse, and the `_ambig` total drops 196 → 121 (101 + 14 + 6),
so the intended change is safe and does reduce the count — consistent with PCP `l-b1b8`'s
claim that Earley already resolves every such pattern to `enum_pattern`. Amendment: cite
lines 91–97, or define the removal as "the seven per-prelude-case alternatives, i.e. every
alternative other than `enum_pattern`, `literal`, `IDENT`, `WILDCARD`".

### MAJOR-3 — W1's check semantics contradict W2's gate; the improvement would pass unrecorded
W1 specifies `--check` "fails if greater" than the lock (PLAN.md §3 W1). W2's gate says the
same command "fails with a count below the lock until `--write` records the new figure"
(§3 W2). Both cannot hold: under fail-if-greater, W2's reduction **passes silently** against
the old lock and nothing forces the `--write` — the phase's headline "driven down and
recorded" number is then never recorded, and the acceptance axis ("driven to zero **or
recorded**") is met in form only. Amendment: make `--check` exact-match (fail on any
difference, up or down), matching how every other lock in this repo is deliberate-write
(`prelude/coverage.lock` precedent per AGENTS.md); or restate W2's gate as an assertion on
the lock's contents. This is the conformant-but-wrong hazard: every item nominally has a
failing gate, but W2's gate cannot fail under W1's stated semantics.

### MAJOR-4 — W5 under-scopes the shim adaptation; the materialised script cannot start
D1/W5 describe the distributor work as rename + prune `BACKENDS` + path updates. The stashed
shim (`git show 'stash@{0}^3:as-lang'`, read this session) depends on contracts that no
longer exist:

- `TARGETS` is read from `prelude/prelude.json`'s `"targets"` key at startup — the file has
  no such key (actual keys: `$comment, version, runtime, special_forms, types, builtins`,
  verified by direct load). The script raises KeyError before any subcommand runs.
- `cmd_check` calls `check.parser()`, `check.check_file(parser, f)`,
  `check.import_cycles(models)`, `check.target_capabilities(models, target)`. Current
  `checker/check.py` is a thin argparse CLI exposing only `main()`; the real entry is
  `checker/resolve.py:641` `check_file(path, roots) -> list[Diagnostic]`. No
  `import_cycles` or `target_capabilities` exists anywhere in `checker/` or `backend/`
  (grep). `--rules` has no counterpart in the current `check.py` either.
- `cmd_build`'s TargetMismatch/rule-13 stderr contract references features
  (`target_capabilities`) that are gone with the above.

So W5 includes a silent re-design of `check` against `resolve.check_file` (deciding the fate
of `--target`/`--rules`: drop, or re-implement — a scope decision for the orchestrator) and a
replacement for the TARGETS load. The W5 gates (CLI smoke: `check grammar/corpus/valid`
exits 0) will force the fix, so this is not a blocker, but the item as written is materially
larger than "rename and repoint". Amendment: enumerate the checker-API rewrite in W5's What
and flag the `--target` decision.

Verified-clean parts of D1, for the record: pruning `sw` is correct — `backend/` contains
only `to_python.py` and `to_rust.py` (`backend/golang/` is runtime support, no emitter);
`differential.py` drives exactly py/rs/interp arms (differential.py:196,215,248). The name
`agentscript` collides with nothing: no `.venv/bin/agentscript`, no `node_modules/.bin`
entry, and the only Cargo binary is `agentscript-interp`
(`crates/agentscript-interp/Cargo.toml` `[[bin]]`); `package.json`'s `"name"` has no `bin`
field. The stash contains exactly `as-lang`, `tools/fmt/fmt.py`, `tools/fmt/t/test_fmt.py`
(`git ls-tree -r 'stash@{0}^3'`), so no grammar drift enters via the stash.

## MINOR findings

### MINOR-1 — D3 conflates bytes and characters in its own baseline
HANDBOOK.md is 12,779 **bytes** (`wc -c`) but 12,749 Unicode **characters**
(`len(read_text())`, both measured). PLAN.md §1 says "12,779 chars (`wc -c`), 2,454
bytes" — inverted and internally inconsistent; §4 repeats "12,779-char ratchet". If
`budget.py` records `len()` characters as D3 states, the baseline is 12,749. Amendment:
pick one unit, state it, and record the matching number. The design itself is sound: char
count is monotone in token count for this document, and the handbook is indeed the
per-call payload (AGENTS.md "HANDBOOK.md is what goes into an agent's prompt"), so a
char ratchet guards the stated goal without a tokenizer's determinism question.

### MINOR-2 — D4's denominator counts variants no error can ever mention
The 17-variant count and 1/17 baseline are accurate (`crates/agentscript-interp/src/ast.rs:65-88`;
only `IntLit` carries a span, ast.rs:52-56; 29 `Err(` sites in eval.rs confirmed by count).
But `Float/Str/Bool/Unit` never reach any of eval.rs's Err sites, so the locked fraction can
never reach 17/17 without span-plumbing that serves no diagnostic — the metric rewards work
the goal doesn't need. The plumbing claim itself checks out: `cst.rs:70-73` already lowers
tree-sitter positions into `Span`, so threading is data movement as D4 claims. Amendment:
define the denominator as the failable-variant set (derived from the Err-site survey W8
already mandates) or lock the rationale for 17 in `span.lock`.

### MINOR-3 — grammar.js drift after W2 is real but invisible; record the decision
Removing the lark alternatives leaves `grammar.js:195-215`'s seven named pattern rules
(`ok_pattern`…`enum_pattern`) unmatched on the lark side. This does not break the "both
grammars change together" rule as enforced: the accepted language is unchanged,
`validate.py` compares verdicts only (validate.py:59-60, 176-180), and `queries/searches.scm`
references no pattern nodes (grep returned nothing), so no gate sees the shape drift — and
changing grammar.js *would* change node shapes (the worse drift). The plan's "only if the
removal changes node shapes (not expected)" is therefore the right call, but the rationale
should be stated as a decision, not a hope, since AGENTS.md's rule exists precisely against
silent drift.

### MINOR-4 — D5's fallback is thin, and the crate it lands in has no bin target
The primary mechanism is more likely than not: `tree-sitter build -o` succeeded against this
grammar in my probe (67 KB .so produced under /tmp; CLI 0.26.12 per package.json). But the
Python `tree-sitter` package is not installed in `.venv` (pip list shows lark only), so
`Language()` loading the built lib remains unverified — the plan already declares this in
§5 Risks, and W5's tests bind the CLI surface, not the mechanism, which is the right
structure. Two amendments: (a) spec the JSON output contract of `ast --json`/`search`/`edit`
*now*, so the Rust fallback is a real alternative rather than a sentence; (b) note that
`crates/agentscript-ts` is `staticlib + rlib` with no `[[bin]]`
(`crates/agentscript-ts/Cargo.toml`), so the fallback needs a new bin target (or a new
crate) named in the plan.

## Conformant-but-wrong note

MAJOR-3 is the instance: the plan formally satisfies "every item has a gate that fails now"
(all eight gates verified failing this session, verbatim outputs match PLAN.md's except
where noted below), yet under W1's stated fail-if-greater semantics W2's gate passes without
recording anything — the ratchet would protect the old number against growth while silently
discarding the improvement the phase exists to make.

## Gate verification (run this session)

All six file-existence gates fail now with the outputs PLAN.md quotes (pytest's
"file or directory not found" lines confirmed for W3/W5/W6/W8; "can't open file" for
W1/W4/W7). Supplementary observations:

- W1 probe (mine, read-only): explicit-ambiguity parse of all 79 fixtures — works,
  deterministic, 196 `_ambig` (see MAJOR-1).
- W2 simulation (in-memory only): removing lines 91–97 keeps every fixture parseable,
  count drops to 121 (MAJOR-2).
- `tree-sitter build` probe: succeeds for this grammar (MINOR-4).

## Risks (unverified — not asserted as fact)

1. Python `tree-sitter` `Language()` loading the CLI-built .so was not testable without
   installing the package into `.venv` (an environment change outside a review's remit).
   Plan's §5 risk register covers this; the fallback keeps W5's gate intact.
2. Stashed `fmt.py` fit to the current corpus beyond the known token-name drift
   (`DEFENTRY`/`DEFEXTERN`/`DEFOPAQUE` in its FORM_KW vs `grammar/parse.py:20-23`) is
   unknown until W3 runs; plan acknowledges. I read the stash's parser construction and
   FORM_KW but not the full printer, so `format_file`/`Diag` signatures assumed present per
   `as-lang`'s imports.
3. W8 vs `differential.py`: program mode compares stderr verbatim across four arms and
   against declared values (differential.py:367-410). All current program cases are exit 0/1
   with stderr written by the *program* (e.g. `"not-found\n"`, differential.py:442), and
   interpreter runtime errors are exit 2 (main.rs:14-18) — so W8 most likely touches no
   existing case, which is stronger than the plan's cautious note. But "no program case
   traps today" was verified only by scanning the case list at differential.py:428-457, not
   by execution.
4. Whether the 196-vs-219 gap (MAJOR-1) comes from corpus growth since the plan session or
   a different glob is unknown; either way the lock written by W1 supersedes the prose.
