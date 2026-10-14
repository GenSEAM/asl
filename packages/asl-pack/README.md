# asl-pack

ASL modules that describe packaging and distribution: platform triples, a WebAssembly runtime chooser, build graphs, package manifests and capability checks, the standalone bundle footer layout, and generators for installer, OS package, release and mobile bridge text. Most functions return records and script text; they do not build a binary.

- `platform.asl`: `TargetOs`, `TargetArch`, `targetTriple`, `formatBinaryName`.
- `runtime.asl`: `recommendRuntimeProfile` picks Wasmtime, WAMR, Wasm3, V8, browser or AOT by environment, SIMD need and a no-JIT constraint. The cold-start and size numbers in `profileForRuntime` are constants in the source with no measurement behind them.
- `pack.asl`, `standalone.asl`, `buildGraph.asl`, `packageAsl.asl`, `targetAdapter.asl`, `intermediatePolicy.asl`, `distributionProfiles.asl`: package plans, manifests, capability checks, compile waves and intermediate-file policy.
- `dist.asl`, `installer.asl`, `packaging.asl`: text of `install.sh`, `install.ps1`, npm wrappers, agent-platform instruction files, and macOS, Debian, RPM, Windows and browser package specs.
- `release.asl`: `executeReleasePlan!` runs real commands (`mkdir`, `zip`/`tar`, `sha256sum`, `cp`); its first step, `runVerificationGate!`, runs `./bin/asl audit gates`, which does not exist in this repository, so that step fails (the later steps still run, and the receipt records the failure).
- `ffiLinker.asl`: shared-library names and linker flags per platform.
- `targets/`: Kotlin/Android JNI and Swift/iOS bridge generators, and a generator for a Node.js mobile preview-server script.

Building an executable is not done here: `asl/host/out/asl-host build FILE -o OUT` embeds the checked module sources in an executable linked against the host library.

