# Test Telemetry for Agents: Time, Memory and Assertion Counts in Every Receipt
*By GenSEAM | September 2026*

When autonomous AI coding agents work on large codebases, verification cannot stay a bare pass/fail bit.

In human workflows, tests run by hand or on remote CI. If a test takes 500ms or holds 200MB of memory, the developer barely notices. In an agent loop, where an agent may run dozens of edit-verify cycles within a single task, unobserved latency, memory growth and vacuous tests compound: the loop slows, the context fills with noise, and a green bar that measured nothing reads as success.

Traditional instrumentation brings its own costs:
1. **Timing distortion**: bytecode rewriting and dynamic hooks inflate execution time and change the behaviour being measured.
2. **Allocation pressure**: profilers allocate telemetry objects of their own.
3. **Telemetry bloat**: verbose traces dump large payloads into the agent's observation window.

This post describes what AgentScript (ASL) test runners report today, how we measure time and memory around them now, and the telemetry we are building into the receipt.

---

## 1. What the Runners Report Today

ASL has two test runners, and the difference matters to an agent.

- **The stage-0 host**, `asl/host/out/asl-host test FILE`, runs the exported `runTests`, which must return `true` after at least one assertion or refutation has executed. It prints how many ran and exits non-zero on any failure, on an unknown name anywhere in the module graph, or on a test that asserted nothing.
- **asl-core**, reached by `asl test FILE`, is lenient: it treats an unknown name as data and passes a `runTests` that returns `false`, as long as every executed assertion held.

The same file can report different counts on the two. On 2026-09-24:

```text
$ asl/host/out/asl-host test tests/conformance/rules/rulesSyntaxDialectTest.asl
tests/conformance/rules/rulesSyntaxDialectTest.asl: 48 assertion(s) executed, 32 refutation(s) executed (80 passed)

$ asl test tests/conformance/rules/rulesSyntaxDialectTest.asl
✓ tests/conformance/rules/rulesSyntaxDialectTest.asl: 44 assertion(s) executed, 28 refutation(s) executed and recorded cleanly.
```

And a file can pass one and fail the other. The web catalog's own parity suite, `asl/web/tests/blogParityTest.asl`, stops on the host with 49 load errors before any assertion runs, because it calls `listLen` and `nil`, neither of which the host binds; under `asl test` it runs 90 assertions before one fails. The assertion count is the first piece of telemetry an agent needs, and it is only meaningful from the strict runner.

---

## 2. Time and Memory, Measured Around the Runner

Neither runner reports elapsed time or memory yet, and `asl test` takes no metrics flag. What works today is measuring from outside the process. On macOS:

```text
$ /usr/bin/time -l asl/host/out/asl-host test tests/conformance/rules/rulesSyntaxDialectTest.asl
tests/conformance/rules/rulesSyntaxDialectTest.asl: 48 assertion(s) executed, 32 refutation(s) executed (80 passed)
        0.01 real         0.01 user         0.00 sys
             8765440  maximum resident set size
```

Across three runs on 2026-09-24 on a local macOS machine, this suite took 0.01 s wall-clock each time and peaked at about 8.8 MB resident (8,765,440 to 8,847,360 bytes). Measuring from outside costs the test nothing, since the probe is the operating system's own accounting, but it sees the whole process, not individual suites or functions.

The dimensions an agent needs from a test run:

| Metric | What it catches |
| :--- | :--- |
| **Assertions executed** | Vacuous tests: a suite that asserts nothing proves nothing. |
| **Elapsed time** | Algorithmic regressions, quadratic loops, accidental I/O. |
| **Peak resident memory** | Leaks, unbounded buffers, retained structures. |

Thresholds for alerts on these are a design choice we have not yet made; we will adopt them per suite from recorded baselines rather than state them in advance.

---

## 3. The Target: Telemetry in the Receipt

We are building the host runner to take its own timings with the monotonic clock around each suite, without allocating during the run, and to emit one ASN receipt per suite:

```lisp
(:testReceipt :suite "tests/conformance/rules/rulesSyntaxDialectTest.asl" :runner :host :status :passed :assertions 48 :refutations 32 :wallMs 10 :maxRssBytes 8765440)
```

The values above are the ones measured in section 2, placed in the receipt shape we intend to emit. As a wire frame, this receipt costs 51 tokens against 60 for the same fields as a JSON object (cl100k_base; 52 against 61 on o200k_base; tiktoken 0.12.0, 2026-09-24), a saving of about 15 percent on this one frame. Savings on larger tabular payloads are higher and are recorded in `asl/bench/asn_tokens.lock`.

The receipt design follows from the observer problem above: the probe reads a clock and a counter at suite entry and exit and does integer arithmetic, so the measurement does not perturb what it measures. How small that overhead is on the host will be measured, not asserted, once the runner emits it.

---

## 4. The Gate Suite

At workspace scale, suites run through `./bin/asl audit gates --full --sync`. A failing suite is red unless it is listed with its digest in `.asl/mem/knownRed.asn`, and that list may only shrink. Without `--full`, the command runs only the static checks: on 2026-09-24 it reported 19 checks passed and status `:pending`, with 816 suites not yet run. Adding per-suite time and memory to the gate report is part of the same target as the receipt.

---

## 5. Portability

The runtime is meant to run on macOS, Linux and WebAssembly, so the telemetry needs a clock and a memory counter on each: `clock_gettime(CLOCK_MONOTONIC)` and the resident set size on POSIX hosts, and `clock_time_get` with the linear memory page count on WASI. The receipt shape stays the same across hosts. This is design; today the stage-0 host is a native C binary built from `asl/host/src`, and the in-process clock is not wired in on any host.

---

## 6. Conclusion

Tests in an agent loop should report more than green or red: how many assertions actually ran, how long the run took, and how much memory it held. Today the strict runner reports the first, and the operating system can report the other two from outside. Folding all three into one compact receipt per suite is the work in progress.

- Run the strict runner: `asl/host/out/asl-host test <file>`.
- Run the gate suite: `./bin/asl audit gates --full --sync`.
- Read about the toolchain in [The Agentic Toolchain](/blog/the-agentic-toolchain-and-native-action-loops).
