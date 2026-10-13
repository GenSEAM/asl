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

### The 3 Core Invariants of AgentScript (ASL)

1. **Zero-Foreign Code, Measured**: the language packages are pure ASL. On 2026-09-24, `git ls-files asl/packages` listed 652 `.asl`, 52 `.asn`, 10 `.md` and 3 `.gitignore` files and no Python or JavaScript. The toolchain around them is not there yet: `bin/asl` is a bash script with embedded Python, and `./bin/asl audit foreign` counted 453 foreign files with 77,975 lines across the workspace (Python 57,040, shell 15,099, C 3,901, JavaScript 1,767, PowerShell 168). The audit fails when foreign lines exceed a recorded baseline, and raising the baseline takes a recorded reason and date. Compiling ASL to WebAssembly and native binaries is the direction; `asl build` returns `ERR_UNIMPLEMENTED` today.
2. **Tools as Forms**: agent tools are operations called as S-expressions, `asl '(:read ...) (:edit ...) (:check ...)'`, several forms per call, each answered with an ASN receipt. `asl '(:tools)'` lists them.
3. **Verification in the Harness, Not in Prose**: an agent does not declare victory in words. A step closes when its gate exits 0: `asl/host/out/asl-host test FILE` fails unless the suite's `runTests` returns `true` after at least one assertion ran, and the workspace gate suite is `./bin/asl audit gates --full --sync`.

---

## What We Can Show Today

We have not measured framework size or start-up latency against a Python or TypeScript orchestrator, so this post quotes no reduction figure. What the repository shows is the discipline itself: a ratchet that makes every increase in foreign code an explicit, recorded exception, tests that fail when they assert nothing, and tools called as forms with structured receipts.

---

## Next Steps
- Next Article: [AgentScript and the case for S-expressions](/blog/agent-script-the-optimal-agent-language).
