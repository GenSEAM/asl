# Agent approach: toolbelt, critical packages, working doctrine

Date 2026-11-13, measured on `d29e73aea` to `f44cc771f` (main moved twice during the run).
Ledger with every figure, the per-package rows and the backlog rows `AGENTEFF-01..19`:
`.asl/mem/audits/fable-20261113/agentEfficiency.asn`.

Not repeated here, only referenced: Leon run failures and `LEONFIX` rows (`leonFailures.asn`),
library glue and `EXTERN` rows (`glue.asn`, `asl/doc/externDesign.md`), the type lens and `INFER`
rows (`inference.asn`, `asl/doc/inferenceDesign.md`), intel and observe defects `VZ-03..07`
(`visualization.asn`), the package cycle (`layering.asn`).

Method: tiktoken 0.12.0 `o200k_base`; "in" is the command text, "out" is stdout plus stderr; one
run per task; staged edits ran in their own session and were discarded. Single samples, load 10
to 110, so latencies are upper bounds.

## 1. Toolbelt benchmark

Ten fixed tasks, plain tools (grep, sed, cat, `./bin/asl check|test`) against agent-plane forms.
Tokens are in+out; steps are tool calls.

| # | Task | Plain | Forms | Winner | Why the loser lost |
|---|------|-------|-------|--------|--------------------|
| 1 | locate a definition | 1 step, 60 | 1 step, 193 | plain | `(:query)` adds hit excerpts and a text count; no line number |
| 2 | list callers | 1 step, 386, unlabelled | 1 step, 554, exact with decoys | plain on tokens, forms on exactness | 67-token `:limits` sentence in every receipt. `(:intel :op impact)` is 160 tokens and wrong (VZ-04) |
| 3 | read one function | 2 steps, 529 (cat: 891) | 1 step, 480 | forms | escaping adds 27 percent over the raw text |
| 4 | 2-line edit that must check | 3 steps, 210 | 1 step, 315 | forms on steps | 49 tokens per accepted edit; one checker run per edit |
| 5 | what a module exports | 1 step, 253 | 1 step, 4940 | plain | outline lists all 154 items; 73 of 140 signatures cut at a nested paren |
| 6 | builtin signature | 2 steps, 228 | 1 step, 68 | forms | grep needs to know where signatures live |
| 7 | run one test | 1 step, 40 | 1 step, 103 | plain | the verdict is printed twice |
| 8 | why a check fails | 1 step, 123 | 1 step, 270 | plain | the batch runs on after the rejected write |
| 9 | rename in 8 files | 3 steps, 307, 6 s | 3 steps, 2525, 145 s | plain | no rename op; edits checked one by one, so callers-first is rejected (6 of 8) |
| 10 | what a package is for | 1 step, 2577 | 1 step, 535 | forms | manifest and README are a slogan and a list |

Totals: plain 16 steps and 4713 tokens. Forms as an agent first tries them: 12 steps and 12804
tokens, 2.7 times plain. Forms with the right op each time (`:read :limit` for tasks 5 and 10,
definition first for task 9): 11 steps and 3789 tokens, a third fewer steps and a fifth fewer
tokens than plain. The gap between the two form figures is what the backlog rows close.

Latency: read-only forms 0.1 to 0.8 s; callers 2.2 s; check 0.06 s for a leaf file, 1.2 to
1.9 s warm and 16.4 s cold for a file with 69 modules behind it; one test file 0.3 to 1.4 s.
After a commit on main every `asl` command waits for the native CLI rebuild: one check was
killed after 300 s of waiting, peer commands had waited 5 to 11 minutes, and the wait prints a
23-token line every 30 s with a default budget of 3600 s.

Error shapes (seven rejections probed). Fixable in one turn: `ERR_SYMBOL_NOT_FOUND` (file
outline with ranges and `:nearest`, 132 tokens) and `ERR_UNREPAIRABLE` (line, col, three
options, a `:pick` key, 182 tokens). Not fixable in one turn: an unknown symbol (no `:nearest`
although the right name is one letter away; code and defect each printed twice), a type
mismatch (two diagnostics for one defect, no candidate), `ERR_NO_MATCH` (no closest line), and
any step that follows a rejected step in a batch (a later `(:check)` reads the disk and says
valid).

## 2. Critical packages

