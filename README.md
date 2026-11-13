<div align="center">

<img src="assets/logo.svg" alt="AgentSlang Chameleon Logo" width="100" height="100" />

# AgentSlang (ASL)
### *A harness, a toolbelt and a language for software written by models.*

[Website](https://aslang.dev) · [LLM entry (llms.txt)](llms.txt)

</div>

---

AgentSlang is three things, in the order the evidence supports them:

- **A harness doctrine.** Constraints are enforced by the environment (ownership, checkers, gates that were red before they were green, a grader that is not the writer), not listed in the prompt. See [`MANIFESTO.md`](MANIFESTO.md).
- **`asl`, the toolbelt.** `asl '<form> <form> ...'` reads, searches and edits files in any git repository; the forms of one call run as one batch, and edits are staged, inspected with `(:diff)`, then flushed or discarded.
- **ASL, the language.** Source (`.asl`) and data (`.asn`) files are S-expressions with balanced delimiters. Whether models write it as reliably as a mainstream language is untested (see below).

## Status (2026-11-13)

Pre-release; build from a checkout.

- **Self-hosted.** The compiler (`asl1`) is written in ASL and compiles itself through LLVM IR (`asl-target-llvm`). The C host interpreter was deleted on 2026-10-13; `host/` holds a build script and tests, no C. The runtime archive `libaslrt.a` is ASL lowered to LLVM IR and compiled by clang.
- **Targets that ship:** native code and `wasm32-unknown-unknown`, both through LLVM. [aslang.dev](https://aslang.dev) is built that way from [`web/`](web/).
- **Seeds** are tracked for `arm64-apple-darwin`, `x86_64-unknown-linux-gnu` and `aarch64-unknown-linux-gnu` ([`seed/seed.asn`](seed/seed.asn)). The gates are run on macOS; Linux is not gated yet.
- **Experimental:** `asl-target-js` and `asl-html` produce runnable output on their fixtures; the Python, Go, Swift, C, shell and WAT targets are prototypes or frozen. Foreign functions, package fetching and releases are missing ([`ROADMAP.md`](ROADMAP.md)).
- What works, is partial, is absent or lies is listed per capability in [`grammar/capabilities.asn`](grammar/capabilities.asn).

## What is measured and what is not

Every figure the project publishes is listed with its status in [`bench/publishedClaims.asn`](bench/publishedClaims.asn). The figures below were counted with tiktoken 0.12.0 by an independent audit of this tree on 2026-11-13; the audit record lives in the workspace ledger, not in this repository.

**Generation correctness: untested.** No experiment has compared models writing ASL with models writing Python or TypeScript. The only data has no comparator arm: on one family of one-line arithmetic tasks, 145 of 462 raw generations passed (31%) and 420 after a mechanical heal pass (`packages/asl-forms`, heal), 2026-10-15. The protocol that would settle it is [`EXPERIMENT.md`](EXPERIMENT.md); it has not been run.

**Tokens: the saving is against pretty-printed JSON.** One tool call, five encodings:

```json
{
  "action": "execute_command",
  "payload": {
    "binary": "git",
    "arguments": ["status", "--short"],
    "working_dir": "/app",
    "timeout_ms": 5000
  }
}
```

```agp
(! cmd "git" ["status" "--short"] "/app" 5000)
```

| Encoding | `cl100k_base` | `o200k_base` |
|---|---|---|
| JSON, keyed, pretty-printed (above) | 51 | 51 |
| JSON, keyed, minified | 30 | 32 |
| ASN, keyed frame | 28 | 28 |
| ASL positional frame (above) | 18 | 18 |
| JSON positional array `["cmd","git",["status","--short"],"/app",5000]` | 17 | 17 |

The 51 to 18 drop comes from removing whitespace and keys, which JSON can do too; it is one example, not a benchmark. On data, keyed ASN was 9% to 17% larger than minified JSON on a 100-record fixture and 0.46% smaller on 7190 real receipts; on tables, columnar JSON and CSV are cheaper than ASN rows. On code, ASL costs about 1.3 to 1.8 times the tokens of typed Python (1.84 over 9 module pairs, `o200k_base`, 2026-10-09) and is cheaper only on sum types with pattern matching (0.88 on the example below). The Python sides were not executed against the ASL tests.

The `(! ...)` sigil frame is the target wire of [`docs/agenticProtocol.md`](docs/agenticProtocol.md); what runs today is described there.

## The language in one example

```asl
(module demo/shapes :x [area runTests])

enum Shape (circle r: Int64) (square side: Int64)

fn area s: Shape -> Int64
  (match s ((circle r) (* 3 (* r r))) ((square a) (* a a)))

fn runTests -> Bool
  (do (assert (= (area (square 3)) 9) "square") (assert (= (area (circle 1)) 3) "circle") true)
```

A function header is a bare column-0 line with its body indented below: the one place where layout matters, and the most common generation failure in the data above (all 38 programs the heal pass could not repair lacked it). Whether to accept a parenthesised `(fn ...)` form is an arm of [`EXPERIMENT.md`](EXPERIMENT.md). Inside a form whitespace carries no meaning. There is no nil, exception or `try`: fallible builtins return `(some v)`/`(none)` or `(err e)`, taken apart with `match`. User and builtin names are camelCase, predicates end in `?` (`listLength`, `stringContains?`). The full rules are in [`llms.txt`](llms.txt).

## Quickstart

There are no prebuilt binaries in this repository. From a checkout, with clang:

```sh
CC=$(command -v clang) sh host/build.sh   # builds host/out/libaslrt.a and the native CLI from seed/<triple>
bin/asl version                           # put bin/ on PATH
bin/asl check file.asl                    # balance, then names, arity, enums, types
bin/asl test fileTest.asl                 # run a suite; it fails when an assertion fails
bin/asl build file.asl -o out             # native binary
bin/asl '(:tools)'                        # the agent-plane operation catalogue; also bin/asl -f FILE and bin/asl - (forms on stdin)
```

`bin/asl` is a launcher that execs the native CLI and rebuilds it when its sources change. `(...)` forms, `-f FILE` and `-` go to the toolbelt (`packages/asl-forms`), `asl intel ...` to `packages/asl-intel`, everything else to the CLI (`packages/asl-cli`). It works from a plain clone; inside the larger workspace the same paths resolve under `asl/`. `asl help` lists the CLI commands; `asl gate`, `asl lint`, `asl mem` and `asl tool` are retired and answer ERR_RETIRED.

## Packages

`packages/` holds 69 directories (`ls packages | wc -l`, 2026-11-13). They are not equal: the core below carries the self-hosted toolchain and the harness; most of the rest are experiments or declarations with little code, and no tier manifest exists yet.

| Core package | Description |
| :--- | :--- |
| [`asl-parser`](packages/asl-parser/) | Lexer, reader and AST parser |
| [`asl-checker`](packages/asl-checker/) | Semantic type checker |
| [`asl-ir`](packages/asl-ir/) | Typed intermediate representation |
| [`asl-target-llvm`](packages/asl-target-llvm/) | LLVM IR backend: native code and wasm |
| [`asl-cli`](packages/asl-cli/), [`asl-forms`](packages/asl-forms/), [`asl-intel`](packages/asl-intel/) | CLI, agent-plane toolbelt, code intelligence |
| [`asl-gates`](packages/asl-gates/) | Gate runners and audit engine |
| [`asl-gateway`](packages/asl-gateway/) | Model gateway: routing, limits, usage ledger |
| [`asl-agent`](packages/asl-agent/) | Leon, the agent loop |

Every package has a `manifest.asn`.

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE).
