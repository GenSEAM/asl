# Loop benchmark: maintenance work on one codebase in two languages

Date 2026-11-13. Unit `LOOPBENCH`. Runner `asl/bench/loop/` (core.asl, run.asl), tasks
`asl/bench/loop/tasks/*.task`, results `asl/bench/loop/results/`, design ledger and backlog
rows `.asl/mem/audits/fable-20261113/designChoice.asn`.

Not repeated here, only referenced: the write-from-scratch generation bench
(`asl/bench/gen`, `asl/EXPERIMENT.md`), miss absorption (reader synonyms and heal, branch
`fable-missabsorb`), instruction cards (`asl/bench/gen/cards`, `asl/bench/gen/cardLab`), the
toolbelt bench (`asl/doc/agentApproach.md`), the type lens (`asl/doc/inferenceDesign.md`).

## 1. The claim under test

On small write-from-scratch tasks ASL loses to Python: the generation bench of today shows a
raw pass near 100 percent for Python and TypeScript and 5 to 30 times more tokens to green for
ASL (section 6 of the ledger). The claim that is still open is about the whole loop of real
work in an existing codebase, where the cost is reading context, locating code, failing late
and repairing:

> H-loop: on maintenance tasks in an existing package, an agent working in ASL with the ASL
> tools solves at least as many tasks as the same agent working in Python with Python's
> standard tools, for fewer total tokens.

The benchmark separates three things that are usually mixed:

| Arm | Language | Tools | Measures |
|---|---|---|---|
| `py` | Python 3.13, typed | read, grep, edit, write, pytest, mypy --strict | the baseline with Python's standard tooling |
| `pyB` | Python | `py` plus outline, symbol, replace, rename | what the same structural tools give when bolted onto Python |
| `aslA` | ASL | read, grep, edit, write, `asl test`, `asl check` | the language alone, same plain tools |
| `aslB` | ASL | `aslA` plus outline, symbol, replace, rename, lens, card | the language with its toolbelt |

`aslA` against `py` is the language effect (prior against strictness). `aslB` against `aslA`
is the tool effect inside ASL. `pyB` against `py` is the share of that tool effect which is not
language-specific. `aslB` against `pyB` is what remains for ASL once Python has the same
structural tools: only the lens, the card and the checker differ there.

## 2. The codebase pair

One package in both languages with the same module and function structure.

- ASL side: `asl/packages/asl-stats` as it stands on main (5 modules, 580 source lines, 384
  test lines, 132 assertions; `tools/layers/layers.asn`: std, rank 20, no imports outside the
  package). The runner copies it into a scratch tree per trial; the header row of every
  results file records the sha256 of the sources it copied.
- Python side: `asl/bench/loop/py/` (package `stats`, 5 modules of the same names, 3 pytest
  files, 17 test functions holding the same assertions and the same oracle values). Ported by
  hand for this unit: snake_case names, `StatsError(ValueError)` in place of `(err ...)`,
  frozen dataclasses for records, loops where the ASL recurses. `python3 -m pytest -q tests`:
  17 passed; `python3 -m mypy --strict stats tests`: clean (Python 3.13.0, pytest and mypy as
  installed; pyright is not installed and was not installed).
- The Python side is **untracked**: `./bin/asl audit foreign` rejects any `.py` file that is
  not listed in `scripts/audit/foreignAllowlist.asn`, and that file is outside this unit. The
  Python halves of the tasks live beside the port, in `asl/bench/loop/py/tasks/`, for the same
  reason. Row `LOOPBENCH-02` asks for the allowlist entries; until then a clean checkout runs
  the ASL arms only.

Size: the brief asked for 1.5 to 4 thousand lines. asl-stats is 964 lines (55 KB, about 15
thousand tokens) and was chosen because it is self-contained, pure, numerically checkable
against the same oracle in both languages, and small enough to port faithfully in one sitting.
It is at the low end of "mid-size": a file fits in one read, so the read-side tools have less
to save than they would on a 30-file package. Row `LOOPBENCH-06` repeats the bench on a larger
pair (asl-zip, 2 088 lines, is the next candidate).