| Package | Source | Verdict | Three worst problems |
|---------|--------|---------|----------------------|
| asl-forms | 24 files, 13.5k lines, 222k tokens | keep, shrink | fat receipts; per-edit check makes multi-file edits order-dependent; one 31-op registry for every plane, with web search and lens inside the kernel |
| asl-intel | 33 files, 4.9k lines, 89k tokens | shrink to outline, coupling, deadcode on one index; freeze the rest | wrong answers that look right (impact, trace, outline signatures); unbounded output; a second symbol engine beside the exact `observe` one |
| asl-gateway | 51 files, 31.3k lines, 489k tokens | keep the routing core (52 percent), split the rest | files no agent can hold (config 3389 lines); reasoning cap not enforced at the call; half the package is web research, pacing and its own CLI |
| asl-agent (Leon) | 46 files, 26.1k lines, 415k tokens | freeze features; shrink after the `LEON-BAR-20` measurement | the loop loses runs (33 of 180 ok); provider tables, pools and git-word parsing live in Leon; it asks the model for evidence the harness can produce |
| asl-agent-core, asl-agent-bus | 41 files, 2.4k lines | freeze | not imported by Leon; two different `AgentMessage` schemas; 589 exports |
| asl-harness | 2 files, 2.0k lines | keep, shrink | one 90 KB file; its own ASN reader |
| harness/ | 115 files, 7.1k lines, 211k tokens | freeze, split | advertised adapters have no caller; 1318 exports; 454 result files tracked beside code |

Responsibility, public surface, users, test evidence and the glue-or-owned split for each are in
the ledger `(:package ...)` rows.

What Leon minimally needs (estimate from module headers, not from reading 57k lines): six parts
of about 300 KB together, 22 percent of today's 1.39 MB.

| Part | Does | Today | Target |
|------|------|-------|--------|
| turn | stable prefix plus appended turns, one gateway chat call, reply parsed into forms | 126 KB | 60 KB |
| context | prefix, turn-1 pre-read pack, compaction | 109 KB | 40 KB |
| dispatch | forms run in-process by asl-forms, owns enforced by the txn | 162 KB | 40 KB |
| gates | run the gate, red before, verdict | 45 KB | 30 KB |
| receipts | journal row per turn, usage, diff | 62 KB | 40 KB |
| loop | budget ladder, stop reasons, CLI, config | 313 KB | 90 KB |

Accretion by placement, 547 KB or 39 percent of Leon: provider knowledge (92 KB), seven pool and
serve modules (84 KB), git command parsing as a write policy (112 KB), claim and evidence
policing (164 KB), a second CLI (44 KB), eleven small speculative modules (51 KB). In the
gateway the routing core is about 0.87 MB; web research and scraping (0.32 MB), subscription
pacing and learning (0.18 MB) and the CLI (0.08 MB) are separable.

Glue instead of owned code: model calls, retries, reasoning caps and concurrency belong to the
gateway; write confinement to an operating-system sandbox; red-before, commit and assert counts
to the harness; names, imports and exports to the checker's own resolution; HTTP, dates and
entity tables to libraries (see `externDesign.md`). Owned, because nothing outside offers it:
staging and txn, delimiter repair, the checker bridge, the turn protocol, alias routing and
subscription CLI sessions.

## 3. Doctrine

Every number is a ceiling a test can check. Values are proposals until adopted.

1. **Reading unit.** Read down a ladder and stop at the first rung that answers: card index
   (about 500 tokens), package card (500), module header with exports (250), one symbol (16
   tokens a line), a slice of at most 60 lines. A whole file only under 100 lines.
2. **Receipt budget.** Payload plus at most 40 tokens. An accepted mutation answers in at most
   15. A list answers 400 by default with `:more`. No op returns over 4096 bytes without an
   explicit `:limit`. Nothing stated twice, no sentence that `(:help)` could hold.
3. **Card.** Before the task an agent gets a language card of at most 800 tokens, a tool card of
   at most 400 listing only the ops of its run kind, and a protocol of at most 300, all
   byte-stable so they cache. Task row plus pre-read anchors: at most 1500. Turn 1 under 3000.
   The 799 tokens of the ASL card against 17 for Python are the price of a language with no
   priors; they are paid once per cached prefix, so the lever is cache stability, not a shorter
   card.
4. **Errors.** An error is repairable in the next turn or it is a tool defect: code,
   `path:line:col`, the offending text, expected against found, and `:nearest` names or a `:fix`
   form to send back. One diagnostic per defect, three at most, 120 tokens. A rejected step
   stops the steps that depend on it.
5. **Forms or native tools.** A form when the answer needs the parser or the staged state:
   symbol read, builtin signature, exact callers, edit with check in one call, test verdict as
   data. Native tools when the question is text: where a name is defined, a module's export
   header, plain search, a file under 100 lines, a rename until `(:rename)` exists.
