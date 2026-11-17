# Batch Tool Calls and Staged Transactions: Why Agents Need More Than a Bash Wrapper
*By GenSEAM | September 2026*

Give an agent the `asl` toolbelt and its action loop changes shape: instead of firing a dozen fragile shell commands one turn at a time, it sends a batch of S-expression forms—`(:query ...) (:read ...) (:edit ...) (:check ...)`—in one call and gets back one structured `(:batch ...)` of receipts. Edits sit in a session-isolated staging buffer until the checker passes and `(:flush)` writes them atomically, or `(:txn ...)` wraps the whole sequence with automatic rollback.

By contrast, the default industry harness wraps human command-line tools in raw bash subprocesses (`cat`, `grep`, `sed`, interactive build tools) and dumps thousands of lines of raw terminal output back into the prompt. That creates four recurring failure modes:
1. **Interactive Deadlocks**: Commands freeze waiting on unseen `stdin` prompts (`[y/N]`, pagers).
2. **Subshell Ephemerality**: Working directory and state vanish between turns.
3. **Blind Text Rewrites**: `sed` and line-number patches corrupt files when lines shift.
4. **Weak Feedback Loops**: Unstructured exit output hides whether a check actually verified the change.

This post describes the loop we are building for AgentSlang (ASL), the checks that already exist, and the parts that are still design.

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
agent  -> asl test tests/authTest.asl
asl    <- "N assertion(s) executed (N passed)", exit 0
```

### Operational Properties
1. **Bounded reads**: `(:read)` returns a symbol or a bounded slice; `(:intel :op outline :file "...")`, or `asl intel outline FILE`, lists a module's items with their kind, signature and export flag without loading bodies.
2. **Staged edits**: `(:edit)` and `(:write)` stage changes in a session buffer outside the working tree; `(:diff)`, `(:check)` and `(:test)` see the staged content; `(:flush)` writes it to disk and `(:discard)` drops it. `(:txn ...)` stages, checks and flushes in one call and restores every touched file when a step fails.
3. **Non-interactive execution** (partly built): the process package `asl-proc` redirects standard input from `/dev/null` unless input is supplied, and a timeout wraps the command so it is killed and exits 124. Its session model tracks idle time and steps to SIGTERM after 10 s of silence and SIGKILL after 12 s, recording a receipt. The module loads and its suites pass (`processTest.asl`, `sessionTest.asl`, `rpcProcTest.asl`). Persisting working directory and environment across turns is still a target.

---

## 2. Checks That Fail on the Claim

A check is only useful to an agent if it fails when the code is wrong. The reference is the `asl` CLI: `asl check` and `asl test` on an `.asl` file. The checker resolves every name before anything runs:

- an unknown symbol is `ERR_UNKNOWN_SYMBOL`, a wrong argument count `ERR_ARITY`, a mismatched argument type `ERR_TYPE_MISMATCH`, and a `match` that misses an enum case `ERR_MATCH_NONEXHAUSTIVE`, each with line and column;
- a function that calls an effectful builtin without being marked is `ERR_EFFECT_UNMARKED`;
- a test passes only when the exported `runTests` returns `true` after at least one assertion executed. A suite with zero assertions fails (`ERR_TEST_FAILED: zero assertions executed`), and `(assert true ...)` is rejected at load as `ERR_CONSTANT_ASSERT`.

A concrete example: a file with a top-level `(defun double [x] (* x 2))` fails `asl check` with `ERR_UNSUPPORTED_TOPLEVEL list-form (defun ...) at top level` and exit 1. `lambda` is accepted as an anonymous `fn`.

An earlier toolchain engine verified delimiter balance only and passed suites that it should have failed. It has been retired: the rule for agents is to check and test with `asl check` and `asl test`.

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

Inside `packages/`, the source directories are ASL: on 2026-10-14, of the 720 git-tracked files under `packages/*/src`, 718 are `.asl` and one is `.asn`; the exception is the browser plugin's `popup.html`. Tests and fixtures carry some data files. The compiler is itself written in ASL and compiles itself through LLVM IR; that self-compile is gated on macOS only.

The benefit we are after:
1. **One cognitive domain**: the agent reads and writes one syntax.
2. **No dependency breakage**: a package with no `node_modules` or virtualenv has nothing to drift.

---

## 6. The Toolbelt

| Command | Purpose |
| :--- | :--- |
| `asl check <file>` | Resolve names, arity, types, enum coverage and effect marks before running. |
| `asl test <file>` | Strict test runner: `runTests` must return `true` after at least one assertion. |
| `asl intel outline <file>` | Items and signatures of a module without bodies. |
| `asl audit gates --full` | The workspace gate suite; `--static` skips the suites. |
| `asl '(:read ...)' '(:edit ...)' '(:flush)'` | Bounded reads and staged edits on the agent plane; `asl '(:tools)'` lists every op. |

---

## 7. Conclusion

Autonomous coding is not only about model weights or prompts; it is about **tooling architecture**. The parts that help most are the plain ones: bounded reads, staged edits, and checks that fail on the claim. The parts that look like help but are not, such as a gate that always passes, are worse than no gate at all, because the agent trusts them.

- Learn about token ergonomics in [The Token-Density Fallacy](/blog/the-token-density-fallacy-and-machine-understandability).
- Run the strict checks: `asl check <file>` and `asl audit gates --full`.
