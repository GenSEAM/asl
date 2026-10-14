# Why 3B Local Models Fail at Python but Fly on S-Expressions: Zero-Tax Autonomous Coding on Apple Silicon
*Published on September 10, 2026 · 7 min read · By the GenSEAM Team*
*Canonical URL: https://aslang.dev/blog/why-3b-local-models-fail-at-python-but-fly-on-s-expressions*

## 1. The Bottleneck

Picture an autonomous coding loop running entirely on a laptop: a 3B-parameter coder model, quantized, served by `llama.cpp` on Apple Silicon. No cloud calls, no network latency, no data leaving the machine. The model is fast and cheap to run. The question is whether what it writes survives the first parse.

The task: take an event loop, add an error accumulator, and keep the priority dispatch. The model writes Python:

```python
def process_events(event_queue, max_errors=3):
    errors = []
    for event in event_queue:
        try:
            if not validate_checksum(event):
                raise ChecksumError("bad event payload")
            record_metric("event_inbound", 1)
        except ChecksumError as e:
            errors.append(e)
            if len(errors) >= max_errors:
                return Failure(errors)
        elif event.is_priority:
            dispatch_priority(event)
```

The `elif` was meant to pair with an `if` that the model never wrote at that indentation; it now sits directly after an `except` block. The harness runs `python3 -m py_compile module.py` (Python 3.13 here):

```text
  File "module.py", line 12
    elif event.is_priority:
    ^^^^
SyntaxError: invalid syntax
```

The error goes back into the context window, the model re-emits the function, and the familiar loop begins: each repair costs prompt tokens, and a small context window fills up with failed attempts rather than with the task. This is an illustration of a failure mode, not a measured run; section 4 says what we have and have not measured.

## 2. Why Grammar Shape Matters

Why would a model that can reason through a state machine stumble on indentation and closing brackets?

Python's block structure follows Peter Landin's 1966 "off-side rule": scope is decided by column position, and a block ends without any closing token. To know whether the next line belongs to the inner `if`, the `try` or the `for`, the model has to track indentation depth implicitly, across many tokens, and emit the right amount of whitespace at the right moment. Nothing in the output marks the intent "this block is now closed".

Rust and TypeScript fail differently: brackets are explicit, but validity depends on non-local constraints. Rust's borrow checker decides whether a reference taken early in a function is still live at a later use, a whole-function analysis that a left-to-right generator cannot look ahead to satisfy.

Our hypothesis is that for small models the shape of the grammar matters as much as the parameter count: a grammar that closes every construct with an explicit, local token asks less bookkeeping of the model. It is a hypothesis; section 4 is how we intend to test it.

## 3. The AgentScript Approach

In AgentScript (ASL) every form is delimited by balanced parentheses, operators are prefix, and the text is a direct serialization of the syntax tree. Here is the same accumulator, written as a fold over a closed `Event` type:

```agentscript
(module engine/events :x [processEvents runTests])

enum Event (event id: Int64 valid: Bool)

enum Tally (tally good: Int64 bad: Int64)

fn step acc: Tally ev: Event -> Tally
  (mt acc
    ((tally good bad)
      (mt ev
        ((event id valid) (if valid (tally (+ good 1) bad) (tally good (+ bad 1)))))))

fn processEvents queue: (List Event) maxErrors: Int64 -> (Result Int64 Str)
  (mt (fold step (tally 0 0) queue)
    ((tally good bad) (if (>= bad maxErrors) (err "checksum error threshold exceeded") (ok good))))

fn runTests -> Bool
  (do
    (assert (= (processEvents (list (event 1 true) (event 2 false) (event 3 true)) 3) (ok 2)) "under threshold")
    (assert (= (processEvents (list (event 1 false) (event 2 false)) 2) (err "checksum error threshold exceeded")) "threshold")
    true)
```

`host/out/asl-host test` on this file reports 2 assertions executed, 2 passed. While drafting it we closed one parenthesis too many; the host answered `ERR_READ_UNBALANCED unmatched ')'` with the position, before running anything. That is the property this post is about: a structural mistake is caught by counting delimiters, and the error points at one specific character rather than at a line whose meaning depends on the lines around it.

What the language gives a small model, concretely:

1. **Explicit closure.** Every `(` is closed by its own `)`. Ending a block is a token the model emits, not a whitespace decision.
2. **No precedence table.** `(+ good 1)` and `(>= bad maxErrors)` say their evaluation order outright.
3. **A checked, closed set of names.** The stage-0 host rejects unbound names, wrong arity, non-exhaustive matches over an `enum` and unmarked effects before running a program, so a hallucinated helper is a load error, not a runtime surprise.
4. **No nil, no exceptions.** Absence is `(none)`, failure is `(err e)`, and both are taken apart with `mt`.

There is also a path to constraining generation itself. The `asl-slm` package contains a grammar token-mask engine (`computeTokenMaskBitset`, `isTokenAllowed`) that, given a grammar state and a vocabulary, computes which tokens may come next; its two test suites pass on the stage-0 host (149 checks). It is a library today: it is not wired into `llama.cpp` or any other inference server.

## 4. What We Have Measured, and What We Have Not

We have not run a recorded comparison of a 3B model writing Python against the same model writing ASL. There is no pass-rate, token or latency figure in the repository for that experiment, so this post quotes none.

The experiment we intend to run is straightforward: the same task specifications, the same quantized model and the same local server, in Python and in ASL, counting first-pass parse success, first-run test success and repair turns to green, with each language's strict checker (`python3 -m py_compile` plus the task's tests on one side, `asl-host check` and `asl-host test` on the other) as the gate. When it is done, the method and raw results will be in the repository before a number appears here.

## 5. Trying It Locally

You can check and run ASL with the stage-0 host from a checkout of the repository:

```bash
git clone https://github.com/GenSEAM/asl.git
cd asl
sh host/build.sh                     # builds the C host into host/out/
host/out/asl-host check events.asl   # names, arity, enums, effects
host/out/asl-host test events.asl    # runs runTests, prints the assertion count
```

To point a local model at ASL, give it [`llms.txt`](https://aslang.dev/llms.txt) as the language reference and use `asl-host check` as the gate in your loop: exit code 0 and an executed assertion count are the evidence.

## 6. Resources

- Language reference and site: [aslang.dev](https://aslang.dev)
- Source: [github.com/GenSEAM/asl](https://github.com/GenSEAM/asl)