6. **Gate loop.** Check after every edit (2 s warm, 20 s cold), one named test file after the
   change (60 s warm), the merge train once per batch. Never a whole-tree suite inside a turn.
   A gate proves the change by going red without it.
7. **Availability.** No agent call waits on a rebuild: read-only forms answer from the last
   built CLI and name its rev; check and test wait 30 s at most, then answer one line.
8. **Sandbox defaults.** Edits stage and a flush is explicit; writes only inside `:owns`; one
   session buffer per agent; no network in a write unit; children only through
   `tools/fleet/run` with a timeout; no push, no remote, no delete outside owns; confinement by
   the operating system, not by parsing command words.
9. **One toolbelt.** `asl/grammar/tools.asn` is the only source. `(:tools)` and
   `(:tools :kit write)` print it; the `asl-toolbelt` skill and the CLAUDE.md tools rule are
   rendered from it for Claude Code and Codex, which call the CLI through the shell (no MCP, by
   decision); Leon's tool card is rendered from the same rows and Leon calls asl-forms
   in-process. Same receipts for everyone, so the ten tasks above are one regression gate.
10. **Glue first.** Before a package grows, name what an existing tool, a library or the calling
    agent already does. Own only what is specific to ASL.

## 4. Think in ASN, transpile out

Direction only, priority p3; both targets are frozen today.

Where it stands: ASL code costs 1.3 to 1.8 times typed Python in tokens and keyed ASN is 9 to 17
percent worse than minified JSON (`language.asn`), so a token gain is not supported by
measurement. The testable claim is fewer repair turns because the check is strict. The py and js
targets pass 12 byte-equal fixtures each and `(:target :name py|js)` exists.

| Stage | Row | What | Decision rule |
|-------|-----|------|---------------|
| 1 | AGENTEFF-17 | generation-bench arms `aslToPy` and `aslToJs`: the model writes ASL, the target lowers it, the Python and TypeScript hidden tests judge it | continue only if the pass rate of the direct arm is reached at 1.0 times its tokens to green or less |
| 2 | AGENTEFF-18 | portable subset as a checker mode (pure functions, schema, enum, list, map and string builtins, print); targets unfrozen for the subset only | 12 fixtures per target stay byte-equal |
| 3 | AGENTEFF-19 | ASN as plan and hand-off form: A/B against Markdown and minified JSON on the 20 replay units of `LEON-BAR-20` | tokens per accepted unit and accept rate |

## 5. Backlog

Ranked by tokens and turns saved; full rows with gates and owns are in the ledger. The backlog
is at its cap of 170, so the rows wait there until the planner trades them in. "Cheap" marks a
row a cheap model can do through Leon once it is rewritten to the row template of
`leonFailures.asn`.

| Row | Prio | Fix | Measured target |
|-----|------|-----|-----------------|
| AGENTEFF-01 | p0 | receipt diet for edit, write, test, check, query; skip steps after a rejection | task 1: 174 to 50; task 4: 185 to 75; task 7: 79 to 25 |
| AGENTEFF-02 | p0 | outline: exported only, one compact row per name, whole signatures (cheap) | task 5: 4914 to 450; 73 signatures corrected |
| AGENTEFF-03 | p0 | no call waits on a rebuild (widens FABLE-VIZ-06) | over 300 s per call after each commit |
| AGENTEFF-04 | p1 | multi-file edits checked once as a set; `(:rename)` | task 9: 2525 tokens and 145 s to 300 tokens |
| AGENTEFF-05 | p1 | errors with `:nearest`, one diagnostic per defect, closest line on no-match | one turn per rejected edit |
| AGENTEFF-06 | p1 | `(:tools :kit write)`; skill and Leon card rendered from one source | 1168 to 400 per session |
| AGENTEFF-07 | p1 | read: 80-line default, raw mode, `(:read :card P)` (cheap) | task 10 first try: 3331 to 506 |
| AGENTEFF-08 | p1 | the ten tasks as a token ratchet gate | keeps 01 to 07 from regressing |
| AGENTEFF-09 | p1 | impact answers from the observe caller graph | a wrong answer removed |
| AGENTEFF-10 | p1 | skill gains the forms-or-native table (cheap) | 67 tokens per callers receipt |
| AGENTEFF-11..16 | p2 | providers out of Leon; jail instead of command parsing; web research out of the gateway; no file over 800 lines; freeze core, bus and harness adapters (cheap); reasoning cap at the gateway | sizes in the ledger |
| AGENTEFF-17..19 | p3 | think in ASN, stages 1 to 3 | section 4 |
