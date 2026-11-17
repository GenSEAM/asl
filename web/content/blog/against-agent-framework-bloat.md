# Fewer Moving Parts: How ASL Keeps Agent-Built Infrastructure Small
*By GenSEAM | September 2026*

Agents now write much of the glue that holds infrastructure together, and every layer they add is a layer someone has to verify. AgentSlang (ASL) bets on fewer layers: one language for code, data and tool calls, a checker that rejects bad code before it runs, and a toolbelt where `asl '(:read ...) (:edit ...) (:check ...)'` is a single call answered by a single `(:batch ...)` of receipts. Fewer moving parts means less to break, and less for the person reviewing the run to read.

It is a deliberate answer to what piled up over the past three years, as teams tried to make LLMs write software by stacking speculative abstraction on top of standard programming environments:

1. **The Wrapper Trap**: large orchestration frameworks wrapping simple API calls in dozens of classes, abstract interfaces and state graphs.
2. **Subprocess Hell & Memory Leaks**: agents spawning unmonitored Python subshells, hanging Docker containers and orphan child processes.
3. **Looping Hallucinations**: when a model invents a file or crashes a runtime, framework boilerplate dumps a long traceback into the prompt, and the next turn reasons about noise.

The result is fragility: agents that look impressive in short demos and fail a few turns into real work.

---

## The Easy Solution: Radical Simplicity & The Ladder of Restraint

The cleanest solution is the shortest working diff that solves the problem. The best code is the code that is never written.

Before writing a line of agent code or building an abstraction, we climb **The Ladder of Restraint**:

```text
1. Does this need to be built at all? (YAGNI: delete it)
2. Does it already exist in the codebase? (Reuse existing utils)
3. Does the standard library cover it? (Use standard forms)
4. Does the native platform provide it? (POSIX syscalls, shared memory)
5. Can this be one single line? (Make it one line)
6. Only then: write the minimum verifiable code.
```

### The 3 Core Invariants of AgentSlang (ASL)

1. **One Language, Measured**: the language packages are ASL. On 2026-10-14, `git ls-files packages` listed 1,602 `.asl` files; the only other code in it is test material: two shell scripts, two C probes, LLVM IR goldens and upstream parser samples kept as `.sample` fixtures. That count is a dated snapshot, not a gate. The compiler is itself written in ASL and compiles itself through LLVM IR (gated on macOS only), and the same backend compiles this website to WebAssembly.
2. **Tools as Forms**: agent tools are operations called as S-expressions, `asl '(:read ...) (:edit ...) (:check ...)'`, several forms per call, each answered with an ASN receipt. `asl '(:tools)'` lists them.
3. **Verification in the Harness, Not in Prose**: an agent does not declare victory in words. A step closes when its gate exits 0: `asl test FILE` fails with `ERR_TEST_FAILED: zero assertions executed` unless the suite's `runTests` returns `true` after at least one assertion ran, and `asl audit gates` runs the gate suites.

---

## What We Can Show Today

We have not measured framework size or start-up latency against a Python or TypeScript orchestrator, so this post quotes no reduction figure. What the repository shows is the discipline itself: packages written in one language, a checker that rejects unknown names, wrong arity and unmarked effects before anything runs, tests that fail when they assert nothing, and tools called as forms with structured receipts.

---

## Next Steps
- Next Article: [AgentSlang and the case for S-expressions](/blog/agent-slang-the-optimal-agent-language).