Three places where the port could not be literal, each a real language difference:
`math.exp` raises on overflow and `math.log` raises at 0 where ASL floats give inf and -inf
(the port wraps both in `rng.py`); Python integers do not wrap, so the generator masks to 64
bits; Python has no export list, so the "export it" step of two tasks does not exist there.

## 3. Tasks

Ten tasks, each with a prompt, a seeded starting state, a reference solution and a hidden
acceptance test, in both languages. File format: blocks opened by a `#@` line (`task`,
`prompt`, `seed FILE`/`with`, `ref FILE`/`with`, `gradeEdit FILE`/`with`, `accept FILE`,
`absent`); `refAll` and `gradeEditAll` replace every occurrence.

| Id | Kind | What the agent must do | Layers and files |
|---|---|---|---|
| bugPercentile | bug from a failing test | suite is red; find the off-by-one in the percentile index | describe |
| bugWilson | bug from a failing test | suite is red; a term of the Wilson half-width lost a factor | interval |
| bugCrossModule | bug from a failing test | failing asserts name ranks and mean; the defect is the shared finite check | describe, seen through agree |
| bugReportHedges | bug from a report, no failing test | fix the small-sample correction and add a regression assertion | describe and its test |
| paramResampleSize | parameter through 3 call layers | `size` from bootstrapPercentile through statLoop to resampleLoop, callers updated | interval, tests |
| featureTrimmedMean | feature with a test | new exported function with four error cases | describe and its test |
| renameSumKahan | rename across files | exported name changed in definition, export list, callers, tests | describe, agree, tests |
| guardNanPercentile | behaviour change under an invariant | percentile refuses NaN; percentileSorted and the seeded bootstrap must not change | describe |
| refactorIntervalRecord | typed API change | three functions return a record instead of a pair; tests follow | interval, tests |
| featureRngInt | feature plus refactor | new exported draw, used by the bootstrap loop without changing its stream | rng, interval |

Grading, the same for every arm (`grade!` in core.asl): the pristine test files are restored
over whatever the agent did to them, the task's `gradeEdit` patches are applied (for tasks
that change a signature or a name on purpose), the hidden acceptance file is written, and then
the pristine suite and the hidden file run. A trial is **solved** only when the suite passes,
the hidden tests pass and no `absent` text remains in the sources. Saying `done` is not
evidence; a trial that runs out of turns with a correct tree is solved.

`asl run asl/bench/loop/run.asl verify` proves every task half without a model: the seeded
state must be red and the state after the reference edits green.

## 4. The agent loop

Plain chat completions through the in-process gateway link (the caller is a copy of the 40
lines of `liveOnce!` in `asl/bench/gen/run.asl`, which does not export it; request and reply
types, the ASN reader and the price arithmetic are imported from `aslBench/gen/core`). No
provider tool-call API: every reply holds one call written as tags,

    <tool>edit</tool>
    <path>src/describe.asl</path>
    <old>...</old>
    <new>...</new>

so all arms and models pay the same protocol. The whole conversation is resent each turn, as
agents do, so input tokens grow with every read: that is the cost the read-side tools attack.

- Budget per trial: 16 replies, 3 000 output tokens per reply, 150 000 tokens in total; a tool
  result is cut at 6 000 characters. A run has a mandatory `--maxUsd` cap counted from the
  usage fields of every reply.
- Sandbox: a scratch copy of the package per trial; paths are relative, `..` and absolute
  paths are refused. Children (pytest, mypy, `asl test`, `asl check`, the lens) start only
  through `asl/tools/fleet/run.asl` with a timeout and a descendant limit, niced, one at a
  time, after waiting while the one-minute load is above 24 (at most 15 minutes).
