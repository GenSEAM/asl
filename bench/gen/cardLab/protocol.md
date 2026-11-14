# Card lab: how instruction styles are compared

Status 2026-11-13: screening only. Nothing here is a confirmed result; numbers live in
`screening.asn` and `results/*.asn` and are quoted with their n. The screening run was
stopped at 67 of 120 trials because replies were being recorded against the wrong task
(`screening.asn`, defect crossWiredReplies).

## 1. The claim under test

Principal's thesis: concise ASN-style instructions raise a model's effective intelligence
(less bias, inattention and hallucination), and token efficiency is the goal. It splits
into three claims that need separate evidence:

| Claim | What would show it | Where |
|---|---|---|
| T1. A short card can replace the 799-token card for writing ASL | raw pass of a card of 450 tokens or fewer is not below the `asl` arm, same tasks and model | section 2 |
| T2. The ASN row form itself helps, beyond being short | `aslCardAsn` beats cards of the same budget and content in prose and contrast form | sections 2 and 4 |
| T3. ASL reads at least as clearly as Python at fewer tokens | reading accuracy per 1000 program tokens, ASL against Python and TypeScript | section 3 |

T2 is the thesis proper. T1 only says the card was too long, and T3 is about the language,
not about instructions.

## 2. Writing: card arms

Language, tasks, grader and scoring are the `asl` arm of `asl/EXPERIMENT.md` unchanged
(bracket surface, bare `fn` header, 30 tasks, `bin/asl check` then `bin/asl test`, heal
pass). Only the system prompt differs.

| Arm | Style | o200k tokens |
|---|---|---|
| `asl` (existing) | prose, the section "The language" of `llms.txt` | 799 |
| `aslCardAsn` | ASN rows `(:rule :id .. :do .. :ex ..)`, examples as forms | 448 |
| `aslCardContrast` | "you know Python", 11 contrast pairs `py -> asl` | 449 |
| `aslCardExample` | two complete programs and 6 one-line pitfalls | 446 |
| `aslCardMin` | one function and 5 pitfalls | 150 |

Content is failure-driven: `misses.asn` counts the miss classes of the first pilots
(bare body 52, `==` 29, reasoning to the token limit 24, unbalanced parentheses 16,
`listAppend` with a scalar 14, foreign builtin names 13, `listTail` as a list 13, `%` 11),
and each card orders its content by that table. Every example in every card is executed by
`examplesTest.asl` (51 assertions).

Measures, per arm and model:

- **raw pass@1**, **healed pass@1**, **solved** within 4 calls, as in EXPERIMENT.md section 7.
- **tokens-to-green**: prompt plus completion over the calls of a solved trial, median.
- **tokens per solved task**: all tokens of the arm divided by solved trials, with the card
  counted and with the card excluded.
- **card cost amortised over a session**: with prompt caching a card of C tokens read in N
  calls costs `C * (w + (N - 1) * r)` input-token equivalents, where w is the cache-write
  factor and r the cache-read factor of the provider (for example 1.25 and 0.1). Per call
  that is `C * (w + (N - 1) * r) / N`; for the 799-token card and N = 20 it is about 126,
  for a 450-token card 71, for 150 tokens 24. A repair turn costs a whole completion (the
  pilots show 600 to 8000 output tokens per failed turn), so a card pays for itself if it
  removes one repair turn in several tasks. The comparison therefore reports cost at N = 1
  (no cache) and N = 20.

Decision rule for the screening (n = 1 per task, 30 trials per arm): it can only discard.
An arm whose raw pass is below `asl` by more than 20 points is dropped; the others go to a
confirmation run at n = 5 on two models, scored by bootstrap over tasks as in
EXPERIMENT.md. With 30 trials a 95% interval is about plus or minus 17 points, so no
ranking among the survivors is claimed.

Harness defect found while screening (2026-11-13): when the shared native CLI is being
rebuilt, `bin/asl check` of a candidate waits past the grader's time limit and the runner
records a correct program as stage `check`, four times in a row (about 200 s per trial).
Rows of the running pilots are affected as well. `regrade.asl` therefore regrades the first
reply of every row; raw pass is quoted from the regrade, and solved and tokens-to-green of
affected rows are not usable until those trials are rerun.

Known weaknesses, stated before the numbers:

1. **In-sample.** The cards were written from failures on these same 30 tasks. They name
   builtins those tasks need. A confirmation needs tasks the card author has not seen;
   until then a gain is an upper bound.
2. **Style and content are confounded.** The four cards do not carry identical facts
   (the ASN card has 13 rules, the min card 5). Only section 4 separates form from content.
3. **One cheap model.** `vcGlm53Flash` only.
4. **ASN rows cost tokens.** The same facts cost more in rows than in prose: `(:rule :id x
   :do "..." :ex ...)` spends about 9 tokens of frame per rule, 13 rules about 120 of 448.
   The first draft of the ASN card was 735 tokens against 667 for the contrast card with
   more content. "Concise" has to be measured, not assumed from the look.

