# Test Telemetry for Agents: Time, Memory and Assertion Counts in Every Receipt
*By GenSEAM | September 2026*

When autonomous AI coding agents work on large codebases, verification cannot stay a bare pass/fail bit.

In human workflows, tests run by hand or on remote CI. If a test takes 500ms or holds 200MB of memory, the developer barely notices. In an agent loop, where an agent may run dozens of edit-verify cycles within a single task, unobserved latency, memory growth and vacuous tests compound: the loop slows, the context fills with noise, and a green bar that measured nothing reads as success.

Traditional instrumentation brings its own costs:
1. **Timing distortion**: bytecode rewriting and dynamic hooks inflate execution time and change the behaviour being measured.
2. **Allocation pressure**: profilers allocate telemetry objects of their own.
3. **Telemetry bloat**: verbose traces dump large payloads into the agent's observation window.

This post describes what the AgentScript (ASL) test runner reports today, what the host can already tell you about memory, and the telemetry we want in every receipt.

---

## 1. What the Runner Reports Today

There is one strict runner: the stage-0 host. `asl/host/out/asl-host test FILE` runs the exported `runTests`, which must return `true` after at least one assertion or refutation has executed. It prints how many ran and exits non-zero on any failure, on an unknown name anywhere in the module graph, or on a test that asserted nothing. `asl test FILE` and the `(:test)` op run on the same host; the lenient asl-core runner, which once passed suites the host rejected, is retired.

```text
$ asl/host/out/asl-host test asl/packages/asl-slm/tests/maskerTest.asl
asl/packages/asl-slm/tests/maskerTest.asl: 78 assertion(s) executed, 36 refutation(s) executed (114 passed)
```

The assertion count is the first piece of telemetry an agent needs. A green exit with zero assertions is impossible on this runner, so "passed" always means something was checked.

---

## 2. Memory From Inside, Time From Outside

The host already has one in-process probe. With `ASL_GC_STATS=1` set, it prints its garbage collector's counters as an ASN form on exit:

```text
$ ASL_GC_STATS=1 asl/host/out/asl-host test asl/packages/asl-slm/tests/maskerTest.asl
(:gcStats :collections 0 :objectsAllocated 3540 :objectsFreed 0 :bytesAllocated 116278 :bytesLive 0 :totalGCNs 0 :pagesFreed 0 :pagesAcquired 14)
asl/packages/asl-slm/tests/maskerTest.asl: 78 assertion(s) executed, 36 refutation(s) executed (114 passed)
```

This suite allocates about 114 KB of ASL objects and never triggers a collection. Wall time and peak resident memory are not reported by the runner; today they are measured from outside the process. On 2026-10-14, in a Linux x86_64 container, three runs of this suite took 33 to 38 ms wall-clock each (timed around the subprocess), and the largest peak resident set across them was 11,396 KB (`getrusage` on the child processes). That includes process start and loading the module graph, not just the assertions. Measuring from outside costs the test nothing, but it sees the whole process, not individual suites or functions.

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
(:testReceipt :suite "asl/packages/asl-slm/tests/maskerTest.asl" :runner :host :status :passed :assertions 78 :refutations 36 :wallMs 33 :bytesAllocated 116278 :maxRssKb 11396)
```

This receipt is a design, not current output. The probe would read a clock and a counter and do integer arithmetic, so it should not perturb what it measures; how small that overhead really is will be measured once the runner emits it, not asserted here.

---

## 4. The Gate Suite

At workspace scale, suites run through `asl audit gates --full`, implemented in the `asl-gates` package. A failing suite is red unless it is listed with its digest in the known-red ledger, `.asl/mem/knownRed.asn`, and the gate reports a ledger that lost lines since its base. Without `--full`, the command runs only the static checks and reports the suites as not run. Adding per-suite time and memory to the gate report is part of the same target as the receipt.

---

## 5. Portability

ASL programs also compile, through the `asl-target-llvm` package, to native code and to `wasm32-unknown-unknown`. On wasm32 the only host builtin a program can call is `print`: clocks, files, environment and sockets are rejected when the program is lowered, with `ERR_CAPABILITY_ABSENT`. So the same receipt cannot be produced inside a wasm32 module today; time would have to be measured by the embedder, and memory read from the module's own allocator. Today only the stage-0 host runs test suites.

---

## 6. Conclusion

Tests in an agent loop should report more than green or red: how many assertions actually ran, how long the run took, and how much memory it held. Today the strict runner reports the first, `ASL_GC_STATS=1` reports allocation, and the operating system reports time and peak memory from outside. Folding all of it into one compact receipt per suite is the work in progress.

- Run the strict runner: `asl/host/out/asl-host test <file>`.
- Run the gate suite: `asl audit gates --full`.
- Read about the toolchain in [The Agentic Toolchain](/blog/the-agentic-toolchain-and-native-action-loops).
