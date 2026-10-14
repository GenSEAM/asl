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

## Exports

`src/main.asl`: `compileEntry!`, `diagText`. `src/emit.asl`: `emitJsModule`, `jsIdent`,
`jsString`, `supportedBuiltins`. `src/runtime.asl`: `runtimeText`, `builtinNames`, `entryNames`.

## Tests

`tests/emitJsTest.asl` (asl-host, needs node on PATH): 12 fixtures compiled to JS and run under
node must print the same bytes, exit with the same code and trap with the same error code as
`asl-host run`. 75 assertions pass (2026-10-14).