- System prompt: the protocol, the tool list of the arm, and for ASL arms a 1.2 KB language
  primer (`asl/bench/loop/cards/asl.txt`); Python arms get one sentence. The primer is a
  placeholder for the measured cards of the card writer (`asl/bench/gen/cards`).
- Recorded per trial: solved and its three parts, stop reason (done, turns, tokens, budget,
  call), turns, tokens in and out per turn, distinct files read, bytes returned by read-type
  tools, the call sequence, cost, wall time. The full transcript stays in the work directory.

What the structural tools are, and how much of each is ASL:

| Tool | What it does | ASL-specific? |
|---|---|---|
| outline, symbol | item headers; one definition by name | no: the same 40 lines serve `fn` and `def` (ctags, `ast`) |
| replace | swap one whole definition, then run the checker | no; the checker verdict is as good as the checker (mypy --strict against `asl check`) |
| rename | whole-word rename over all files, then check | no (rope, sed -w) |
| lens | a definition plus the signature and effect of every symbol it uses, imported ones included | the facts are; pyright hover gives signatures one symbol at a time through an LSP session, there is no one-call CLI |
| card | package purpose, modules, exported signatures in 1.6 KB | the generator is ours; nothing equivalent ships with Python |
| check | whole-package static check | `asl check` is one binary with no environment; mypy needs the project configured, and neither sees `math.exp` overflow |

## 5. Pilot

Run: 3 tasks x 3 arms x `vcGlm53Flash` (served as `zai/glm-5.3-flash` through Vercel), n=1,
2026-11-13, rows in `asl/bench/loop/results/2026-11-13/pilot.asn`. Spend 0.103 USD of the 1.5
USD cap, counted from usage at 0.15 and 0.50 USD per million tokens. The tasks were picked so
that no B-only tool decides one (no rename task).

| Task | `py` | `aslA` | `aslB` |
|---|---|---|---|
| bugWilson | solved, 7 turns, 13 954 tokens | solved, 9 turns, 53 951 | solved, 6 turns, 15 716 |
| featureTrimmedMean | solved, 10 turns, 44 943 | not solved, 16 turns, 132 745 | not solved, 16 turns, 107 387 |
| paramResampleSize | solved, 16 turns, 49 737 | not solved, 16 turns, 84 224 | solved, 16 turns, 79 410 |

| Arm | Solved | Tokens, all trials | Tokens per solved trial | Output tokens | Mean turns | Bytes read | Cost USD |
|---|---|---|---|---|---|---|---|
| `py` | 3 of 3 | 108 634 | 36 211 | 5 331 | 11.0 | 20 286 | 0.018 |
| `aslA` | 1 of 3 | 270 920 | 270 920 | 21 623 | 13.6 | 38 956 | 0.048 |
| `aslB` | 2 of 3 | 202 513 | 101 256 | 18 153 | 12.6 | 36 408 | 0.037 |

n=1 on three tasks carries no interval and tests nothing; it shows the harness runs end to end
and where the first numbers point. They point **against** H-loop: Python solved all three for
about a third of the tokens of the better ASL arm.

What the transcripts show (work directory logs, read by the writer):

1. Both ASL failures on featureTrimmedMean are one defect: the model appended a correct
   function body and closed it with one parenthesis too many, as if `fn` were a form. The
   body of the `aslA` attempt is otherwise right. Neither arm ran the checker before turn 16;
   when `aslA` finally did, the diagnostic was exact (`src/describe.asl:135:104: parse
   unmatched ')'` with the fix form). This is the bare-header miss that decision DC-D1 of the
   ledger removes and that the miss-absorption branch would absorb; the writer of this unit
   made the same miss in 110 of the 132 functions of the runner and its test (found by the
   first `asl check`, removed mechanically; nothing else failed that check).
