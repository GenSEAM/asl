# EXPERIMENT.md: ASL against Python and TypeScript, generation baseline

**Status: PRE-REGISTERED, protocol v2 of 2026-11-13. No baseline arm has run. Running it spends model budget and needs the principal's approval.**

Integrity note: v2 was written after ASL-only results had been seen (462 trials of one arithmetic family, 145 raw passes, 420 after heal, 2026-10-15; no comparator arm). No Python or TypeScript generation result existed when the thresholds below were set. Protocol v1 and its amendments are kept unedited in the appendix; v2 supersedes them wherever they differ.

Amendments are dated, appended under "Amendments" in the appendix, and state whether they were made before or after seeing results. An amendment made after results invalidates the pre-registration for the metric it touches.

Paths are relative to this repository; paths starting with `tools/` or `.asl/` are in the development workspace and are named where the published tree has no equivalent yet.

## 1. Question

Do models write correct ASL about as reliably, and at about the same token cost, as they write Python and TypeScript, on the same tasks, with the same models and budget? This has never been measured. Two dialect questions ride on the same tasks: brackets against parens only, and the bare function header against a parenthesised one.

## 2. Hypotheses and decision rule

| ID | Hypothesis | Refuted when |
|---|---|---|
| **H1** (primary) | ASL is generated competitively | healed pass@1 of arm `asl` is more than **15 points** below raw pass@1 of `py` **or** of `ts`, on either model |
| **H2** (primary) | ASL costs no more to get to green | tokens per solved task of `asl`, language card excluded, exceed **1.5 times** that of `py` or `ts`, on either model |
| **H3** | brackets generate better than parens only | `aslParen` raw pass@1 is not below `asl` (paired by task, Holm-adjusted p < 0.05, difference of 10 points or more counts as an effect) |
| **H4** | a parenthesised `(fn ...)` header generates better than the bare column-0 line | `aslWrapFn` raw pass@1 is not above `asl` by the same test |

The 15 point threshold is the one v1 fixed. The 1.5 factor and the 10 point effect size are new in v2.

Decisions, applied in a dated row in `bench/publishedClaims.asn`:

- H1 or H2 refuted: language surface work stops. Effort moves to the harness and toolbelt on existing Python and TypeScript repositories. No prompt, card or grammar iteration to rescue the number.
- H1 and H2 hold with a 95% interval that still crosses a threshold: run phase B (section 8) before claiming anything.
- H3 or H4 shows an effect: the winning surface is adopted (for H4, the parser accepts both headers) and manifesto, README and `llms.txt` are aligned. No effect: the current surface stays and the question is closed.

## 3. Tasks

30 tasks in 3 families of 10. Each task has a language-neutral statement, one idiomatic signature per language, 2 example cases shown to the model and 6 graded cases (at least one edge case) that are not shown.

| Family | Tasks |
|---|---|
| A, arithmetic and strings | `sumDigits` `gcd` `isPrime` `fizzbuzzLine` `collatzSteps` `clampInt` `powMod` `countVowels` `reverseWords` `romanNumeral` |
| B, lists and options | `maxOf` `secondLargest` `indexOf` `dedupeKeepOrder` `runLengthEncode` `mergeSorted` `chunk` `histogram` `firstFailure` `lookupChain` |
| C, records and enums | `shapeArea` `exprEval` `trafficLightNext` `accountApply` `parseCommand` `inventoryTotal` `pointInRect` `classifyToken` `stackMachine` `updateUser` |

Absence and failure are expressed the way each language does it: `Option` and `Result` in ASL, `T | None` and `ValueError` in Python, `T | undefined` and a thrown `Error` in TypeScript. `histogram` is the existing `bench/tasks/histogram.asn`.

Files to write before any model call, one per task: `bench/gen/tasks/<id>.asn` (statement, signatures, cases) and hand-written reference solutions `bench/gen/ref/<id>.{asl,py,ts}`. Reference solutions are written by hand, not generated. A task whose ASL reference cannot be written is a language finding, logged in `bench/gen/results/inexpressible.asn`, and is replaced before the run.

