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

In AgentSlang (ASL), every name in a module must resolve to one of three things:
1. A builtin of the host or a function of its prelude.
2. A local binding (a function defined with a `fn` line, a `let` binding, or a parameter).
3. A symbol imported from another module (`:i [(pkg/module :a m)]`), called as `m/name`.

The stage-0 host checks this before anything runs. `asl/host/out/asl-host check FILE` resolves every name in the module graph, checks call arity, and checks that a match covers every case of an enum. Here is a module an agent might plausibly write:

```agentslang
(module probe/p10a :x [total runTests] :i [])

fn total xs: (List Int64) -> Int64
  (if (= (len xs) 0) 0 (listSum xs))

fn runTests -> Bool
  (do (assert (= (total (list 1 2 3)) 6) "total") true)
```

ASL has no `len` (the builtin is `listLength`), so the check stops at the call:

```text
p10a.asl:4:11: ERR_UNKNOWN_SYMBOL len
check failed: p10a.asl: 1 error(s)
```

The hallucinated name never reaches runtime, never becomes an obscure runtime exception, and never reaches a peer agent's context.

A caution from our own history: this guarantee belongs to the host. Our older evaluator, asl-core, read an unknown name as data and passed files like this one. It is retired: `asl check` and `asl test` on an `.asl` file now run on the stage-0 host, and the host is the check to trust.

---

## 3. Tests That Cannot Fake Green

The same split shows up in the test runner. `asl-host test FILE` runs the exported `runTests`, which has to return `true`, and requires at least one `assert` or `refute` to execute:

* A `runTests` that executes its assertions and then returns `false` fails with `ERR_TEST_FAILED: runTests returned false, not true`.
* A `runTests` with no assertions fails with `ERR_TEST_FAILED: zero assertions executed`.
* An assertion whose condition is a constant, such as `(assert true "ok")` or `(assert (= (+ 1 1) 2) "ok")`, is rejected before the suite runs with `ERR_CONSTANT_ASSERT`: it can never fail, so it proves nothing.

The workspace gate rule in `grammar/rules.asn` adds a counting requirement: every gate suite has to execute more than zero assertions, and the assertions it declares are reconciled against the ones it executes, so deleting or skipping an assertion shows up as a gap rather than a silent green.

---

## 4. Epistemic Citation Verification: Enforcing Source Grounding

When agents take facts from documentation or search results, a claim can carry its evidence:

```agentslang
(module probe/p10b :x [Claim grounded? runTests] :i [])

schema Claim
  statement: String
  sourceId: String
  exactQuote: String

fn grounded? claim: Claim source: String -> Bool
  (and (not (stringEmpty? claim.exactQuote)) (stringContains? source claim.exactQuote))

fn runTests -> Bool
  (let [(doc "timeoutMs: Integer duration in milliseconds")
        (good {:statement "Timeout is in milliseconds" :sourceId "doc402" :exactQuote "duration in milliseconds"})
        (bad {:statement "Timeout is in seconds" :sourceId "doc402" :exactQuote "duration in seconds"})]
    (do (assert (grounded? good doc) "quoted verbatim") (refute (grounded? bad doc) "not in the source") true))
```

The check is a plain substring search of the quote in the retrieved source: if the quote does not appear verbatim, the claim is not grounded and is not acted on. This removes the "lazy summary" failure where an agent invents a plausible feature the documentation never mentions. The sample passes `asl-host test` (one assertion, one refutation). It is a pattern, not a library: the toolchain does not ship a citation verifier today.

---

## 5. Path and Capability Jailing

When an agent edits files through the `asl` toolbelt:

1. **Workspace Jail:** every path an op receives resolves against the workspace root, and a path outside it is rejected with `ERR_BOUNDARY_VIOLATION` before anything is read or written.
2. **Owned Paths:** a transaction, `(:txn :owns (<path> ...) <form> ...)`, stages edits only inside its `:owns` prefixes (anything else is `ERR_OWNS`), runs its nested gates on the staged content and flushes only if they pass. The agent loop, `(:agent ...)`, takes the same `:owns` and `:gates`.
3. **Staged Writes:** edits are staged with `(:edit)`, inspected with `(:diff)` and written atomically with `(:flush)`, or dropped with `(:discard)`.

The language half is effect markers. A function that names an effectful builtin such as `println`, or calls a function that does, must be marked (`fn ! name` or a trailing `!`), and `asl-host check` rejects an unmarked one with `ERR_EFFECT_UNMARKED`. The marker makes effects visible to a reviewer; running marked code inside a granted capability context is still a design goal.

---

## 6. Defense in Depth for Autonomous Systems

Replacing prompt suggestions with checks that run before code does (closure and arity checks, exhaustive enum matches, effect markers, tests that must return true and count their assertions, quote-verified claims and path jails) gives agents a boundary that holds when their attention does not.

Agents can explore, refactor and generate at full speed, because an invented name, an ungrounded claim or a vacuous test is stopped at the checker instead of discovered in production.
