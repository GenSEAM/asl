# RESEARCH_REPORT.md — Viability and Design Research for AgentS

Companion to [`SPEC_REVIEW.md`](SPEC_REVIEW.md). Where the review asked *"is this specification
complete?"*, this asks *"should this be built, and in what shape?"*

---

## 0. Provenance — read this before trusting anything below

Two deep-research runs were attempted. **Both had their adversarial verification stage destroyed
by session quota**, and the automated synthesis step never ran. What follows is my own synthesis
over the raw claim set, with evidence tiers marked on every load-bearing statement.

| Run | Agents done | Verification | Outcome |
|---|---|---|---|
| 1 (`wlesbzoab`) | 30/105 | 0/75 verifiers ran | 24 sources → 120 claims → 25 selected, all unverified |
| 2 (`wrswni1fh`) | 39/105 | 4/70 verifiers ran | 2 confirmed, 2 refuted, 21 unverified; synthesis died |

**The surviving verification is itself unreliable.** Both claims the panel marked REFUTED (0-2)
are directly supported by verbatim quotes I then pulled from the source myself (§4.1). That is a
100% false-negative rate on the only refutations produced. Treat panel verdicts from run 2 as
noise in both directions.

Evidence tiers used throughout:

* **[VERIFIED]** — I fetched the primary source in this session and read the figure or quote.
* **[PANEL]** — 3-0 confirmed by run 2's verifiers. Weak, given the false-negative rate above.
* **[UNVERIFIED]** — extracted by a fetch agent, never checked. **The majority of claims below.**
* **[BLOCKED]** — I tried to verify and could not reach the source.

---

## 1. Verdict

**Narrow it, and re-found the value proposition.** Not "build as specified", not "abandon".

The spec's implicit bet is that a clean, regular S-expression syntax makes LLM code generation
more reliable, and that this reliability justifies a DSL sitting between the model and four native
targets. The research attacks that bet from three directions and supports it from one — but the
three attacks are on the load-bearing premises and the support is on a secondary one.

**What the evidence undermines:**

1. **"Our syntax is easier for LLMs" is unsupported and probably backwards.** No source found
   tests S-expressions at all. What is measured is that generation quality tracks training-corpus
   presence, and a brand-new DSL is by construction zero-corpus. `[UNVERIFIED]`
2. **"Guaranteed syntactic validity" is commodity.** llguidance does arbitrary CFGs via Earley at
   ~50 µs/token and already ships inside llama.cpp, vLLM, SGLang, and mistral.rs. Anyone can have
   balanced parens for any grammar. `[UNVERIFIED]`
3. **Syntax is the wrong target regardless.** Reportedly ~6% of compilation errors in
   LLM-generated TypeScript are syntactic and ~94% are type errors. `[BLOCKED — see §5]`

**What survives, and should become the actual pitch:** the *type* layer, and the *ordering*
discipline in §3.3. Not the parentheses.

---

## 2. Part 1 — Viability

### 2.1 The zero-corpus problem is the central risk

The DSL survey's diagnosis of why LLMs fail on DSLs is **absence of training data for the DSL's
syntax and semantics — not syntactic complexity of the host language**. If that holds, AgentS's
core design move (choose a simpler, more regular syntax) targets a cause that isn't the cause.
`[UNVERIFIED — arXiv 2410.03981]`

Corroborating, all unverified: MultiPL-E finds generation accuracy correlates with language
popularity as a proxy for corpus volume, though imperfectly — some niche languages match popular
ones, so low-resource status is a strong prior, not a death sentence. Reported compile-error rates
for low-resource targets run 40–60% for OCaml/Haskell and 18–39% for hard Rust.

**This is the single most important thing to measure before writing a compiler.** MultiPL-E's
methodology is directly reusable: mechanically translate HumanEval/MBPP plus tests and signatures
into AgentS and measure generation reliability against TypeScript/Python/Go/Rust baselines. That
experiment is cheap relative to a four-backend compiler and it either validates or kills the
premise. **Do it first.** `[UNVERIFIED — nuprl.github.io/MultiPL-E]`

### 2.2 Syntactic validity is commoditized

llguidance implements general CFG-constrained decoding (Earley over a derivative-based regex
lexer), authored in a Lark-format variant, at ~50 µs per token mask on a 128k tokenizer with
negligible startup — already integrated across the mainstream inference stacks. Constrained
generation reportedly drives syntax errors to 0% versus 10% unconstrained. `[UNVERIFIED]`

