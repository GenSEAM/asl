# Against Agent Framework Bloat: The Case for Radical Simplicity over Large Orchestrators
*By GenSEAM | September 2026*

Over the past three years, AI engineering teams have tried to make LLMs write software by piling layers of speculative abstraction on top of standard programming environments:

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
4. Does the native platform provide it? (POSIX syscalls, zero-copy shm)
5. Can this be one single line? (Make it one line)
6. Only then: write the minimum verifiable code.
```

### The 3 Core Invariants of AgentSlang (ASL)

1. **Zero-Foreign Code, Measured**: the language packages are ASL. On 2026-10-14 (commit `36deda1`), `git ls-files packages` listed 1,602 `.asl` files; the only other code in it is test material: two shell scripts, two C probes, LLVM IR goldens and upstream parser samples kept as `.sample` fixtures. The foundation underneath is not ASL: the stage-0 host in `host/` is 33 C source and header files, 10,202 lines by `wc -l`. It parses, checks and runs ASL. The way off it is the self-hosted compiler `asl1`, which `asl-target-llvm` lowers to LLVM IR; a seed exists for `arm64-apple-darwin` only, and self-hosting is in progress. The same backend already compiles this website to WebAssembly (`web/dist/site.wasm`, 252,954 bytes in the 2026-10-14 build).
2. **Tools as Forms**: agent tools are operations called as S-expressions, `asl '(:read ...) (:edit ...) (:check ...)'`, several forms per call, each answered with an ASN receipt. `asl '(:tools)'` lists them.
3. **Verification in the Harness, Not in Prose**: an agent does not declare victory in words. A step closes when its gate exits 0: `host/out/asl-host test FILE` fails with `ERR_TEST_FAILED: zero assertions executed` unless the suite's `runTests` returns `true` after at least one assertion ran, and `asl audit gates` runs the gate suites.

---

## What We Can Show Today

We have not measured framework size or start-up latency against a Python or TypeScript orchestrator, so this post quotes no reduction figure. What the repository shows is the discipline itself: packages written in one language, a checker that rejects unknown names, wrong arity and unmarked effects before anything runs, tests that fail when they assert nothing, and tools called as forms with structured receipts.

---

## Next Steps
- Next Article: [AgentSlang and the case for S-expressions](/blog/agent-slang-the-optimal-agent-language).