## 4. Arms

| Arm | Language shown to the model | Checked by |
|---|---|---|
| `py` | Python 3.13 with type hints, no card | `python3 -I` on solution plus graded cases |
| `ts` | TypeScript, no card | `tsc --strict --target es2022`, then `node` on the output |
| `asl` | current surface: `[ ]` lists and bindings, bare `fn name a: T -> R` header | `bin/asl check`, then `bin/asl test` |
| `aslParen` | parens only: `(let ((x e)) ...)`, no brackets | normalised to the current surface, then as `asl` |
| `aslWrapFn` | `(fn name [a: T] -> R body)` as one form | normalised to the current surface, then as `asl` |

- The ASL card is the section "The language" of `llms.txt` at the run commit, with its sha256 recorded (the whole file is 1569 `o200k_base` tokens on 2026-11-13). The two variant cards are that text with the one construct substituted mechanically; nothing else changes.
- Normalisers for the variant arms start from `rewriteLetShape` and `normalizeHeader` in the workspace's `tools/synProbes.asl`. Each must turn the variant spelling of all 30 reference solutions into text that passes the graded cases before any arm runs; a normaliser defect is a harness defect, not a model failure.
- Every ASL arm is scored twice: raw, and after `bin/asl heal`. Python and TypeScript get no repair tool, so raw against raw is the like-for-like comparison and healed ASL is its best case. Both are published.

## 5. Procedure

One trial is one task, one arm, one model, one repetition:

1. Turn 1: system prompt (card for ASL arms, one line naming the language otherwise), task statement, signature, 2 example cases. The reply must hold one fenced code block.
2. Stages, in order, first failure recorded: `extract`, `parse`, `check`, `execute`, `correct` (all graded cases pass).
3. If not correct, a repair turn sends back the first 2000 characters of the tool output and the names of failing cases. At most 3 repair turns, so 4 calls per trial.
4. The trial ends green or exhausted.

Fixed settings: temperature 0.2, at most 1200 output tokens, 5 repetitions, seed recorded where the provider takes one. Trial order is shuffled with a recorded seed so that provider drift falls on all arms alike. Calls are plain chat completions through the gateway (`/v1/chat/completions`), not through the agent loop: this measures the language, not an agent's write discipline. Token counts are the gateway's usage rows, not a local tokenizer.

Children (python3, node, tsc, `bin/asl`) run through `tools/fleet/run.asl` with a 30 second limit and a descendant limit; nothing starts the running executable.

## 6. Models

Named by gateway alias; the provider's exact model id and the date are recorded per call from the gateway usage row.

| Slot | Alias | Why |
|---|---|---|
| M1 | `synDs41Flash` | the project's main writer model |
| M2 | `ocClaudeHaiku55` | a second family at small-model price |
| M3 (optional) | `opus` | frontier check on 10 tasks (families B and C, 5 each), 3 repetitions |

An alias that is absent or fails its first call is replaced by another model of the same class before the run, in an amendment; never during it.

## 7. Metrics

Per arm and model, over 150 trials (30 tasks, 5 repetitions):

- **raw pass@1**: turn 1 is correct with no repair and no heal.
- **healed pass@1** (ASL arms): turn 1 is correct after `bin/asl heal`.
- **solved**: green within 4 calls.
- **tokens-to-green**: prompt plus completion tokens summed over the calls of a solved trial; median and quartiles.
- **tokens per solved task**: all tokens the arm spent, solved or not, divided by solved trials. This is the headline cost figure; it is reported with the card counted and with the card excluded, side by side.
- **repair turns per solved task**, and the stage of first failure.

Intervals: 95%, by bootstrap over tasks (10000 resamples), since repetitions of one task are not independent. H3 and H4 are paired by task with Holm adjustment over the two comparisons.