Consequence: **"LLMs emit our syntax with fewer errors" cannot be the pitch.** Any grammar gets
this from the decoder.

One genuine gap does remain: provider-native structured output has the *lowest* schema coverage of
any engine tested while achieving 92–100% compliance on what it does support. Closed APIs cannot
express arbitrary custom grammars. `[UNVERIFIED]`

### 2.3 The envelope-vs-payload lesson

Aider's benchmark (133 Exercism exercises, 5 runs, four models) reports every model scoring *worse*
when returning code inside JSON than as markdown fences, with character-level escaping identified
as a mechanism, and OpenAI's strict mode giving no measurable improvement. Notably the penalty
exceeded what syntax-error counts explain, attributed to formatting burden consuming reasoning
capacity. `[UNVERIFIED — aider.chat]`

For AgentS this cuts both ways, and the spec should claim the favorable half explicitly: an
S-expression DSL emitted as **raw text** avoids the escaping tax entirely, while one emitted
inside a JSON field inherits all of it. But the same source warns that any unfamiliar output
format may impose a non-syntactic reasoning tax even when it parses cleanly — which is 2.1 again.

---

## 3. The contradiction, and its resolution

Two sources flatly disagree, on the same benchmark. The verification pass that should have
adjudicated this is exactly what died, so I resolved it by reading the primary source.

| Source | Claim | GSM8K |
|---|---|---|
| arXiv 2408.02442 | Format restriction **degrades** reasoning | GPT-3.5: 75.99% → 49.25% |
| arXiv 2501.10868v3 | Constrained decoding **improves** reasoning | 80.1% → 83.8% |

### 3.1 What the primary source actually says `[VERIFIED]`

I fetched the full text of 2408.02442. Table 1, GPT-3.5-turbo on GSM8K:

* **Natural language: 75.99%** (±3.1)
* **JSON format-restricting instructions: 74.70%** (±1.1)
* **JSON-mode (constrained decoding): 49.25%** (±12.0)

Strictness ranking, most to least harmful: JSON-mode → format-restricting instructions →
NL-then-convert. And on surface syntax:

> "On hint sight we do not see any structure format which consistency stands out from others
> which generalized across all models."

*(sic — quoted verbatim.)* **No format wins consistently. S-expressions were not tested by anyone.**

### 3.2 The mechanism `[VERIFIED]`

> "100% of GPT 3.5 Turbo JSON-mode responses placed the 'answer' key before the 'reason' key,
> resulting in zero-shot direct answering instead of zero-shot chain-of-thought reasoning."

**That resolves the contradiction.** The damage is not from constraint per se — restricting by
*instruction* cost only 1.3 points (75.99 → 74.70). The damage is from a grammar that **commits
the answer before the reasoning**, converting chain-of-thought into direct answering. Where a
grammar permits or forces reasoning first, constrained decoding is neutral-to-helpful, which is
what 2501.10868 measured.

### 3.3 The actionable design principle — and an actual argument for S-expressions

> **A grammar must force reasoning-bearing tokens to precede committed results.**

This is the one place where AgentS's syntax choice has a *defensible* advantage the spec never
claimed. In a Lisp, a function body is a sequence whose value is its tail expression: `let`
bindings, intermediate computation, and comments naturally precede the returned value. A grammar
built on that shape structurally puts derivation before result — the opposite of a JSON schema
whose key order can commit an answer first.

**Make this the explicit design rationale.** It is evidence-backed, it is specific to
S-expressions, and it survives the commoditization argument in §2.2 — because it is a claim about
*grammar shape*, not about parser convenience. Every other syntax argument in the spec should be
dropped in its favor.

---

## 4. Part 2 — The architecture fork

### 4.1 What BAML actually did `[VERIFIED — I re-fetched after the panel refuted it]`

The shared-runtime architecture is real and its economics are now concrete:

* **Shared core, not transpilation** `[PANEL 3-0, and consistent with my fetch]`: all bridges sit
  on one Rust library behind a single C FFI header (`baml_cffi.h`), with Protocol Buffers
  (`baml_inbound.proto` / `baml_outbound.proto`) as the cross-boundary format.
* **Fixed cost:** "It took me 2 months to design and implement all of this for Python and
  Typescript."
* **Marginal cost:** "Six of these language bridges - C++, C#, Go, Java, Rust, and Swift - were
  each built by 1 engineer, on our team, over the course of a single week."
* **On conformance:** "listing out test cases is insufficient to steer an agent to the correct
  implementation" — they invested in reference documents describing recursively correct
  implementations instead.

