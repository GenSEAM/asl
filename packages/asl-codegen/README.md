# asl-codegen

ASL source generators that turn parsed ASL (the `asl-parser` AST, typed by `asl-checker`) into Rust, ISO C99 or embedded C text.

- Rust: `emit` (top-level forms, `emitRustProgram`), `expr` (expressions and patterns), `rtypes` (type mapping and derives), `mangle` (identifiers and module paths), `builtins` (builtin templates, `renderBuiltin`).
- ISO C99: `c99Emit` (translation unit, prototypes, `main` entry), `c99Expr` (expression lowering), `c99Type` (type mapping, Option/Result/Map typedefs), `c99Mangle` (C identifier hygiene).
- Embedded C: `emitC` (C and Arduino sketch headers, GPIO and delay calls, `emitCStandalone`).

These modules are libraries. `asl-compiler` calls `c99Emit` (`compileSourceToC99`, `targets.asl`); no command-line tool drives them, and `asl/host/out/asl-host build` does not use them (it embeds module sources in an executable linked against the host). The native and `wasm32` path is `asl-target-llvm`, not this package.

Module names use the prefix `asl-codegen/`; `manifest.asn` lists the same 10 modules. All 10 files in `src/` pass `asl/host/out/asl-host check` (2026-10-14). Two of the test files exercise other packages: `emitWatTest.asl` imports `asl-target-wat/emitWat` and `goCodegenTest.asl` imports `asl-target-go/emitGo`.

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 10 modules, 121 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `asl-codegen/builtins` (`src/builtins.asl`, 3): `builtinTemplate`, `renderTemplate`, `renderBuiltin`.
- `asl-codegen/c99Emit` (`src/c99Emit.asl`, 19): `emitCHeaderGuards`, `emitCStandardIncludes`, `emitCFunctionPrototype`, `emitCExternCWrapper`, `emitCFreestandingPreamble`, `emitCHostedPreamble`, `emitCHeaderFile`, `emitCSourceFile`, `emitCStandalone`, `emitCMainEntry`, `emitCMainEntryWithArgs`, `collectUniqueDefuns`, `assembleCModule`, `emitCFunctionDef`, `emitSchemaForwardDecl`, `emitEnumForwardDecl`, `collectFormsSchemas`, `collectFormsEnums`, and 1 more.
- `asl-codegen/c99Expr` (`src/c99Expr.asl`, 22): `LowerCtx`, `emptyLowerCtx`, `ctxWithVar`, `ctxVarType`, `lowerCExpr`, `lowerCAtom`, `lowerCLet`, `lowerCIf`, `lowerCCond`, `lowerCMatch`, `lowerCCall`, `lowerCFieldAccess`, `lowerCRecordInit`, `lowerCDo`, `wrapBlockWithReturn`, `isC99Keyword?`, `mangleCIdent`, `mangleCTypeName`, and 4 more.
- `asl-codegen/c99Mangle` (`src/c99Mangle.asl`, 8): `mangleCIdent`, `isC99Keyword?`, `mangleCTypeName`, `mangleCModulePrefix`, `pascalIdent`, `capitalizeSeg`, `sliceOr`, `isDigitLeading?`.
- `asl-codegen/c99Type` (`src/c99Type.asl`, 28): `c99PrimitiveType`, `c99TypeStr`, `emitCDefschema`, `emitCDefenum`, `emitCStringType`, `emitCOptionType`, `emitCSliceType`, `emitCPairType`, `emitCMapType`, `emitCResultType`, `emitResultConstructors`, `collectInsts`, `collectInstsFromAnnotation`, `emitInstTypedef`, `emitInstTypedefs`, `emitInstTypedefsFromUniq`, `emitInstForwardDecls`, `emitInstForwardDeclsFromUniq`, and 10 more.
- `asl-codegen/emit` (`src/emit.asl`, 7): `emitDefschema`, `emitDefenum`, `emitDefun`, `emitTopForms`, `emitRustProgram`, `mergeMaps`, `hasMainFn?`.
- `asl-codegen/emitC` (`src/emitC.asl`, 11): `emitCHeader`, `emitArduinoHeader`, `emitCType`, `emitCFn`, `emitArduinoSketch`, `formatGpioCall`, `formatDelayCall`, `emitCStandalone`, `emitCHeaderFile`, `emitCSourceFile`, `c99TypeStr`.
- `asl-codegen/expr` (`src/expr.asl`, 8): `emitExpr`, `emitAtom`, `emitPattern`, `emitBodySeq`, `isIdent?`, `cloneIfIdent`, `resolveQualifiedCase`, `sliceStrOr`.
- `asl-codegen/mangle` (`src/mangle.asl`, 7): `mangleIdent`, `pascalIdent`, `rustModName`, `shortModName`, `capitalizeSeg`, `isRustKeyword?`, `sliceOr`.
- `asl-codegen/rtypes` (`src/rtypes.asl`, 8): `primitiveRustType`, `emitType`, `emitTypeStr`, `typeMentionsIoError?`, `typeMentionsFloat?`, `emitDerives`, `anyTrue?`, `boxedTypeIfRecursive`.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-codegen/tests/<file>.asl
```

13 of 14 test files exit 0 (498 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `builtinsTest.asl` | pass | 7 assertions |
| `c99EmitTest.asl` | pass | 41 assertions, 11 refutations |
| `c99ExprLoweringTest.asl` | **fail** | spawns `bin/asl`, which does not exist |
| `c99ExprTest.asl` | pass | 47 assertions, 29 refutations |
| `c99IntegrationTest.asl` | pass | 23 assertions, 13 refutations |
| `c99MangleTest.asl` | pass | 77 assertions |
| `c99TypeTest.asl` | pass | 77 assertions, 15 refutations |
| `cCodegenTest.asl` | pass | 15 assertions |
| `codegenTest.asl` | pass | 10 assertions |
| `emitWatTest.asl` | pass | 67 assertions |
| `exprTest.asl` | pass | 8 assertions |
| `goCodegenTest.asl` | pass | 36 assertions |
| `mangleTest.asl` | pass | 10 assertions |
| `rtypesTest.asl` | pass | 12 assertions |