## 8. Size, cost and cap

Pilot (this protocol): 30 tasks, 5 arms, 2 models, 5 repetitions = **1500 trials**, at most 6000 calls. M3 adds 150 trials (10 tasks, 5 arms, 3 repetitions).

Token estimate, both models together; these are assumptions until the pilot measures them (prompt 300 tokens without card, 1900 with it; 250 output tokens per call; each repair turn adds about 600 prompt tokens):

| Case | Input tokens | Output tokens |
|---|---|---|
| expected, 2 calls per trial on average | about 4.7 M | about 0.75 M |
| worst, 4 calls on every trial | about 13 M | about 1.5 M |

Money is input M times input price plus output M times output price, with the prices of the gateway's model rows on the day. At the cheap-tier prices in `bench/harness/config.example.asn` (0.15 and 0.60 USD per million, an assumption, not a quote) that is about 1.2 USD expected and 2.9 USD worst. M3 at frontier prices is the larger item and is priced separately before it is approved.

**Cap:** the runner tracks cumulative spend from gateway usage rows and aborts mid-run at the cap the principal sets (proposed: 15 USD for M1 and M2 together). The 0.20 USD cap of amendment 2026-08-20-c applied to a 3-task smoke run and is superseded for this pilot. A subscription-backed alias still counts against the cap at its list price.

Phase B, only if the pilot is inconclusive: 30 more tasks in the same families (60 in all), same arms and models, a separate approval.

## 9. What must exist before the first call

None of this spends model budget.

1. The 30 task files and 90 reference solutions (section 3).
2. A runner, `bench/gen/run.asl`, with these entry points:

   ```sh
   bin/asl run bench/gen/run.asl verify               # every reference passes in every arm, normalisers included; no model call
   bin/asl run bench/gen/run.asl dry                  # canned replies reach every stage, including a check failure and an exhausted trial
   bin/asl run bench/gen/run.asl pilot --model synDs41Flash --cap-usd N --seed S
   bin/asl run bench/gen/run.asl report               # recomputes every table from bench/gen/results/<date>/trials.asn
   ```

   It does not exist on 2026-11-13: `bench/harness/` holds only `config.example.asn`, `bench/tasks/` holds 5 files and no runner. The workspace's `tools/synProbes.asl` (trial directories, check, test and heal under limits) is the starting point; its model call goes through the agent loop and must be replaced by a plain gateway call.
3. A gate for the runner: red before, green after, and red on a mutant that swaps two arm labels.
4. `python3`, `node` and `tsc` versions recorded in the results header.

## 10. Record and grading

- Raw rows: `bench/gen/results/<date>/trials.asn`, one row per trial with arm, task, model id, repetition, stage of first failure per turn, tokens per call, and the reply text.
- `report` is rerun from those rows by a grader who did not write the runner, in a clean checkout; the tables published are the grader's.
- `bench/publishedClaims.asn` gains one measured row per headline figure, naming the results file. The status line of this file changes only then.
- Everything is published, including a refuted H1.

---

# Appendix: protocol v1 and its amendments (superseded where v2 differs, text unedited)

## 1. What is being tested

AgentSlang's premise is that a regular S-expression syntax, injected into a system prompt, lets LLMs
generate code more reliably than mainstream languages, and that this justifies a DSL between the
model and native Rust/Go.

`researchReport.md` found this premise **untested by anyone** — no located source evaluates
S-expressions — and found evidence pointing the other way: generation quality tracks
training-corpus presence, and AgentSlang is by construction zero-corpus.

This experiment resolves that empirically, cheaply, before a compiler is written.

## 2. Hypotheses