**The panel refuted the last two of these 0-2. The source states them nearly verbatim.** This is
why §0 says the surviving verification is untrustworthy.

**One caveat the raw claim missed:** this blog is about agent-built software with human operators.
"1 engineer, one week" means *one engineer directing coding agents*, not one engineer hand-writing
a binding. The economics are real but they are agent-assisted economics.

### 4.2 Recommendation: shared runtime, and it is not close

Roughly 2 engineer-months of fixed cost buys a substrate on which each additional language is
about an engineer-week. AgentS's stated design — four independent native backends — pays the
per-target cost *every time*, and pays it in the hardest possible currency:

* every backend needs its own semantic-equivalence guarantees (§6 of the review: A1 mangling,
  A2 wire casing, A3 numeric widths);
* the Rust backend needs an ownership model that does not exist (B6), and BAML — a Rust shop —
  notably ships a Rust *binding*, not a Rust code generator;
* async coloring (G8) must be solved four times, once per concurrency model.

A shared runtime collapses all four into one implementation plus thin bindings. The cost is the
"native output" promise in §1 of the spec, which should be dropped rather than defended.

**Caveat, stated plainly:** `defui` does not fit this architecture. React and Vue components must
be real generated source in the user's build, not FFI calls into a Rust runtime. If `defui`
survives at all it is a separate code generator with separate economics — which is an argument for
cutting it from v1 (§6).

---

## 5. What I could not verify — and why it matters most

**The single most load-bearing source for the verdict is [BLOCKED].** OpenReview
`DNAapYMXkc` returns a bot-verification screen. Its claims, all **[UNVERIFIED]**:

* ~6% of compilation errors syntactic, ~94% type-check failures (six open-weight LLMs, TypeScript)
* idealized syntax-only constraint removes **9.0%/4.8%** of compile errors on HumanEval/MBPP,
  versus **74.8%/56.0%** for type-constrained decoding
* type systems cannot in general be captured by context-free grammars, so no GBNF/outlines/
  XGrammar-class tool reaches this; the authors built a prefix automaton plus type-inhabitation
  search — an incremental type checker over partial programs
* 40–60% compile-error rates for OCaml/Haskell, 18–39% for Rust

**If these hold, they are the most important findings in this report** — they say the entire
grammar strategy buys roughly a tenth of what a type-aware completion engine does, and they
relocate AgentS's defensible value from syntax to types. **They also directly downgrade my earlier
recommendation in `SPEC_REVIEW.md` §11.4 to ship a GBNF grammar.** That advice is not wrong, but I
weighted it far too heavily; a grammar is table stakes, and the leverage is in the type layer.

**Verify these before acting on them.** One paper, one unreachable source, carrying the verdict.

Also unverified and worth checking: the DSL survey (arXiv 2410.03981), all MultiPL-E claims, the
Aider benchmark, and arXiv 2606.06923 on declarative orchestration — whose claims are notable
because they report the winning "declarative" representation being **plain Markdown in the system
prompt, not a typed DSL**, with the advantage shrinking as models get stronger and collapsing
entirely under realistic (non-golden) retrieval.

---

## 6. Recommendations

1. **Run the MultiPL-E experiment before writing any compiler.** Translate a HumanEval subset into
   AgentS, measure generation reliability against TS/Python/Go/Rust. This premise is currently
   assumed, cheap to test, and load-bearing for everything else.
2. **Re-found the pitch on types, not parentheses.** Syntactic validity is commodity (§2.2) and
   reportedly ~6% of the error surface (§5). A typed IR with an incremental checker over partial
   programs is the defensible artifact.
3. **Adopt the ordering principle as explicit design rationale** (§3.3) — the one evidence-backed
   argument specific to S-expressions. Drop the other syntax arguments.
4. **Pivot to a shared runtime with thin bindings** (§4.2). Drop "native transpilation" from §1 of
   the spec.
5. **Cut `defui` from v1.** It does not fit the runtime architecture, and §5 of the review found it
   the least specified area after `defagent`.
6. **Ship the grammar anyway** — it is cheap and llguidance takes Lark-format directly — but budget
   it as table stakes, not differentiation.
7. **Verify §5's source before committing to 2.** The verdict currently rests on an unreachable paper.

Design resolutions for review items (a) ownership/Rust, (c) async coloring, and (d) agent/tool
semantics were **not reached** — those search angles' claims died with the verification stage. If
recommendation 4 is adopted, (a) and (c) largely dissolve: a shared Rust runtime means writing
that code once, by hand, rather than generating it four times.
