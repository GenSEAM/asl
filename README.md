<div align="center">

<img src="assets/logo.svg" alt="AgentScript Chameleon Logo" width="100" height="100" />

# AgentScript (ASL)
### *A language and data notation written by models, for models.*

[Website](https://aslang.dev) · [LLM entry (llms.txt)](llms.txt)

</div>

---

AgentScript is two things:

- **ASL, the language.** Source (`.asl`) and data (`.asn`) files are S-expressions with balanced parentheses. A malformed program is caught by counting delimiters rather than by running it, and whitespace carries no meaning inside a form.
- **`asl`, the toolbelt.** `asl '<form> <form> ...'` reads, searches and edits files in a git repository; the forms of one call run as one batch, and edits are staged, inspected with `(:diff)`, then flushed or discarded.

Status: early. The stage-0 C host (`host/out/asl-host`) checks and runs programs; `asl build` returns `ERR_UNIMPLEMENTED` and produces no artifact until phase R1. Compiling to WebAssembly or C, and a differential gate across backends, are targets.

## Why

Languages and formats built for human typists cost a model in two places:

- **Whitespace-significant syntax** (Python, YAML): a misplaced indent is a syntax error found only when the file is loaded.
- **JSON tool calls**: quoted keys, colons and commas are paid for on every object before the model starts reasoning.

ASL keeps structure in delimiters and keys bare. The same command, counted with `cl100k_base` (tiktoken, 2026-09-24; the untracked `bench/token_frames.lock` records the same counts):

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

| Frame | `cl100k_base` tokens |
|---|---|
| JSON | 51 |
| positional frame | **18** |

This is one example, not a benchmark. The `(! ...)` sigil frame is the target wire of [`docs/agenticProtocol.md`](docs/agenticProtocol.md); what runs today is described there.

## The language in one example

```asl
(module demo/shapes :d "Areas of shapes" :x [area runTests])

enum Shape (circle r: Int64) (square side: Int64)

fn area s: Shape -> Int64
  (mt s ((circle r) (* 3 (* r r))) ((square a) (* a a)))

fn runTests -> Bool
  (do (assert (= (area (square 3)) 9) "square") (assert (= (area (circle 1)) 3) "circle") true)
```

A function header is a bare column-0 line; its body is indented below. There is no nil, exception or `try`: fallible builtins return `(some v)`/`(none)` or `(err e)`, taken apart with `mt`. User and builtin names are camelCase, predicates end in `?` (`listLength`, `stringContains?`). The full rules are in [`llms.txt`](llms.txt).

## Quickstart

```sh
curl -fsSL https://aslang.dev/install.sh | bash   # installer source: dist/install.sh
asl version
asl check file.asl                  # delimiter balance (asl-core)
asl test fileTest.asl               # run a suite on asl-core, which is lenient
host/out/asl-host check file.asl    # strict: names, arity, enums
host/out/asl-host test fileTest.asl # strict runner
asl '(:tools)'                      # the agent-plane operation catalogue
```

`asl test` runs asl-core, which reads 0 as true, treats unknown names as data and passes a `runTests` that returns false; `asl-host` is the reference.

## Packages

`packages/` holds 46 packages. A few, by their manifests:

| Package | Description |
| :--- | :--- |
| [`asl-parser`](packages/asl-parser/) | Lexer, reader and AST parser |
| [`asl-checker`](packages/asl-checker/) | Semantic type checker |
| [`asl-transpile`](packages/asl-transpile/) | ASN reader and checker, formatters for YAML, TOML, CSV, SVG, CSS, shell |
| [`asl-proc`](packages/asl-proc/) | Child processes, pipes, stream redirection, resource guards |
| [`asl-vdom`](packages/asl-vdom/) | Virtual DOM and component source generators |
| [`asl-gates`](packages/asl-gates/) | Gate runners and audit engine |
| [`asl-lint`](packages/asl-lint/) | Quality and anti-pattern analysis |
| [`asl-codegen`](packages/asl-codegen/), [`asl-target-*`](packages/) | Code generators; not wired to `asl build` yet |
| [`asl-contracts`](packages/asl-contracts/) | Contract specs, staging and the tool plane |

Each package README lists what its `src/` exports and which runner its tests pass on.

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE).
