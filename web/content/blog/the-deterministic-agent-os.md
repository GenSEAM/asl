# The Model Proposes, the Toolchain Verifies: ASL's Split Between Agent ALU and Deterministic Host
*By GenSEAM | September 2026*

In AgentSlang (ASL), the language model does what only a model can do—choose the design and write the forms—while a deterministic toolchain handles symbol lookup, staged file transactions, static checking and test execution. The two sides meet over a clean contract: the agent sends a batch of ASN forms in one call, and the host returns a batch of verified receipts that both the agent and human reviewers can trust.

Most agent stacks blur that boundary by asking the LLM to act as a whole operating system at once: planner, bash shell, file browser, compiler and test inspector. Without a deterministic kernel underneath, four failures repeat:
1. **Context Drowning**: Whole-file `cat` dumps fill the context window in a few turns.
2. **Interactive Terminal Deadlocks**: Commands hang on unseen `stdin` prompts.
3. **Memory Drift**: External vector stores fall out of sync with git branches and rollbacks.
4. **Unverified Victory**: Agents declare work done without a checker or non-vacuous test receipt.

Our architecture separates **the stochastic semantic ALU** from **the deterministic toolchain**.

---

## 1. The Separation

```text
stochastic plane      the model (the ALU) and its context window (the registers)
                              |  forms in, receipts out
deterministic plane   the harness: tool routing, delimiter and name checks
                      staged edits and git, with the memory ledgers
                      process supervision: stdin firewall and idle watchdog
```

- **The LLM is an ALU**: The model's job is probabilistic reasoning and semantic code transformation under explicit constraints.
- **The Harness is the OS**: The harness controls process lifetimes, routes tools, validates delimiters, and isolates execution.
- **The Context Window is a register file, not a trash bin**: What enters it should be chosen, bounded, and replaceable.

Much of the deterministic plane already exists as tools. The `asl` agent plane reads a symbol or a bounded slice of a file (`(:read :file ... :symbol ...)`) instead of `cat`, stages edits in a session buffer (`(:edit ...)`, `(:diff)`) and writes them to disk only on `(:flush)`, and resolves names, arity and enum coverage before anything runs (`asl check FILE`, also run by `(:check)`). The rest of this post describes the parts we are still building.

---

## 2. A Slotted Context: Our Design Target

We are building the harness to partition the prompt into four registers:

| Slot | Name | Description | Retention |
|---|---|---|---|
| **Slot 1** | **Invariants** | Rules, root constraints, safety boundaries | Permanent across session |
| **Slot 2** | **Receipts Ledger** | One-line records of past actions and verifications | Compact log (`:receipt ...`) |
| **Slot 3** | **Pinned Domain Slot** | Library interfaces, type stubs, and API signatures | Loaded per step, dropped after |
| **Slot 4** | **Working Frame** | Current task and the slice of code being edited | Active turn |

The lifecycle we want for external knowledge: load the verified signatures of a library into Slot 3, let the model write against them, then drop the slot and keep only a one-line receipt:

```lisp
(:receipt :target "zod@3.22.4" :action "validated-schema" :anchor "auth.asl#validateUser")
```

This is direction, not a measured result. We have not yet run a controlled comparison of context size or token budget with and without slotting, so we make no savings claim here.

---

## 3. Git-Native, Line-Oriented State

Traditional agent state engines rely on SQLite databases, Redis caches, or cloud vector endpoints. When multiple agents collaborate across Git branches, binary files collide.

Our working memory is plain ASN text in a memory directory of the workspace (ledgers for intent, roadmap, principles, notes, known-red suites and dated work), versioned with the code. The `(:mem)` op lists, queries and stages changes to those row-keyed ledgers, and `(:note)` records and lists observations in the notes ledger.

The property we rely on is that a record is one self-contained line, so additions from parallel branches merge as line additions:

```lisp
(:edge :src "sym:store/dot" :dst "req:simdVector" :rel :fulfills)
(:edge :src "sym:paged/slab" :dst "dec:sq8Quant" :rel :governedBy)
```

Code and the facts about it commit together in one Git commit. A relational graph of use cases, requirements and edges in this form is a target; today the ledgers are flat files.

---

## 4. The Idle Watchdog

Terminal commands executed by agents frequently hang when an interactive prompt waits for input.

The process package `asl-proc` handles this in ASL (`packages/asl-proc/src/core/process.asl`):
1. **STDIN Firewall**: the command builder redirects standard input from `/dev/null` unless input is supplied, and a timeout wraps the command in a watchdog that kills it and exits 124.
2. **Idle Watchdog**: a session tracks milliseconds since the last stdout, stderr or stdin event; any event resets it.
3. **Escalation**: `sessionStepDeadline!` moves a silent session to SIGTERM at 10 s and SIGKILL at 12 s, and records a receipt with the signal (as exit code -15 or -9) and a summary line.

The model then sees a structured receipt instead of a frozen terminal and can re-run with non-interactive flags (e.g. `-y`).

The module loads, and its suites pass there (on 2026-10-14: `processTest.asl` 47 passed checks, `sessionTest.asl` 30, and `rpcProcTest.asl` 42, which steps a session through the deadline). The escalation is a session model stepped by elapsed time, not yet a guarantee for every command the agent plane runs.

---

## 5. What We Have Not Measured

An earlier version of this post carried a solve-rate table comparing a 31B model and a 3B model inside this harness with a frontier model in a raw shell. No run, lock or result file backs those numbers, so we removed them. A solve-rate comparison will be published from recorded runs, with its method, scope and date, or not at all.

---

## 6. Conclusion

Our working hypothesis is that much of what makes autonomous software engineering unreliable is an **operating system architecture problem**, not only a model capability problem.

When models are relieved of bookkeeping, file traversal, and unconstrained shell execution, and instead work through bounded reads, staged edits, checks that run before code does, and process supervision, the remaining failures are the ones worth a model's attention. That claim is testable, and recorded runs are how we intend to test it.

- Explore [The Agent Operational Circle](/blog/the-agent-operational-circle).
