# asl-pack

ASL modules that describe packaging: platform triples, a WebAssembly runtime chooser, and generators for installer, release and mobile bridge scripts. They return records and script text; they do not build a binary.

## Modules (`asl/packages/asl-pack/src`, module prefix `aslPack/`)
- `platform.asl`: `TargetOs`, `TargetArch`, `targetTriple`, `formatBinaryName`; triples for aarch64/x86_64 on darwin, linux-gnu and windows-msvc.
- `runtime.asl`: `recommendRuntimeProfile` picks Wasmtime, WAMR, Wasm3, V8, browser or AOT by environment, SIMD need and a no-JIT constraint. The cold-start and size numbers in `profileForRuntime` are constants in the source with no measurement behind them.
- `pack.asl`, `standalone.asl`, `buildGraph.asl`, `packaging.asl`, `packageAsl.asl`, `targetAdapter.asl`, `intermediatePolicy.asl`, `distributionProfiles.asl`: package plans, manifests, capability checks and the standalone bundle footer layout.
- `dist.asl`, `installer.asl`, `release.asl`: text of `install.sh`, `install.ps1`, npm wrappers, release and upgrade scripts.
- `ffiLinker.asl`: shared-library names and linker flags per platform.
- `targets/`: Kotlin/Android JNI, Swift/iOS, and preview-server generators.

## Status
- Target: self-contained single-binary executables. Today `./bin/asl build` returns `ERR_UNIMPLEMENTED` ("produces no artifact until R1").
- Tests (2026-09-24): `./bin/asl test asl/packages/asl-pack/tests/runtimeTest.asl` exits 0 with 4 assertions on both asl-core and `asl/host/out/asl-host test`; `packTest.asl` exits 0 with 26 assertions on asl-core and 1 on the host (1 load error).
