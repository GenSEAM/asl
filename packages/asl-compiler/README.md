# asl-compiler

ASL modules for compiling ASL: the `asl1` driver that writes LLVM IR through `asl-target-llvm`, a C99 path through `asl-codegen`, a target dispatcher, a WebAssembly binary encoder, a reference tree-walking evaluator, and supporting passes (macros, constant folding, incremental queries, diagnostics with patch suggestions).

- `asl1.asl`: `usage: asl1 build ENTRY -o OUT.ll | asl1 check ENTRY | asl1 deps ENTRY`. `build` calls `compilePackageToLlvm!` and writes LLVM IR. On 2026-10-14, `asl/host/out/asl-host run asl/packages/asl-compiler/src/asl1.asl build hello.asl -o hello.ll` wrote IR for a one-function program. `asl-target-llvm` lowers to native code and to `wasm32-unknown-unknown`; per the repository README, the self-hosted native `asl1` binary has a seed for `arm64-apple-darwin` only.
- `compiler.asl`: `compileSourceToC99`, `compilePackageToC99!`, `compilePackageToLlvm!`, `formatDiagnostic`, capability checks. `targets.asl`: dispatch to the C99, C11 (`asl-target-c`), LLVM, Swift, Rust and shell backends.
- `wasm.asl`: WebAssembly v1 binary encoding (LEB128, sections, opcodes) and an MVP lowering (`lowerAstExpr`) for integer arithmetic: integer and boolean constants, locals, `if`, `do`, arithmetic, comparison and logic operators, and calls (including the WASI `fd_write` and `proc_exit` imports). Any other form, strings and records included, lowers silently to the constant 0, and a bare top-level expression is rejected (`ERR_WASM_TOPLEVEL_EXPR`). `wasi.asl`: WASI preview 1 constants, import descriptors and capability checks.
- `evaluator.asl`: tree-walking evaluator (`evalSexpr!`, environments, builtin groups). `checkCache.asl`: cached check verdicts for `asl1 check`.
- `elf.asl`, `macho.asl`: ELF64 and Mach-O arm64 emitter sketches.
- `diagnostics.asl`, `heal.asl`, `comptime.asl`, `salsa.asl`, `compactRewrite.asl`, `optFold.asl`, `vfsGit.asl`, `macro.asl`, `monad.asl`, `threadMacro.asl`, `tryMacro.asl`: diagnostics with patch suggestions, compile-time evaluation, incremental queries, rewrites, a git reader and macro expanders.

`asl/host/out/asl-host` (the C host) is what checks, runs and tests ASL today; `asl-host build FILE -o OUT` embeds the checked module sources in an executable linked against the host and does not use this package.

