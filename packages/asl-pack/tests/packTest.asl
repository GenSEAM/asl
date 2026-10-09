(module aslPack/test :x [runTests] :i [(runtime :a rt) (platform :a plat) (pack :a pk)])

fn testRuntimeRecommendationCli -> Bool
  (let [(profile (rt/recommendRuntimeProfile (rt/envCli) true false))] (assert profile.supportsSimd "CLI profile must support SIMD") (assert (= (rt/runtimeName profile.runtime) "Wasmtime (Cranelift)") "Runtime must be Wasmtime") (assert (= (rt/modeName profile.mode) "JIT (Just-In-Time)") "Mode must be JIT") true)

fn testRuntimeRecommendationIos -> Bool
  (let [(profile (rt/recommendRuntimeProfile (rt/envMobileIos) true false))] (assert profile.appleAppstoreCompliant "iOS profile must be App Store compliant") (assert (= (rt/runtimeName profile.runtime) "LLVM / Cranelift AOT Native") "iOS runtime must be AOT Native") (assert (= (rt/modeName profile.mode) "AOT (Ahead-Of-Time)") "iOS mode must be AOT") true)

fn testRuntimeRecommendationAndroid -> Bool
  (let [(profile (rt/recommendRuntimeProfile (rt/envMobileAndroid) true false))] (assert profile.appleAppstoreCompliant "Android profile must be compliant") (assert (= (rt/runtimeName profile.runtime) "WAMR (Intel Micro Runtime)") "Android runtime must be WAMR") true)

fn testPlatformWindows -> Bool
  (let [(p (plat/makePlatform (plat/osWindows) (plat/archX64))) (binName (plat/formatBinaryName "asl" p))] (assert (plat/isWindows? p) "Platform must be Windows") (assert (= p.executableExtension ".exe") "Extension must be .exe") (assert (= p.sharedLibExtension ".dll") "Shared lib extension must be .dll") (assert (stringEndsWith? binName "x86_64-pc-windows-msvc.exe") "Binary name must end with triple exe") true)

fn testPlatformMacosArm64 -> Bool
  (let [(p (plat/makePlatform (plat/osMacos) (plat/archArm64)))] (assert (plat/isMacos? p) "Platform must be macOS") (assert (= p.triple "aarch64-apple-darwin") "Triple must be aarch64-apple-darwin") (assert (= p.executableExtension "") "Executable extension must be empty") (assert (= p.sharedLibExtension ".dylib") "Shared lib extension must be .dylib") true)

fn testPlanPackage -> Bool
  (let [(pMac (plat/makePlatform (plat/osMacos) (plat/archArm64))) (spec (pk/BuildSpec :appName "asl" :version "0.1.0" :entryModule "src/cli.asl" :targetPlatform pMac :environment (rt/envCli) :strictNoJit false :embedWasm true)) (artifact (pk/planPackage spec)) (manifest (pk/generatePackagingManifest artifact))] (assert (= artifact.targetTriple "aarch64-apple-darwin") "Artifact triple must match") (assert (stringContains? artifact.binaryName "asl-aarch64-apple-darwin") "Binary name must match") (assert (stringContains? manifest "pack:{asl-aarch64-apple-darwin") "Manifest must contain pack header") (assert (stringContains? manifest "|Wasmtime (Cranelift)|") "Manifest must contain runtime name") true)

fn runTests -> Bool
  (do (assert (testRuntimeRecommendationCli) "test-runtime-recommendation-cli must pass") (assert (testRuntimeRecommendationIos) "test-runtime-recommendation-ios must pass") (assert (testRuntimeRecommendationAndroid) "test-runtime-recommendation-android must pass") (assert (testPlatformWindows) "test-platform-windows must pass") (assert (testPlatformMacosArm64) "test-platform-macos-arm64 must pass") (assert (testPlanPackage) "test-plan-package must pass") true)