| ID | Hypothesis | Falsified if |
|---|---|---|
| **H1** | LLMs generate syntactically valid AgentSlang at rates competitive with mainstream languages | parse rate materially below baseline compile-parse rates in the unconstrained arm |
| **H2** | LLMs generate *functionally correct* AgentSlang competitively | AgentSlang pass@1 more than **15 pp** below Go **and** Rust baselines (primary gate) |
| **H3** | Grammar constraints help rather than hurt | constrained arm's pass@1 falls below the same model's unconstrained pass@1 |
| **H4** | AgentSlang is expressive enough to host its own compiler | the lexer probe (§7) cannot be written in Core |
| **H5** | Core transpiles cleanly to Rust and Go | compile rate < 95%, or differential disagreement on any task |

**H2 is the primary gate.** H1 is necessary but cheap and largely guaranteed under constraint —
per `researchReport.md` §2.2, constrained decoding gives ~100% parse success to *any* grammar, so
H1 passing is weak evidence and must not be reported as concept validation.

## 3. Benchmark

**Tasks:** HumanEval. Baselines come free from **MultiPL-E**, which publishes parallel
translations with unit tests for Python, TypeScript, Go, and Rust. Only the AgentSlang translation is
produced here.

* **Phase A:** 50 tasks (fixed subset, ids recorded in `bench/tasks/SUBSET.txt` before running).
* **Phase B:** all 164, only if Phase A clears the gate.

**Sampling:** n = 10 per task per arm per model. temperature 0.2, top_p 0.95, seed recorded.
Metric: **pass@1**, computed as the unbiased estimator over n samples.

**Translation integrity:** the AgentSlang translations are written by hand from the Python originals,
*not* generated by an LLM, and are reviewed against the reference tests before any arm runs.
Every AgentSlang task must be verified solvable by the reference interpreter first — a task the
language cannot express is a language finding, not a model finding, and must be logged separately
in `results/inexpressible.md`.

**Known caveat:** MultiPL-E translation quality is not uniform across languages. The Go baseline
will be spot-checked on 10 tasks before use; if it is visibly degraded, Rust becomes the primary
comparator and this is recorded here as an amendment.

## 4. Arms

| Arm | Condition | Runtime | Purpose |
|---|---|---|---|
| **A** | `agentSpecCore.md` in system prompt, unconstrained | OpenRouter | headline number |
| **B** | A + 3 few-shot worked examples | OpenRouter | measures how much of the gap is closed by examples |
| **C** | A + GBNF grammar constraint | llama.cpp, local | isolates the grammar effect |
| **Base** | MultiPL-E Python / TS / Go / Rust, unconstrained | OpenRouter | comparator |

**Arm C runs locally, not on OpenRouter.** OpenRouter exposes JSON-schema structured output for
some models but **not arbitrary CFG/Lark grammars**. llama.cpp supports GBNF natively.

Consequence, stated so it is not overclaimed later: **C is only comparable to A within the same
local open-weight model.** The constrained-vs-unconstrained contrast is therefore measured on that
model alone, and no constrained number exists for frontier models. Any claim of the form
"constraints fix frontier generation" is out of this experiment's reach.

## 5. Models

* **OpenRouter (arms A, B, Base):** Claude Opus 5, Claude Sonnet 5, one GPT-class frontier model,
  one open-weight model matching the local one below. Exact slugs and dates recorded in
  `results/models.json` at run time.
* **Local (arms A and C, paired):** one open-weight coder model, 7–14B GGUF, fits M1 Pro / 32 GB.

The same open-weight model appears in both the OpenRouter and local sets to sanity-check that the
local harness reproduces hosted behavior on arm A.

## 6. Primary gate

> **AgentSlang pass@1 must be within 15 percentage points of both the Go and Rust MultiPL-E baselines,
> on the same tasks and the same models, in arm A or B.**

Arm C may be reported but **does not satisfy the gate**, because no frontier constrained number
exists to compare against (§4).

**If the gate is missed:** stop. Do not iterate on prompt wording, examples, or grammar until it
passes — that is how a null result gets laundered into a positive one. Report the number, then
evaluate the pivot named in `researchReport.md` §5 (synthetic programming elicitation: choose a
syntax models already emit fluently and transpile from that).

