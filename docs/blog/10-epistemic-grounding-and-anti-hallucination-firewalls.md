# Stop Your Agent from Faking Green Tests: Closure Checks and Anti-Hallucination Firewalls
*By GenSEAM | September 2026*

Prompt engineering is an inadequate defense against autonomous agent failure.

In many agent architectures, developers try to enforce safety and accuracy by adding negative constraints to the system prompt:
```text
"Never invent API endpoints. Always cite sources accurately.
Do not hallucinate parameters. Never touch directories outside /workspace."
```

Under real conditions (long prompts, several subagents exchanging intermediate data, context decay), these natural language guardrails erode. The model starts calling functions that do not exist, citing file paths that were never created, and reporting tests as passing when they never ran.

To run agents on real infrastructure, safety cannot be advice written in prose. It has to be a **boundary enforced by the checker and the tool layer**.

---

## 1. The Epistemic Gap in Agent Swarms

Large language models are probabilistic token predictors, not deductive truth engines. When an agent writes code or changes a system, it works across an **Epistemic Gap**:

1. **Fabricated Identifiers:** The model recalls a name that resembles the project's conventions, or a builtin from another language, and calls a function that was never implemented.
2. **Citation Drift:** Summarizing retrieved documentation, an agent quietly changes a unit (milliseconds read as seconds) or attributes a claim to the wrong source.
3. **Escaped Capability Boundaries:** An agent asked to inspect a log decides to search the whole disk or install packages, changing the host without authorization.
4. **Fake Greens:** A test that asserts nothing, or returns false after a trivial assertion, is reported as a pass.

```text
                                  Agent Generation
                                         │
                                         ▼
                 ┌───────────────────────────────────────────────┐
                 │          Epistemic Grounding Firewall         │
                 └───────────────────────┬───────────────────────┘
                                         │
                 ┌───────────────────────┼───────────────────────┐
                 │                       │                       │
                 ▼                       ▼                       ▼
      ┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐
      │ Factual Grounding   │ │  Closure Checker    │ │  Path Jail          │
      │ - Exact Quote Match │ │ - Symbol Existence  │ │ - Workspace Root    │
      │ - Source Lookup     │ │ - Arity, Enum Cases │ │ - Owned Paths       │
      └─────────────────────┘ └─────────────────────┘ └─────────────────────┘
                 │                       │                       │
                 └───────────────────────┼───────────────────────┘
                                         │
                                         ▼
                              Test Runner That Counts
```

---

## 2. Structural Grounding: The Closure Check

In AgentScript (ASL), every name in a module must resolve to one of three things:
1. A builtin of the host (the stage-0 host binds 123 named functions and 11 constructors, besides operators and special forms, counted 2026-09-24).
2. A local binding (a function defined with a `fn` line, a `let` binding, or a parameter).
3. A symbol imported from another module (`:i [(pkg/module :a m)]`), called as `m/name`.

The stage-0 host checks this before anything runs. `asl/host/out/asl-host check FILE` resolves every name in the module graph, checks call arity, and checks that a match covers every case of an enum. Here is a module an agent might plausibly write:

```agentscript
(module probe/p10a :d "an invented builtin" :x [norm runTests] :i [])

fn norm x: Float64 y: Float64 -> Float64
  (sqrt (+ (* x x) (* y y)))

fn runTests -> Bool
  (do (assert (= (norm 3.0 4.0) 5.0) "norm") true)
```

The host has no `sqrt`, so the check stops at the call:

```text
p10a.asl:4:4: ERR_UNKNOWN_SYMBOL sqrt
check failed: p10a.asl: 1 error(s)
```

The hallucinated name never reaches runtime, never becomes an obscure runtime exception, and never reaches a peer agent's context.

A caution from our own toolchain: this guarantee belongs to the host. `asl check` checks delimiter balance only, and `asl test` still runs on our older evaluator, asl-core, which reads an unknown name as data. On 2026-09-24 the file above passed both `asl check` and `asl test` (exit 0), while `asl-host check` rejected it. Until `asl test` moves to the host, the host is the check to trust.

---

## 3. Tests That Cannot Fake Green

The same split shows up in the test runner. `asl-host test FILE` runs the exported `runTests`, which has to return `true`, and requires at least one `assert` or `refute` to execute:

* A `runTests` that asserts something trivial and returns `false` fails with `ERR_TEST_FAILED: runTests returned false, not true`. `asl test` passed the same file.
* A `runTests` with no assertions fails with `ERR_TEST_FAILED: zero assertions executed`. `asl test` rejects this one too.

The workspace gate rule, run by `./bin/asl audit gates --full --sync`, adds a counting requirement: every suite has to execute more than zero assertions, and the assertions it declares have to equal the ones it executes, so deleting an assertion is visible rather than silently green.

---

## 4. Epistemic Citation Verification: Enforcing Source Grounding

When agents take facts from documentation or search results, a claim can carry its evidence:

```agentscript
(module probe/p10b :d "Quote-grounded claims" :x [Claim grounded? runTests] :i [])

schema Claim
  statement: String
  sourceId: String
  exactQuote: String

fn grounded? claim: Claim source: String -> Bool
  (and (not (string-empty? (.-exactQuote claim))) (string-contains? source (.-exactQuote claim)))

fn runTests -> Bool
  (let [(doc "timeoutMs: Integer duration in milliseconds")
        (good {:statement "Timeout is in milliseconds" :sourceId "doc402" :exactQuote "duration in milliseconds"})
        (bad {:statement "Timeout is in seconds" :sourceId "doc402" :exactQuote "duration in seconds"})]
    (do (assert (grounded? good doc) "quoted verbatim") (refute (grounded? bad doc) "not in the source") true))
```

The check is a plain substring search of the quote in the retrieved source: if the quote does not appear verbatim, the claim is not grounded and is not acted on. This removes the "lazy summary" failure where an agent invents a plausible feature the documentation never mentions. The harness carries a fuller version, `verifyCitation` in `harness/src/grounding.asl`, which also looks up the source by id and rejects low-confidence claims; that module passes `asl-host check`, and its test suite does not yet load on the host.

---

## 5. Path and Capability Jailing

When an agent edits files through the `asl` toolbelt:

1. **Workspace Jail:** every path an op receives resolves against the workspace root, and a path outside it is rejected with `ERR_BOUNDARY_VIOLATION` before anything is read or written.
2. **Owned Paths:** the agent loop, `(:agent ...)`, edits only inside its declared `:owns` list and runs the named gates before reporting.
3. **Staged Writes:** edits are staged with `(:edit)`, inspected with `(:diff)` and written atomically with `(:flush)`, or dropped with `(:discard)`.

What we are building next is the language half: effect tracking, so that functions touching disk, network or console are marked and a pure function that prints is rejected. Today the host accepts it.

---

## 6. Defense in Depth for Autonomous Systems

Replacing prompt suggestions with checks that run before code does (closure and arity checks, exhaustive enum matches, tests that must return true and count their assertions, quote-verified claims and path jails) gives agents a boundary that holds when their attention does not.

Agents can explore, refactor and generate at full speed, because an invented name, an ungrounded claim or a vacuous test is stopped at the checker instead of discovered in production.
