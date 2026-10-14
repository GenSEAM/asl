# asl-target-ts (superseded)

An AST-level TypeScript emitter. It translates one parsed module at a time, without the prelude
or the other modules it imports, and it produces invalid TypeScript on real multi-module
programs (a field named `tag` clashes with its discriminant, nested generic types break, a
constructor matched from another module never matches, `/` and `mod` truncate instead of
flooring). Its own suites still pass (`emitTsTest`, `emitTsRunTest`); `runParityTsTest` needs a
corpus from the parent monorepo.

TypeScript support is [`asl-target-js`](../asl-target-js/): JavaScript lowered from the linked
`asl-ir` module, byte-equal to the host on its fixtures, with `.d.mts` declarations generated from
the entry module's signatures and checked by `tsc --strict`.