Module names use the prefix `aslPack/`; `manifest.asn` lists the same 18 modules. All 18 files in `src/` pass `asl/host/out/asl-host check` (2026-10-14).

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 18 modules, 148 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `aslPack/buildGraph` (`src/buildGraph.asl`, 12): `BuildModule`, `BuildTarget`, `BuildPipelineStage`, `BuildGraph`, `BuildPlan`, `DagValidation`, `makeBuildGraph`, `validateModuleDag`, `computeTopologicalOrder`, `computeCompilationWaves`, `planTargetCompilation`, `emitBuildReceipt`.
- `aslPack/dist` (`src/dist.asl`, 7): `DistConfig`, `makeDistConfig`, `emitInstallSh`, `emitInstallPs1`, `emitBuildFromSourceSh`, `emitNpmPackageJson`, `emitNpmBin`.
- `aslPack/distributionProfiles` (`src/distributionProfiles.asl`, 7): `DistributionProfile`, `PackagePullPlan`, `makeDistributionProfile`, `validateCoreEntrypoint`, `validateCoreEntryPoint`, `planPackagePull`, `defaultBundledPackages`.
- `aslPack/ffiLinker` (`src/ffiLinker.asl`, 7): `LibraryType`, `NativeLibrarySpec`, `ResolvedLinkerFlags`, `KernelSyscall`, `makeKernelCall`, `formatSharedLibName`, `resolveLibraryTarget`.
- `aslPack/installer` (`src/installer.asl`, 15): `SlashCommandSpec`, `AgentPlatform`, `InstallerConfig`, `InstallationPlan`, `formatToolbeltDirective`, `formatSlashAsl`, `formatSlashAslBuild`, `makeAgentPlatform`, `defaultAgentPlatforms`, `makeInstallerConfig`, `sanitizeInstructionText`, `injectInstructionDirective`, `planAgentInstallation`, `emitStandaloneInstallerScript`, `generateFullInstallScript`.
- `aslPack/intermediatePolicy` (`src/intermediatePolicy.asl`, 9): `IntermediatePolicy`, `makeDefaultIntermediatePolicy`, `resolveIntermediatePath`, `isIntermediateFile?`, `shouldCleanIntermediates?`, `cleanIntermediateFile!`, `isPathGitIgnored?`, `defaultIgnoredExtensions`, `defaultIgnoredDirectories`.
- `aslPack/pack` (`src/pack.asl`, 9): `BuildSpec`, `PackageArtifact`, `CapabilityReport`, `DceResult`, `planPackage`, `generatePackagingManifest`, `verifyPackageCapabilities`, `eliminateDeadCapabilities`, `validateManifestHash!`.
- `aslPack/packageAsl` (`src/packageAsl.asl`, 6): `PackageDependency`, `PackageDef`, `isPublishablePackage`, `validatePackageDef`, `parsePackageAsl`, `scanPackageTree`.
- `aslPack/packaging` (`src/packaging.asl`, 8): `PackageSpec`, `makePackageSpec`, `emitMacosPackageSpec`, `emitDebianControlFile`, `emitRpmSpecFile`, `emitWindowsPackageManifest`, `emitBrowserPackageBundle`, `emitPackageChecksumManifest`.
- `aslPack/platform` (`src/platform.asl`, 9): `TargetOs`, `TargetArch`, `PlatformDescriptor`, `makePlatform`, `targetTriple`, `formatBinaryName`, `isWindows?`, `isMacos?`, `isLinux?`.
- `aslPack/release` (`src/release.asl`, 15): `ReleasePlan`, `makeReleasePlan`, `ReleaseStepResult`, `ReleaseReceipt`, `executeReleaseStep!`, `runVerificationGate!`, `prepareDistDirectory!`, `bundleTargetPlatform!`, `generateChecksumManifest!`, `preparePublishMetadata!`, `executeReleasePlan!`, `executeSelfUpdate!`, `emitReleaseScriptSh`, `emitUpgradeScriptSh`, `emitVersionAsn`.
- `aslPack/runtime` (`src/runtime.asl`, 8): `WasmRuntimeKind`, `TargetEnvironment`, `ExecutionMode`, `RuntimeProfile`, `runtimeName`, `modeName`, `profileForRuntime`, `recommendRuntimeProfile`.
- `aslPack/standalone` (`src/standalone.asl`, 8): `StandaloneBundleConfig`, `BundleManifest`, `magicFooter`, `footerSizeBytes`, `requiresCodesign?`, `formatFooterManifest`, `formatCodesignCommand`, `planStandaloneBundle`.
- `aslPack/targetAdapter` (`src/targetAdapter.asl`, 7): `TargetProjection`, `TargetAdapter`, `TargetAdapterPlan`, `TargetBuildBridge`, `validateTargetAdapterContract`, `emitTargetAdapterPlan`, `projectionToBuildTarget`.
- `aslPack/targets/kotlin` (`src/targets/kotlin.asl`, 7): `KotlinTargetSpec`, `KotlinAppSpec`, `generateJniBinding`, `generateGradleDependency`, `generateKmpBuildGradle`, `generateComposeActivity`, `generateKmpStateFlow`.
- `aslPack/targets/preview` (`src/targets/preview.asl`, 3): `MobilePreviewSpec`, `generateDevicePreviewHtml`, `generatePreviewWasmManifest`.
- `aslPack/targets/previewServer` (`src/targets/previewServer.asl`, 4): `PreviewServerSpec`, `makePreviewServerSpec`, `formatHotReloadPatchFrame`, `generatePreviewServerScript`.
- `aslPack/targets/swift` (`src/targets/swift.asl`, 7): `SwiftPackageSpec`, `SwiftAppSpec`, `generatePackageSwift`, `generateCBridgeHeader`, `generateXcframeworkScript`, `generateSwiftuiEntrypoint`, `generateSwiftObservableStore`.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-pack/tests/<file>.asl
```

16 of 16 test files exit 0 (433 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `buildGraphTest.asl` | pass | 32 assertions, 11 refutations |
| `capabilitySandboxTest.asl` | pass | 22 assertions, 19 refutations |
| `distTest.asl` | pass | 23 assertions |
| `distributionProfilesTest.asl` | pass | 25 assertions, 5 refutations |
| `ffiTest.asl` | pass | 11 assertions |
| `installerTest.asl` | pass | 32 assertions |
| `intermediatePolicyTest.asl` | pass | 18 assertions, 5 refutations |
| `mobileTest.asl` | pass | 46 assertions |
| `packTest.asl` | pass | 26 assertions |
| `packageAslTest.asl` | pass | 29 assertions, 11 refutations |
| `packagingTest.asl` | pass | 31 assertions, 10 refutations |
| `platformTest.asl` | pass | 6 assertions |
| `releaseTest.asl` | pass | 20 assertions |
| `runtimeTest.asl` | pass | 4 assertions |
| `standaloneTest.asl` | pass | 14 assertions |
| `targetAdapterTest.asl` | pass | 25 assertions, 8 refutations |
