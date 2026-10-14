# asl-target-js

JavaScript backend for ASL. It lowers the same linked, verified `asl-ir` SSA module that
`asl-target-llvm` lowers for native code and wasm32, and emits one self-contained ES module:
the runtime, the string pool, one function per SSA function, and an export for every function
of the entry module under its ASL name.

```sh
# from the directory that holds the asl checkout
asl/host/out/asl-host run <driver.asl>   # a driver calls (asl-target-js/main compileEntry! "asl/path/entry.asl")
```

## Semantics

- `Int` is `BigInt`; `+ - *` trap with `ERR_INT_OVERFLOW` outside int64, `/` and `mod` floor and
  trap with `ERR_DIV_ZERO`, as on the host.
- Strings keep ASL's UTF-8 byte semantics (`stringLength`, `stringSlice`, `stringIndexOf` count
  bytes). A slice that is not valid UTF-8 is kept as raw bytes; printing it decodes with U+FFFD,
  where the host writes the raw bytes.
- `str` and `print` format values exactly like the host.
- Self tail calls (directly or through join blocks) run as loops, so the prelude's recursive
  loops do not grow the stack. Other deep non-tail recursion is bounded by the JS stack.
- Clocks work (`nowNs`, `monotonicNs`); files, processes, sockets and the environment are
  `ERR_CAPABILITY_ABSENT` at compile time.

## TypeScript

`compileWithTypes!` returns the module and its declarations (`.d.mts`), generated from the entry
module's signatures: `Int` is `bigint`, a schema a readonly interface, an enum a union tagged by
variant name, type variables generics, and `List`/`Option`/`Result`/`Pair`/`Map` the runtime's
shapes (`AslList`, `AslOption`, ...). The module also exports `asl`, typed constructors for values a
TypeScript caller passes in (`asl.list`, `asl.some`, `asl.record`, `asl.variant`, ...), and
`counts`, the assertions run so far, so ASL test suites can run under node.

```sh
ENTRY=asl/path/entry.asl OUT=/tmp/entry.mjs asl/host/out/asl-host run asl/web/tools/jsc.asl   # writes entry.mjs and entry.d.mts
```

## Exports

`src/main.asl`: `compileEntry!`, `compileWithTypes!`, `diagText`. `src/dts.asl`: `emitDts`, `tsType`. `src/emit.asl`: `emitJsModule`, `jsIdent`,
`jsString`, `supportedBuiltins`. `src/runtime.asl`: `runtimeText`, `builtinNames`, `entryNames`.

## Tests

- `tests/emitJsTest.asl` (asl-host, needs node): 12 fixtures compiled to JS and run under node
  print the same bytes, exit with the same code and trap with the same error code as
  `asl-host run`; asl-html's three suites pass under node with the host's assertion counts. 85
  assertions pass (2026-10-14).
- `tests/dtsTest.asl` (asl-host; the TypeScript half needs tsc): declarations for a typed fixture;
  a consumer passes `tsc --strict` and runs, a misuse fails `tsc`. 14 assertions pass.
