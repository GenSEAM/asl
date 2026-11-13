# ASL Manifesto

> **"LLM first."**

AgentSlang (ASL) is a harness, a toolbelt and a language for software written by language models. The problem it is built against: **a model hallucinates when its attention is short or spread thin.** Noisy context, ambiguous structure, contradictory instructions and lost state all dilute attention.

The pillars are ordered by the evidence behind them (2026-11-13).

---

## 1. Non-restrictive harness

Constraints belong in the program and the environment, not in the prompt.

- **Enforce, don't instruct.** Permissions, sandboxes, file ownership, checkers and gates make the wrong action impossible or visible; a prompt full of prohibitions competes with the task for attention.
- **A gate counts only after it has failed**: red before the change, green after it, red on revert.
- **Separated duties.** A writer does not grade its own work.
- **No roles.** A persona is a bias, not a capability.

## 2. Agent-assistive tools

- read by symbol and slice, batch independent operations, stage edits and flush them as one transaction;
- typed, compact receipts that say what to do next;
- memory kept outside the context, so focus survives long tasks and compaction;
- every claim tied to a check that ran, with its exit code and executed assertions.

These work on any git repository; no one has to adopt the language first.

## 3. LLM-first language: a bet, not yet a result

Balanced delimiters carry structure, names are whole words, one notation (ASN) serves code, data and messages, and nothing fails silently: no null, no exceptions, no truthiness.

- **Untested:** whether models write ASL as reliably as Python or TypeScript. No baseline arm has run; [`EXPERIMENT.md`](EXPERIMENT.md) is the protocol.
- **Measured:** token savings hold against pretty-printed JSON only; against minified JSON, ASN is within about 10%, and ASL code costs about 1.3 to 1.8 times the tokens of typed Python (tiktoken o200k, audit of 2026-11-13; see [`README.md`](README.md)).
- **Open:** the function header is a bare column-0 line with an indented body, the one whitespace-significant construct and the dominant generation failure. It is an arm of the experiment.

## 4. Infrastructure SEAM: a direction

- **Real:** the compiler is written in ASL and compiles itself through LLVM IR to native code and WebAssembly; there is no C host.
- **Missing:** foreign functions, package fetching, executed SQL ([`ROADMAP.md`](ROADMAP.md)).

## Scope

Core: parser, checker, IR, LLVM target, CLI and toolbelt, gates, gateway, agent loop. Everything else under `packages/` is experimental until a tier manifest says otherwise. Published figures and their status are in [`bench/publishedClaims.asn`](bench/publishedClaims.asn); capabilities, including the ones that lie, in [`grammar/capabilities.asn`](grammar/capabilities.asn).
