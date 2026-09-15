(module aslPack/test
  :d "Unit tests for runtime matrix recommendations, platform descriptors, and packaging plans."
  :x [runTests]
  :i [(runtime :a rt)
      (platform :a plat)
      (pack :a pk)])

(df testRuntimeRecommendationCli [] -> Bool
  :d "Verifies CLI environment selects Wasmtime JIT for high throughput and SIMD."
  (let [(profile (rt/recommendRuntimeProfile (rt/envCli) true false))]
    (assert (.-supportsSimd profile) "CLI profile must support SIMD")
    (assert (= (rt/runtimeName (.-runtime profile)) "Wasmtime (Cranelift)") "Runtime must be Wasmtime")
    (assert (= (rt/modeName (.-mode profile)) "JIT (Just-In-Time)") "Mode must be JIT")
    true))

(df testRuntimeRecommendationIos [] -> Bool
  :d "Verifies iOS environment enforces Apple App Store compliant AOT without JIT."
  (let [(profile (rt/recommendRuntimeProfile (rt/envMobileIos) true false))]
    (assert (.-appleAppstoreCompliant profile) "iOS profile must be App Store compliant")
    (assert (= (rt/runtimeName (.-runtime profile)) "LLVM / Cranelift AOT Native") "iOS runtime must be AOT Native")
    (assert (= (rt/modeName (.-mode profile)) "AOT (Ahead-Of-Time)") "iOS mode must be AOT")
    true))

(df testRuntimeRecommendationAndroid [] -> Bool
  :d "Verifies Android environment selects compact WAMR AOT engine."
  (let [(profile (rt/recommendRuntimeProfile (rt/envMobileAndroid) true false))]
    (assert (.-appleAppstoreCompliant profile) "Android profile must be compliant")
    (assert (= (rt/runtimeName (.-runtime profile)) "WAMR (Intel Micro Runtime)") "Android runtime must be WAMR")
    true))

(df testPlatformWindows [] -> Bool
  :d "Verifies Windows platform target adds .exe and generates PC triple."
  (let [(p (plat/makePlatform (plat/osWindows) (plat/archX64)))
        (binName (plat/formatBinaryName "asl" p))]
    (assert (plat/isWindows? p) "Platform must be Windows")
    (assert (= (.-executableExtension p) ".exe") "Extension must be .exe")
    (assert (= (.-sharedLibExtension p) ".dll") "Shared lib extension must be .dll")
    (assert (string-ends-with? binName "x86_64-pc-windows-msvc.exe") "Binary name must end with triple exe")
    true))

(df testPlatformMacosArm64 [] -> Bool
  :d "Verifies macOS Apple Silicon target configuration."
  (let [(p (plat/makePlatform (plat/osMacos) (plat/archArm64)))]
    (assert (plat/isMacos? p) "Platform must be macOS")
    (assert (= (.-triple p) "aarch64-apple-darwin") "Triple must be aarch64-apple-darwin")
    (assert (= (.-executableExtension p) "") "Executable extension must be empty")
    (assert (= (.-sharedLibExtension p) ".dylib") "Shared lib extension must be .dylib")
    true))

(df testPlanPackage [] -> Bool
  :d "Verifies end-to-end packaging plan generation and ASN manifest serialization."
  (let [(pMac (plat/makePlatform (plat/osMacos) (plat/archArm64)))
        (spec (pk/BuildSpec
                :appName "asl"
                :version "0.1.0"
                :entryModule "src/cli.asl"
                :targetPlatform pMac
                :environment (rt/envCli)
                :strictNoJit false
                :embedWasm true))
        (artifact (pk/planPackage spec))
        (manifest (pk/generatePackagingManifest artifact))]
    (assert (= (.-targetTriple artifact) "aarch64-apple-darwin") "Artifact triple must match")
    (assert (string-contains? (.-binaryName artifact) "asl-aarch64-apple-darwin") "Binary name must match")
    (assert (string-contains? manifest "pack:{asl-aarch64-apple-darwin") "Manifest must contain pack header")
    (assert (string-contains? manifest "|Wasmtime (Cranelift)|") "Manifest must contain runtime name")
    true))

(df runTests [] -> Bool
  :d "Executes all packaging and runtime test suites."
  (do
    (assert (testRuntimeRecommendationCli) "test-runtime-recommendation-cli must pass")
    (assert (testRuntimeRecommendationIos) "test-runtime-recommendation-ios must pass")
    (assert (testRuntimeRecommendationAndroid) "test-runtime-recommendation-android must pass")
    (assert (testPlatformWindows) "test-platform-windows must pass")
    (assert (testPlatformMacosArm64) "test-platform-macos-arm64 must pass")
    (assert (testPlanPackage) "test-plan-package must pass")
    true))
