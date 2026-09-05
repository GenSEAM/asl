# Phase 3: `asl-native-compiler-wire` Plan

## Objective
Wire the end-to-end self-hosted compiler in `packages/asl-compiler/src/compiler.asl` to support multi-target emission (`rust`, `c-embedded`, `wasi`) and module linking.

## Work Items
1. Add target selection parameter to `compile-source` (`:trg rust`, `:trg c-embedded`).
2. Integrate `asl-codegen/emit-c` into `compile-source` when target is `c-embedded`.
3. Unit test in `packages/asl-compiler/tests/compiler-test.asl`.

## Acceptance Gate
`node asl/bin/asl gate asl/packages/asl-compiler/src/compiler.asl`
