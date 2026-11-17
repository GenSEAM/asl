# Every Test Answers with a Receipt: Assertion Counts and Telemetry in ASL
*By GenSEAM | September 2026*

In AgentSlang (ASL), people do not review agent-written code by reading every function—they read the verification receipts. When an agent runs `asl test` or includes `(:test ...)` in a toolbelt batch, the runner checks the module graph, executes `runTests`, and refuses to pass unless at least one assertion actually ran, reporting the exact executed assertion count in the receipt.

That turns testing from a bare pass/fail bit into evidence an agent coordinator or human reviewer can trust. In a fast agent edit-verify loop, a green exit code from an empty test or an unmeasured memory spike compounds across dozens of turns, while heavy external profilers distort timing and flood the context window with trace output.

This post describes what the strict `asl test` runner enforces and reports today, what the runtime exposes for memory inspection, and the per-test resource fields we are adding to the receipt schema.

---

## 1. What the Runner Reports Today

There is one strict runner, `asl test`. `asl test FILE` runs the exported `runTests`, which must return `true` after at least one assertion or refutation has executed. It prints how many ran and exits non-zero on any failure, on an unknown name anywhere in the module graph, or on a test that asserted nothing. `asl test FILE` and the `(:test)` op use the same runner; an older, lenient runner that once passed suites this one rejects has been retired.

```text
$ asl test asl/packages/asl-slm/tests/maskerTest.asl
asl/packages/asl-slm/tests/maskerTest.asl: 78 assertion(s) executed, 36 refutation(s) executed (114 passed)
```

The assertion count is the first piece of telemetry an agent needs. A green exit with zero assertions is impossible on this runner, so "passed" always means something was checked.

---

## 2. Memory From Inside, Time From Outside

The runtime has an in-process probe. With `ASL_GC_STATS=1` set, an earlier build of the runtime printed its garbage collector's counters as an ASN form on exit. The output below was captured on 2026-10-14 with that earlier build and is shown as a dated example, not as current output:

```text
$ ASL_GC_STATS=1 asl test asl/packages/asl-slm/tests/maskerTest.asl
(:gcStats :collections 0 :objectsAllocated 3540 :objectsFreed 0 :bytesAllocated 116278 :bytesLive 0 :totalGCNs 0 :pagesFreed 0 :pagesAcquired 14)
asl/packages/asl-slm/tests/maskerTest.asl: 78 assertion(s) executed, 36 refutation(s) executed (114 passed)
```

This suite allocates about 114 KB of ASL objects and never triggers a collection. Wall time and peak resident memory are not reported by the runner; today they are measured from outside the process. On 2026-10-14, with the same earlier build in a Linux x86_64 container, three runs of this suite took 33 to 38 ms wall-clock each (timed around the subprocess), and the largest peak resident set across them was 11,396 KB (`getrusage` on the child processes). That includes process start and loading the module graph, not just the assertions. Measuring from outside costs the test nothing, but it sees the whole process, not individual suites or functions.

The dimensions an agent needs from a test run:

| Metric | What it catches |
| :--- | :--- |
| **Assertions executed** | Vacuous tests: a suite that asserts nothing proves nothing. |
| **Elapsed time** | Algorithmic regressions, quadratic loops, accidental I/O. |
| **Allocation and peak memory** | Leaks, unbounded buffers, retained structures. |

Thresholds for alerts on these are a design choice we have not yet made; we will set them per suite from recorded baselines rather than state them in advance.

---

## 3. The Target: Telemetry in the Receipt

We want the runner to read the monotonic clock and the allocator's counters at suite entry and exit, and to emit one ASN receipt per suite. A sketch of the shape, filled in with the values measured above:

```lisp
(:testReceipt :suite "asl/packages/asl-slm/tests/maskerTest.asl" :runner :asl :status :passed :assertions 78 :refutations 36 :wallMs 33 :bytesAllocated 116278 :maxRssKb 11396)
```

This receipt is a design, not current output. The probe would read a clock and a counter and do integer arithmetic, so it should not perturb what it measures; how small that overhead really is will be measured once the runner emits it, not asserted here.

---

## 4. The Gate Suite

At workspace scale, suites run through `asl audit gates --full`, implemented in the `asl-gates` package. A failing suite is red unless it is listed with its digest in the project's known-red ledger, and the gate reports a ledger that lost lines since its base. Without `--full`, the command runs only the static checks and reports the suites as not run. Adding per-suite time and memory to the gate report is part of the same target as the receipt.

---

## 5. Portability

ASL programs also compile, through the `asl-target-llvm` package, to native code and to `wasm32-unknown-unknown`. On wasm32 the only host builtin a program can call is `print`: clocks, files, environment and sockets are rejected when the program is lowered, with `ERR_CAPABILITY_ABSENT`. So the same receipt cannot be produced inside a wasm32 module today; time would have to be measured by the embedder, and memory read from the module's own allocator. Today test suites run through `asl test`, not inside a wasm32 module.

---

## 6. Conclusion

Tests in an agent loop should report more than green or red: how many assertions actually ran, how long the run took, and how much memory it held. Today the strict runner reports the first, `ASL_GC_STATS=1` reports allocation, and the operating system reports time and peak memory from outside. Folding all of it into one compact receipt per suite is the work in progress.

- Run the strict runner: `asl test <file>`.
- Run the gate suite: `asl audit gates --full`.
- Read about the toolchain in [The Agentic Toolchain](/blog/the-agentic-toolchain-and-native-action-loops).