Module names use the prefix `asl-compiler/`; `manifest.asn` lists the same 20 modules. All 20 files in `src/` pass `asl/host/out/asl-host check` (2026-10-14).

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 20 modules, 258 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `asl-compiler/asl1` (`src/asl1.asl`, 2): `main`, `usage`.
- `asl-compiler/checkCache` (`src/checkCache.asl`, 9): `Verdict`, `cacheDir!`, `verdictKey!`, `keyText`, `encodeVerdict`, `decodeVerdict`, `lookup!`, `store!`, `replay!`.
- `asl-compiler/compactRewrite` (`src/compactRewrite.asl`, 5): `CompactionRule`, `makeCompactionRule`, `rewriteAstTokens`, `compactionTarget?`, `defaultCompactionRules`.
- `asl-compiler/compiler` (`src/compiler.asl`, 10): `CompileResult`, `compileSourceToC99`, `compilePackageToC99!`, `compilePackageToLlvm!`, `formatDiagnostic`, `formatIrDiagnostics`, `compileSourceTarget`, `compileStandaloneTarget`, `verifyPackageCapabilities`, `eliminateDeadCapabilities`.
- `asl-compiler/comptime` (`src/comptime.asl`, 17): `ComptimeConfig`, `ComptimeResult`, `makeComptimeConfig`, `makeComptimeResult`, `evalComptime`, `evalComptimeWithConfig`, `checkPurity`, `consumeFuel`, `expandQuasiquote`, `gensym`, `monotonicAfter`, `foldArithmetic`, `isPureOp?`, `parseSnippet`, `foldBinaryList`, `evalNodeRecursive`, `evalArgsLoop`.
- `asl-compiler/diagnostics` (`src/diagnostics.asl`, 10): `SelfHealingDiagnostic`, `makeSelfHealingDiagnostic`, `emitDiagnosticWithPatch`, `suggestMissingImportPatch`, `suggestMissingMatchBranchPatch`, `suggestTypeMismatchPatch`, `suggestMissingExportPatch`, `formatDiagnosticWithPatch`, `renderDiagnosticReceipt`, `parseDiagnosticReceipt`.
- `asl-compiler/elf` (`src/elf.asl`, 13): `emitElf64`, `writeElfHeaders`, `elfSections`, `sysvAbi`, `hostLinuxAdapter`, `hostWindowsAdapter`, `hostWasiAdapter`, `normalizeWin32Path`, `qpcToNanoseconds`, `iocpRingInit`, `iocpRingPush`, `iocpRingPop`, `translateIocpEvent`.
- `asl-compiler/evaluator` (`src/evaluator.asl`, 22): `EvalValue`, `EvalEnv`, `makeRootEnv`, `makeChildEnv`, `envLookup`, `envBind`, `evalAtom`, `evalBuiltinArithmetic`, `evalBuiltinComparison`, `evalBuiltinLogic`, `evalBuiltinString`, `evalBuiltinList`, `evalBuiltinIo!`, `evalBuiltinSys!`, `evalSpecialForm!`, `evalSexpr!`, `evalAssert`, `truthy?`, and 4 more.
- `asl-compiler/heal` (`src/heal.asl`, 10): `HealTransactionResult`, `makeHealTransactionResult`, `RollbackJournalRecord`, `makeRollbackJournalRecord`, `createRollbackJournalEntry`, `canRetryHeal`, `synthesizeHealPatch`, `verifyHealPatchCandidate`, `applyHealTransaction`, `getPatchOpKind`.
- `asl-compiler/macho` (`src/macho.asl`, 7): `emitMachoArm64`, `writeMachoHeaders`, `arm64Instructions`, `machoSections`, `hostDarwinAdapter`, `machTimeToNanoseconds`, `canonicalizePathDarwin`.
- `asl-compiler/macro` (`src/macro.asl`, 7): `expandLetPair`, `expandIfLet`, `expandWhenLet`, `expandCond`, `expandCase`, `expandLetStar`, `expandPipe`.
- `asl-compiler/monad` (`src/monad.asl`, 7): `optionMap`, `option-and-then`, `option-unwrap-or`, `resultMap`, `resultMapErr`, `result-and-then`, `result-unwrap-or`.
- `asl-compiler/optFold` (`src/optFold.asl`, 12): `foldConstants`, `foldArithmetic`, `foldLogic`, `foldBranches`, `asInt`, `asBool`, `simplifyBoolean`, `dceBlock`, `evalComptimeConstant`, `foldLetBindings`, `substituteVar`, `sexprEquals?`.
- `asl-compiler/salsa` (`src/salsa.asl`, 18): `QueryKey`, `QueryEntry`, `QueryProvider`, `SalsaDatabase`, `QueryResult`, `makeQueryKey`, `makeSalsaDatabase`, `registerQuery`, `demandQuery`, `executeQuery`, `invalidateQuery`, `evictStaleEpochs`, `redGreenCheck`, `simulateEditCycles`, `findQuery`, `findProvider`, `computeHashString`, `makeDummyEntry`.
- `asl-compiler/targets` (`src/targets.asl`, 5): `compileSourceTarget`, `compileSource`, `compileStandaloneTarget`, `compileStandaloneSource`, `transpileTarget`.
- `asl-compiler/threadMacro` (`src/threadMacro.asl`, 7): `hasThreadForm?`, `threadFirstStep`, `threadLastStep`, `expandThreadMacro`, `expandThreadInSource`, `findMatchingCloseParen`, `parseThreadForms`.
- `asl-compiler/tryMacro` (`src/tryMacro.asl`, 5): `hasTryForm?`, `expandTryMacro`, `expandTryInSource`, `makeTryExpansion`, `findMatchingCloseParen`.
- `asl-compiler/vfsGit` (`src/vfsGit.asl`, 9): `gitReadHead!`, `gitCurrentBranch!`, `gitParsePackedRefs`, `gitResolveRefCommit!`, `gitHeadCommit!`, `gitParseConfig!`, `gitInspectRepoStatus!`, `normalizePath`, `gitResolveDirs!`.
- `asl-compiler/wasi` (`src/wasi.asl`, 38): `wasiFdStdin`, `wasiFdStdout`, `wasiFdStderr`, `wasiFdPreopenStart`, `wasiErrno`, `wasiErrnoName`, `wasiOpenFlags`, `wasiFileType`, `wasiFileTypeName`, `wasiStandardImports`, `encodeCiovec`, `wasiFdWrite!`, `wasiFdRead!`, `wasiPathOpen!`, `wasiFdClose!`, `wasiPathFilestatGet!`, `wasiFileRead!`, `wasiFileWrite!`, and 20 more.
- `asl-compiler/wasm` (`src/wasm.asl`, 45): `leb128EncodeU32`, `leb128EncodeI32`, `encodeUtf8`, `byteLength`, `flattenByteLists`, `wasmMagicHeader`, `encodeSection`, `encodeFuncType`, `encodeTypeSection`, `encodeFunctionSection`, `encodeMemorySection`, `encodeImportEntry`, `encodeImportSection`, `encodeExportEntry`, `encodeExportSection`, `encodeLocalEntry`, `encodeFunctionBody`, `encodeCodeSection`, and 27 more.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-compiler/tests/<file>.asl
```

28 of 34 test files exit 0 (983 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `asl1Test.asl` | **fail** | needs the parent monorepo: imports `tools/nativeTest` |
| `c99AbiBridgeTest.asl` | pass | 18 assertions, 13 refutations |
| `c99TargetTest.asl` | **fail** | needs the parent monorepo: reads `tests/acceptance/d81/ResolutionSample.asl` |
| `calcFixture.asl` | pass | 2 assertions |
| `checkCacheTest.asl` | **fail** | needs the parent monorepo: imports `tools/fleet/run` and `tools/nativeTest` |
| `coTest.asl` | pass | 32 assertions |
| `compactRewriteTest.asl` | pass | 28 assertions |
| `comptimeTest.asl` | pass | 54 assertions, 28 refutations |
| `coreClosureTest.asl` | pass | 8 assertions, 4 refutations |
| `entryDirResolutionTest.asl` | pass | 7 assertions, 2 refutations |
| `evaluatorTest.asl` | pass | 46 assertions, 40 refutations |
| `evaluatorWasiTest.asl` | pass | 14 assertions, 9 refutations |
| `healTest.asl` | pass | 15 assertions, 9 refutations |
| `hostAdapterTest.asl` | pass | 52 assertions, 22 refutations |
| `macroTest.asl` | pass | 27 assertions, 7 refutations |
| `monadTest.asl` | pass | 21 assertions, 12 refutations |
| `optFoldTest.asl` | pass | 32 assertions, 8 refutations |
| `salsaTest.asl` | pass | 48 assertions, 31 refutations |
| `stage2_test.asl` | pass | 8 assertions, 3 refutations |
| `targetsLlvmDiagTest.asl` | pass | 20 assertions, 3 refutations |
| `threadMacroTest.asl` | pass | 17 assertions, 10 refutations |
| `tryMacroTest.asl` | pass | 12 assertions, 5 refutations |
| `vfsGitTest.asl` | **fail** | needs the parent monorepo: expects a git repository at the working directory |
| `wasiAbiTest.asl` | pass | 40 assertions, 11 refutations |
| `wasiCapabilityTest.asl` | pass | 21 assertions, 10 refutations |
| `wasiIoTest.asl` | pass | 45 assertions, 24 refutations |
| `wasiRuntimeTest.asl` | **fail** | needs the parent monorepo: expects a git repository at the working directory (`gitCurrentBranch!`) |
| `wasmBinaryTargetTest.asl` | pass | 17 assertions, 5 refutations |
| `wasmCodegenTest.asl` | pass | 15 assertions, 5 refutations |
| `wasmLeb128Test.asl` | pass | 25 assertions, 9 refutations |
| `wasmLoweringTest.asl` | **fail** | needs the parent monorepo: imports `tools/nativeTest` |
| `wasmOpcodesTest.asl` | pass | 31 assertions, 5 refutations |
| `wasmSectionTest.asl` | pass | 29 assertions, 7 refutations |
| `wasmTest.asl` | pass | 11 assertions, 6 refutations |