**Secondary measurements** (reported, not gated): token count per solution vs baselines; error
taxonomy — parse / type / runtime / wrong-answer, which tests whether the ~6%-syntactic /
~94%-type split from `researchReport.md` §5 reproduces on AgentSlang.

## 7. Expressiveness probe (H4)

Write the AgentSlang lexer **in AgentSlang**. Pass condition: it tokenizes the Stage 1 conformance
corpus and matches the reference Rust lexer token-for-token.

Prediction on record: **this will fail without user-defined sum types** (`SPEC_REVIEW.md` G5; that review is not in this repository), since
token kinds are a sum. Recording the prediction now so that discovering it counts as confirmation
rather than hindsight.

**Superseded — see amendment 2026-08-20-a.** The language gained closed unions before the probe was
run, so this prediction can no longer be confirmed or refuted by it.

## 8. Transpiler gate (H5)

* compile rate ≥ 95% for both `rustc` and `go build` on generated output
* **differential testing:** interpreter, Rust, and Go agree on every task; any disagreement is a
  blocking defect
* reported, not gated: clippy warnings/KLOC, `go vet` count, `.clone()` density in generated Rust
  (the cost of the Rc-everywhere strategy from the plan's Stage 4)

## 9. Amendments

### 2026-08-20-a — H4 prediction superseded (made BEFORE any results)

`AgentSlang` v0.2 added user-declarable closed unions, which §7 had predicted the lexer probe
would fail without. The prediction was made against v0.1 and is now untestable: the probe can no
longer fail for the predicted reason.

No result had been observed when this amendment was made — the probe has never been run, and no
measurement arm has executed. The change originates from a language-scope decision, not from
seeing an outcome.

**Replacement prediction for H4:** the probe now succeeds in producing a lexer, and the binding
constraint moves to what remains absent from Core — I/O and FFI — meaning a self-hosting compiler
stays blocked on reading its own source file rather than on expressing its token type.

### 2026-08-20-b — benchmark and measurement targets changed (made BEFORE any results)

No arm has run and no result has been observed. The change follows from the project goal, not from
an outcome.

**Benchmark: HumanEval → terminal-bench.** HumanEval is a suite of small self-contained functions
and therefore cannot exercise the property v0.2 was built for: modules, reuse, and how much
*working* code survives one pass. Measuring on it would have scored the language on the one axis
its redesign was not about. terminal-bench tasks are whole working programs, which is the unit
this project defines as a pass.

**SWE-bench was considered and rejected for now.** Its tasks are edits inside existing Python
repositories, so a solution must import, subclass and interoperate with arbitrary host code. Core
has no FFI by deliberate design, so such a patch is currently inexpressible — the measurement
would report a scope boundary as a language failure. Revisit only if FFI enters Core.

**Measurement targets: Python and JavaScript.** These are where the benchmark and its human
baselines live. Rust and Go remain the compiler's own self-hosting targets and are unchanged as a
product goal; they are simply not what the generation experiment compares against.

**Consequences for the pre-registered gate.** The comparator is no longer MultiPL-E's Go/Rust
translations but real Python/JavaScript solutions to the same terminal-bench tasks. The 15 pp
threshold is retained in form but now applies against those baselines. §3, §4, §5, §6 and §8 are
superseded by this amendment wherever they name HumanEval, MultiPL-E, or Go/Rust as comparators.

**A new blocking dependency this creates:** terminal-bench tasks read input and write output.
Core has **no I/O at all** — it is on the deliberate exclusion list. The language must gain an I/O
surface before any arm can run, and that is a scope decision, not a harness detail. Recorded as
PCP `r-io`. Until it is resolved, this benchmark is unrunnable regardless of gateway access.

**H5 is restated:** Core transpiles cleanly to Python and JavaScript — compile/import rate and
differential agreement against the reference interpreter, on those two targets.

### 2026-08-20-c — pilot scope and spend cap (made BEFORE any results)

No arm has run. This amendment narrows the first run to fit an explicit budget.

**Scope: 2-3 borderline tasks, not the suite.** Chosen for being at the edge of what Core can
express, since a task the language handles comfortably tells us nothing we do not already know.
Task ids are fixed in `bench/tasks/PILOT.txt` before the first call.

**Spend cap: $0.20 per run, enforced in the harness, not by intention.** The harness must track
cumulative spend and abort mid-run when the cap is reached rather than reporting an overrun
afterwards. Measured payload: the specification is ~6,000 tokens and is resent on every call, so
it dominates cost; at cheap-tier pricing 60 calls is roughly $0.08 and 120 roughly $0.16. Prompt
caching, if the gateway offers it, cuts that by around two thirds.

**This pilot cannot satisfy the primary gate, and must not be reported as if it had.** A pass@1
estimate over 2-3 tasks carries no useful confidence interval; the 15 pp threshold in §6 is
unevaluable at this sample size. What the pilot *can* do is detect catastrophic failure — a model
that cannot produce parseable or type-correct AgentSlang at all — which is a cheap and legitimate kill
gate. A positive pilot licenses spending on a real run; it does not validate the concept.

**Host language decided:** the compiler is hosted in Rust (PCP `D2030`). This does not affect the
measurement targets, which remain Python and JavaScript per amendment 2026-08-20-b.

### 2026-08-21-a — H5 restated to the backends that exist (made BEFORE any results)

No arm has run. Amendment 2026-08-20-b restated H5 over Python and JavaScript, on the reasoning
that the benchmark and its baselines live there. Two backends now exist and neither pairing matches
that text: **Python and Rust** are implemented, JavaScript has lowering rules in the prelude but no
transpiler, and Go has neither.

**H5 as it now stands:** Core transpiles cleanly to Python and Rust — every corpus program lowers,
`rustc` accepts the Rust, and the two backends agree on every case of every benchmark task.

That last clause is the substantive part and it is already enforced by a differential gate rather
than asserted. Cross-runtime agreement is not a default: measured on this machine, Python and
JavaScript disagree on `2**53+1` and on rounding a half. Equivalence exists only where a gate
enforces it.

JavaScript re-enters H5 when its transpiler exists, not before.

### 2026-08-29-a — a `check` stage added to the classification (made BEFORE any results)

No arm has run and no result has been observed. The change follows from a component landing, not
from an outcome.

A semantic checker now exists, so `STAGES` becomes `extract, parse, **check**, transpile, execute,
correct`. Previously a program that parsed but was semantically wrong could only die at
`transpile`, or not at all — the harness lowered unchecked source, and parse and lowering shared
one call, so the two were indistinguishable in the record.

This adds resolution to the instrument; it does not move the pre-registered gate. The 15 pp
threshold against the Python and JavaScript baselines is unchanged, and no threshold is defined
over the new stage. The dry-run path gained a third canned sample — one that parses and fails the
checker — so the new stage is exercised rather than assumed reachable.

### 2026-09-03-a — the I/O blocking dependency is resolved (made BEFORE any results)

No arm has run and no result has been observed. This amendment records that a dependency the
2026-08-20-b amendment named as blocking has since been met.

That amendment stated: "Core has **no I/O at all** — it is on the deliberate exclusion list. The
language must gain an I/O surface before any arm can run." **It has.** §6.8 declares nine I/O
builtins, failures are values of the closed union `IoError`, effects are tracked by a `!` marker on
the signature (§4.2, §5.7), and a program's entry point is `main` (§4.0). Every backend lowers it,
and the differential gate compares whole programs on stdout *and* exit status across all six
targets, including a failing path, so the error mapping each host derives independently is checked
rather than assumed. PCP `r-56bf`, `D4533`.

The earlier amendment's text is left as written. Pre-registration means the record of what was
believed when is not edited afterwards; a later fact goes in a later entry, dated, which is what
this is.

**What is still blocking, restated so the two are not confused.** The language is no longer the
constraint. Two things are:

1. **The harness has whole-program mode and no task uses it.** `bench/harness/run.py` still drives
   an entry function with cases, and `bench/tasks/histogram.json` is a pure-function task, so the
   terminal-bench shape this amendment series chose has nothing written against it.
2. **Gateway access** — the endpoint, the exact model identifier, and the environment variable
   holding the credential. Unchanged since it was recorded; PCP `l-298e`.

No threshold moves. The 15 pp gate against the Python and JavaScript baselines stands as written.

### 2026-10-14-a — references brought up to date (made BEFORE any results)

No arm has run and no result has been observed. This amendment changes no hypothesis, threshold
or gate; it records where the files this protocol names stand today.

**Renamed in place.** `RESEARCH_REPORT.md` is now `researchReport.md` and `AGENT_SPEC_CORE.md` is
now `agentSpecCore.md`; the references above were updated to the new names and nothing else in
those sentences changed. `SPEC_REVIEW.md` is not in this repository. `researchReport.md` §5, as it
stands, names no "synthetic programming elicitation" pivot; §6's reference to it has no target.

**The harness named in 2026-09-03-a is gone.** `bench/harness/run.py` is not in the tree;
`bench/harness/` holds only `config.example.asn` (endpoint, model, key variable, $0.20 spend cap,
5 samples per task), and nothing reads it. The task once at `bench/tasks/histogram.json` is now
`bench/tasks/histogram.asn` (HumanEval/111, still a pure function with cases).
`bench/tasks/SUBSET.txt`, `bench/tasks/PILOT.txt` and `results/` have not been written. A harness
must exist again before any arm can run; this is now blocking alongside gateway access.

**Host language (2026-08-20-c) superseded.** The compiler is not hosted in Rust. The stage-0 host
is C (`host/src`); the native compiler `asl1` is written in ASL and lowers through LLVM IR
(`asl-target-llvm`), with a committed seed for `arm64-apple-darwin` only.

**H5 backends (2026-08-21-a).** `asl-target-py` and `asl-target-rs` are source-to-source
prototypes, and the differential gate that amendment describes is not identified in the tree today.
H5 is left as last stated; restating it over the backends that now produce runnable output
(LLVM IR, native and `wasm32-unknown-unknown`) is a decision for a later amendment.

### 2026-11-13-a — protocol v2 (made BEFORE any baseline result, AFTER ASL-only results)

No Python, TypeScript or other comparator arm has run. ASL-only generation results existed and had
been read when this was written: 462 trials of one parametric arithmetic family on free models,
145 raw passes and 420 after a mechanical heal pass (2026-10-15), with no baseline arm. The
thresholds for the new metrics were set knowing those numbers and not knowing any baseline number.

**What changes.** Sections 1 to 10 at the top of this file replace §1 to §8 and the benchmark,
comparator, pilot scope and spend cap of amendments 2026-08-20-b and 2026-08-20-c: tasks are 30
small functions in three families instead of HumanEval or terminal-bench; comparators are Python
and TypeScript; arms for the bracket and the function-header questions are added; the metric set
gains raw and healed pass, tokens-to-green and tokens per solved task; the pilot is 1500 trials
with a cap the principal sets. H4 (lexer probe) and H5 (transpiler agreement) of v1 are dropped
from this experiment: the compiler is now written in ASL and compiles itself, which answers H4,
and the source-to-source targets H5 named are prototypes outside the core scope.

**What does not change.** The 15 point threshold on the primary gate, and the rule that a missed
gate is reported and not iterated on.

**Stale facts in earlier entries, left as written.** 2026-10-14-a says the stage-0 host is C
(`host/src`) with a seed for `arm64-apple-darwin` only. The C host had been deleted on 2026-10-13;
`host/` holds a build script and tests, and `seed/` holds three triples.
