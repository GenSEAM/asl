# AgentScript (ASL)

A programming language and data notation written by models, for models. Site: [aslang.dev](https://aslang.dev) · LLM entry: [`llms.txt`](llms.txt).

- **ASL** (`.asl`) is the language; **ASN** (`.asn`) is its data notation. Both are S-expressions: structure lives in balanced parentheses, keys are bare, whitespace carries no meaning inside a form.
- There is no nil, exception or `try`. Fallible operations return `(some v)` / `(none)` or `(ok v)` / `(err e)` and are taken apart with `mt`. Names are camelCase; predicates end in `?`.

```asl
(module demo/shapes :x [area runTests])

enum Shape (circle r: Int64) (square side: Int64)

fn area s: Shape -> Int64
  (mt s ((circle r) (* 3 (* r r))) ((square a) (* a a)))

fn runTests -> Bool
  (do (assert (= (area (square 3)) 9) "square") (assert (= (area (circle 1)) 3) "circle") true)
```

## Install

From a checkout (needs a C compiler):

```sh
sh host/build.sh                         # builds host/out/asl-host
host/out/asl-host check file.asl         # names, arity, types, exhaustive matches
host/out/asl-host test fileTest.asl      # runs runTests, counts executed assertions
host/out/asl-host run file.asl ARGS      # runs main
host/out/asl-host build file.asl -o out  # one executable with the modules embedded
```

Installer: [`scripts/install.sh`](scripts/install.sh) (`scripts/install.ps1` on Windows); the site serves the same script:

```sh
curl -fsSL https://aslang.dev/install.sh | sh
```

## Layout

| Path | Contents |
| :--- | :--- |
| `host/` | the C host (reader, checker, evaluator, runtime) and `host/build.sh` |
| `prelude/` | the prelude every program loads |
| `grammar/` | grammar, lexicon, rules and capability ledgers (ASN) |
| `packages/` | 70 packages, e.g. `asl-parser`, `asl-checker`, `asl-compiler`, `asl-target-llvm`, `asl-proc`, `asl-gateway`, `asl-agent`, `asl-mem`, `asl-search`; tests live in each package's `tests/` |
| `apps/harness/` | the agent harness (calibration data and results are not published) |
| `agentLoop/` | the self-hosted agent loop |
| `web/` | the aslang.dev site (Vite, Cloudflare Pages) |
| `tools/`, `bin/`, `backend/`, `bench/`, `examples/` | developer tools, launchers, backend, benchmarks, examples |
| `docs/` | specifications (`asnSpec.md`, `agenticProtocol.md`, ...) and `manifesto.md` |

## Status

Early. `asl-host` checks, tests, runs and builds programs; the self-hosted compiler and the LLVM target are in progress in `packages/`. Interfaces change without notice.

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE).