2. paramResampleSize: `aslA` changed the signature of resampleLoop! and missed its recursive
   call; it never ran the checker, and the grading run reported `ERR_ARITY resampleLoop!
   takes 6 argument(s), given 5` at the exact line. `aslB` did the same work through three
   `replace` calls, each of which returns the checker verdict, and was solved. This is the one
   place where a B tool was used, and the one place where `aslB` beat `aslA`. The strict
   checker pays only when the loop makes the agent run it.
3. On bugWilson `aslB` used no B tool (test, read, edit, test): its lower cost against `aslA`
   there is noise, mostly two `aslA` replies that hit the 3 000-token output cap.
4. ASL costs more to read and to think about: the same package is 9 685 source tokens in ASL
   against 7 737 in Python (o200k, 1.25x) and its tests 10 339 against 6 300 (1.64x), and the
   ASL arms spent 3.4 to 4 times the output tokens of the Python arm.
5. pytest prints the compared values of a failed assertion; `asl test` prints the assertion
   message only and stops at the first failure. The Python arm got the wrong Wilson bounds in
   its first result; the ASL arms had to read the test to learn what was expected.

Harness defects found by the pilot (row `LOOPBENCH-08`); the first two are fixed in the tree,
the rest are open, and the long run was **not** launched because of the third and fourth:

1. Fixed after the pilot: compile errors of ASL children carried a 190-character native test
   cache path per diagnostic into the tool result (`cleanOut` stripped only line-leading
   paths). Paid by the ASL arms only.
2. Fixed after the pilot: the protocol example showed one `<path>` tag, and the model wrote
   `<test>tests/x</test>` for the test tool, so its single-file test ran the whole suite.
3. Open, biased against ASL: `edit` and `write` in `aslB` do not validate. The real toolbelt
   checks balance and types on every staged edit; here only `replace` and `rename` do. Both
   featureTrimmedMean failures would have been caught on the turn that made them.
4. Open: a grading child that waits on the shared native CLI rebuild queue past its 180 s
   timeout would count as a red suite. It did not happen in the pilot (longest trial 277 s
   over 9 replies), but one `asl check` of this unit waited 33 minutes behind cold builds of
   six worktrees earlier in the session; an unattended run needs a timeout verdict that voids
   the trial instead of failing it.
5. Open: there is no append; `edit` refuses an empty `old`, and `write` replaces the file. The
   ASL arms lost 4 replies to this.
6. Open: a reply cut at the output cap holds no tool call and still costs a turn (4 replies).
7. Open: 5 of 9 trials stopped on the 16-reply limit, two of them solved; the limit is too
   tight for the two-file tasks, or `done` should be implied by a green suite.
8. Open: wall time includes the load wait and is not comparable between arms; trial lines
   reach the log only when the run ends (buffered stdout).

Off-assignment defects seen while building the runner, reported and not fixed: `asl check`
passes a `with` on a value whose schema it cannot name and `asl run` then fails with
`ERR_LOWER_UNSUPPORTED` (check and lowering disagree); a parse error in an imported module is
reported against the importing test file at `0:0`.

## 6. Full run plan and what would settle the claim

Rows `LOOPBENCH-01..09` in the ledger. The run that tests H-loop:

- 10 tasks x 4 arms x 2 models (`vcGlm53Flash`, `synDs41Flash`) x n=5: 400 trials. At the
  pilot's cost per trial this is inside 5 USD; Wilson 95 percent intervals per arm, paired by
  task and model.
- Confirmed when, on both models: `aslB` solves at least as many trials as `py` (lower Wilson
  bound of the difference at or above -5 points) and the tokens per solved trial of `aslB` are
  at most 0.8 of `py`.
- Refuted when `py` solves 10 points more than `aslB`, or `aslB` needs more tokens per solved
  trial than `py`, on both models.
- Not language-specific when `pyB` reaches the `aslB` figures: then the advantage is the
  tools, and the finding is "build the tools", not "use the language".
- The language itself helps when `aslA` solves at least as many as `py`; it hurts, and by how
  much, when it does not. That figure is the price of the missing prior on edit tasks and the
  target of miss absorption and the cards.