## 3. Reading: `readProbe.asl`

The clarity claim is about reading, and the writing data cannot answer it. The probe uses
the 30 reference programs, which exist in all three languages and pass the same cases.

- **Predict.** Given only the program and the two visible examples as notation, state the
  result of two graded cases (the first two that do not fail). Score: exact match after
  removing spaces and unifying quotes; 60 values per arm.
- **Bug.** A single-token mutant, the same class in the three languages (first class of
  `lt gt le ge eq plus minus times and or zero one true` whose pattern occurs in all three
  references), kept only if all three mutants compile and fail a graded case. The model
  names the wrong line and gives the corrected line. Score: line number right, and the
  program with that line replaced passes the graded cases (so any correct fix counts).
- Arms: `py`, `ts`, `aslCard` (system prompt: the shortest card that survives screening),
  `aslNoCard` (system prompt "The program is written in ASL.").
- **Density**: o200k tokens of the program text. On the 30 references: ASL 2833, Python
  2384, TypeScript 2624 (tiktoken 0.12.0, stripped file text, 2026-11-13), so ASL is 1.19
  times Python and 1.08 times TypeScript before any model is asked.
- Reported: accuracy on both parts, program tokens, output tokens, and correct answers per
  1000 program tokens. ASL "reads as clearly at fewer tokens" only if its accuracy is not
  lower and its density figure is; the density half is already false on these programs.

Items: `readItems.asn`, built by `readProbe.asl gen` on 2026-11-13. 14 of the 30 tasks
received a mutant (eq 4, plus 3, times 2, lt gt le ge zero 1 each); for the other 16 no
class occurs in all three references with all three mutants failing, so the bug part has 14
items per arm and the predict part 60.

Limits: the references are idiomatic per language, so they are not line-for-line
equivalent (ASL uses `listMax`, Python a loop or `max`); the mutated site is the first
occurrence of the pattern in each text, so the three mutants share a class, not a place;
one model, n = 1.

## 4. Beyond code: three probes of the thesis proper (not run)

The thesis says the row form itself changes what a model does with an instruction. That
needs the same content in three renderings with equal token budgets: ASN rows, prose
sentences, markdown bullets. Budget parity is enforced by count (o200k, within 3%), padding
the cheapest rendering with neutral filler rows, never by cutting content. Each probe runs
on the pilot runner (system prompt = instruction set, one user turn, exact-match scoring),
30 items, n = 5, two models.

```
(:probe :id distraction :thesis "rows keep an instruction in force while the task pulls elsewhere"
  :content "12 output constraints (answer language, forbidden words, required closing token, maximum sentences, numeric format, ...)"
  :renderings (asnRows prose mdBullets) :budget "equal o200k, within 3 percent"
  :task "a user turn of 400 to 600 tokens asks an unrelated question and carries 2 embedded counter-instructions (for example 'ignore the format above')"
  :score "per constraint: kept or broken, by regex; primary = share of the 12 kept; secondary = share of trials that follow a counter-instruction"
  :support "asnRows keeps at least 5 points more constraints than both other renderings, interval excluding 0, on both models"
  :refute "difference inside plus or minus 3 points, or either other rendering ahead")
(:probe :id retention :thesis "rows survive a long context"
  :content "8 rules given once in the system prompt, each with an id"
  :renderings (asnRows prose mdBullets) :budget "equal o200k, within 3 percent"
  :task "filler dialogue of 2000, 8000 and 24000 tokens between the rules and a final request that triggers exactly 3 of the 8 rules; the triggered rules rotate so position in the list is balanced"
  :score "triggered rules applied (0 to 3); untriggered rules wrongly applied; slope of accuracy against filler length"
  :support "asnRows loses fewer points from 2000 to 24000 than both other renderings on both models"
  :refute "equal slopes, or rows better only at 2000")
(:probe :id absentFacts :thesis "rows make it plainer what was not said, so the model invents less"
  :content "a fact sheet of 20 facts about a made-up product (names, limits, dates)"
  :renderings (asnRows prose mdBullets) :budget "equal o200k, within 3 percent"
  :task "30 questions: 15 answerable from one fact, 15 about a field the sheet does not hold; instruction: answer from the sheet or reply ABSENT"
  :score "answerable: exact value; absent: ABSENT; primary = hallucination rate on the 15 absent questions at matched answerable accuracy"
  :support "asnRows hallucination rate lower by at least 10 points than both other renderings with answerable accuracy not lower"
  :refute "no difference, or lower hallucination bought by answering ABSENT to answerable questions")
```

Common controls: the three renderings are generated from one source list so the facts
cannot drift; item order is shuffled per repetition with a recorded seed; a fourth
rendering, the ASN rows with ids and keys replaced by neutral ones (`:a :b`), separates
"structure" from "meaningful keywords". The thesis is supported only if at least two of the
three probes meet `:support` on both models; one probe alone is a property of that task.
