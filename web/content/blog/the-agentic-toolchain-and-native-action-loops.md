# Why Bash Wrappers Fail Coding Agents: Action Loops and Checks That Run Before Code Does
*By GenSEAM | September 2026*

When building developer tools, compilers, and harnesses for autonomous software engineering agents, the prevailing industry approach is wrapping standard command-line tools in raw bash subprocesses.

The agent is given a shell prompt and asked to navigate multi-file repositories using tools designed for humans: `cat`, `grep`, `npm test`, `cargo build`, and interactive prompts. When a command fails, thousands of lines of unformatted compiler output flood the context window, and the agent is left to guess how to proceed.

The result is operational fragility:
1. **Interactive Deadlocks**: Commands freeze when waiting for unseen `stdin` prompts (`[y/N]`, sudo, or pagers like `less`).
2. **Subshell Ephemerality**: Directory changes (`cd`) and environment exports (`export VAR=val`) disappear between turns, so agents repeat failed setup steps.
3. **Foreign Dependency Drift**: Multi-language projects break when host environments drift across Python, Node, Rust, or C toolchains.
4. **Weak Feedback Loops**: A check that passes when it should fail teaches the agent to declare success.

Tools for agents should match how language models operate. This post describes the loop we are building for AgentScript (ASL), the checks that already exist, and the parts that are still design.

---

## 1. The Action-Observation Loop

Human engineers use a terminal as an interactive loop with visual inspection. Coding agents work in discrete turns of action and observation. The loop, one turn per line:

```text
agent  -> (:read :file "core/auth.asl" :symbol "login")
asl    <- the symbol, or a bounded slice, not the whole file
agent  -> (:edit :file "core/auth.asl" :old "..." :new "...")
asl    <- staged in the session buffer; (:diff) shows it
agent  -> (:check :file "core/auth.asl")
asl    <- ok, or ERR_UNKNOWN_SYMBOL / ERR_ARITY / ERR_MATCH_NONEXHAUSTIVE with line and column
agent  -> (:flush)
agent  -> asl-host test tests/authTest.asl
asl    <- "N assertion(s) executed (N passed)", exit 0
```

### Operational Properties
1. **Bounded reads**: `(:read)` returns a symbol or a bounded slice; `(:intel :op outline :file "...")`, or `asl intel outline FILE`, lists a module's items with their kind, signature and export flag without loading bodies.
2. **Staged edits**: `(:edit)` and `(:write)` stage changes in a session buffer outside the working tree; `(:diff)`, `(:check)` and `(:test)` see the staged content; `(:flush)` writes it to disk and `(:discard)` drops it. `(:txn ...)` stages, checks and flushes in one call and restores every touched file when a step fails.
3. **Non-interactive execution** (partly built): the process package `asl-proc` redirects standard input from `/dev/null` unless input is supplied, and a timeout wraps the command so it is killed and exits 124. Its session model tracks idle time and steps to SIGTERM after 10 s of silence and SIGKILL after 12 s, recording a receipt. The module loads on the stage-0 host and its suites pass there (`processTest.asl`, `sessionTest.asl`, `rpcProcTest.asl`). Persisting working directory and environment across turns is still a target.

---

## 2. Checks That Fail on the Claim

A check is only useful to an agent if it fails when the code is wrong. The reference is the stage-0 host (`host/out/asl-host`), and `asl check` and `asl test` on an `.asl` file run on it. It resolves every name before anything runs:

- an unknown symbol is `ERR_UNKNOWN_SYMBOL`, a wrong argument count `ERR_ARITY`, a mismatched argument type `ERR_TYPE_MISMATCH`, and an `mt` that misses an enum case `ERR_MATCH_NONEXHAUSTIVE`, each with line and column;
- a function that calls an effectful builtin without being marked is `ERR_EFFECT_UNMARKED`;
- a test passes only when the exported `runTests` returns `true` after at least one assertion executed. A suite with zero assertions fails (`ERR_TEST_FAILED: zero assertions executed`), and `(assert true ...)` is rejected at load as `ERR_CONSTANT_ASSERT`.

A concrete example: a file with a top-level `(defun double [x] (* x 2))` fails `asl-host check` with `ERR_UNSUPPORTED_TOPLEVEL list-form (defun ...) at top level` and exit 1. `lambda` is accepted as an anonymous `fn`.

An earlier toolchain engine, asl-core, verified delimiter balance only and passed suites that it should have failed. It is retired: the rule for agents is to check and test with the host.

---

## 3. The Gate Suite

Workspace-level verification runs through `asl audit gates`. With `--static` it runs the static checks only and reports the suites as not run. Otherwise it runs the static checks plus the suites affected since the last verified fully green commit; when there is no such base it asks for `--full`, which runs every suite. The checks are written in ASL in `packages/asl-gates` and include:

| Check | What it verifies |
| :--- | :--- |
| `gate1Manifests` | package manifests |
| `gate2Syntax` | delimiter balance across source files |
| `gate3Grounding` | the published-claims registry (`bench/publishedClaims.asn`) |
| `gate4Foreign` | foreign-language files against an allowlist |
| `gate6GrammarCount` | grammar registry shape |
| `gate7Skill`, `gate7Rules`, `gate7Installer` | skills, rendered rules, and installer identity |

A failing suite is red unless it is listed in the known-red ledger. A green banner is not by itself evidence; we treat a gate as real only when a seeded defect makes it fail.

`asl gate` and `asl lint` are retired commands: they print a pointer to `asl audit gates` and `asl check` instead of running anything.

---

## 4. Coverage

An earlier version of this post claimed 100 percent function coverage across the packages. No coverage command or measurement exists, so the claim is withdrawn. The nearest real tool is `(:intel :op vacuity)` (`asl intel vacuity`), which scans test files for suites that return without executing an assertion. Function-level coverage is a target.

---

## 5. One Language in the Packages

A repository that mixes Python test scripts, TypeScript transpilers, Rust binaries, and Bash glue asks an agent to master several package managers, build systems, and diagnostic formats.

Inside `packages/`, the source directories are ASL: on 2026-10-14, of the 720 git-tracked files under `packages/*/src`, 718 are `.asl` and one is `.asn`; the exception is the browser plugin's `popup.html`. Tests and fixtures carry some data files. The stage-0 host that runs all of this is C by design, and the native self-hosted compiler is still in progress.

The benefit we are after:
1. **One cognitive domain**: the agent reads and writes one syntax.
2. **No dependency breakage**: a package with no `node_modules` or virtualenv has nothing to drift.

---

## 6. The Toolbelt

| Command | Purpose |
| :--- | :--- |
| `host/out/asl-host check <file>` | Resolve names, arity, types, enum coverage and effect marks before running. |
| `host/out/asl-host test <file>` | Strict test runner: `runTests` must return `true` after at least one assertion. |
| `asl check <file>` | Delimiter balance, then the host check for an `.asl` file. |
| `asl test <file>` | The host test runner. |
| `asl intel outline <file>` | Items and signatures of a module without bodies. |
| `asl audit gates --full` | The workspace gate suite; `--static` skips the suites. |
| `asl '(:read ...)' '(:edit ...)' '(:flush)'` | Bounded reads and staged edits on the agent plane; `asl '(:tools)'` lists every op. |

---

## 7. Conclusion

Autonomous coding is not only about model weights or prompts; it is about **tooling architecture**. The parts that help most are the plain ones: bounded reads, staged edits, and checks that fail on the claim. The parts that look like help but are not, such as a gate that always passes, are worse than no gate at all, because the agent trusts them.

- Learn about token ergonomics in [The Token-Density Fallacy](/blog/the-token-density-fallacy-and-machine-understandability).
- Run the strict checks: `host/out/asl-host check <file>` and `asl audit gates --full`.
