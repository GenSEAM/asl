(module aslPack/mobileTest
  :d "Unit tests for Swift Package Manager and Kotlin Multiplatform bridge generation."
  :x [runTests]
  :i [(aslPack/targets/swift :a sw)
      (aslPack/targets/kotlin :a kt)
      (aslPack/targets/preview :a prev)
      (aslPack/targets/previewServer :a ps)])

(df testSwiftPackageGeneration [] -> Bool
  :d "Verifies Package.swift and C-bridge header generation."
  (let [(spec (sw/SwiftPackageSpec
                :pkgName "ASLKit"
                :iosMinVersion "v15"
                :macosMinVersion "v12"
                :cBridgeHeader "ASLBridge.h"))
        (pkgSwift (sw/generatePackageSwift spec))
        (cHdr (sw/generateCBridgeHeader "ASLKit"))]
    (assert (string-contains? pkgSwift "name: \"ASLKit\"") "Package name must match")
    (assert (string-contains? pkgSwift ".iOS(.v15)") "iOS min version must match")
    (assert (string-contains? cHdr "typedef struct {") "C bridge must declare struct")
    (assert (string-contains? cHdr "asl_eval") "C bridge must declare asl_eval")
    true))

(df testSwiftAppAndXcframeworkGeneration [] -> Bool
  :d "Verifies XCFramework script, SwiftUI @main entrypoint, and Swift 6 Observable store generation."
  (let [(appSpec (sw/SwiftAppSpec
                    :appName "MobileAgent"
                    :bundleId "io.genseam.mobile"
                    :iosMinVersion "v16"
                    :packageName "ASLKit"))
        (xcScript (sw/generateXcframeworkScript "ASLKit" "build/xcframework"))
        (appSwift (sw/generateSwiftuiEntrypoint "MobileAgent"))
        (storeSwift (sw/generateSwiftObservableStore "ASLStateStore"))]
    (assert (string-contains? xcScript "xcodebuild -create-xcframework") "XCFramework script must invoke xcodebuild")
    (assert (string-contains? xcScript "generic/platform=iOS Simulator") "XCFramework script must target iOS Simulator")
    (assert (string-contains? xcScript "ASLKit.xcframework") "XCFramework output path must match")
    (assert (string-contains? appSwift "@main") "SwiftUI entrypoint must declare @main")
    (assert (string-contains? appSwift "struct MobileAgentApp: App") "SwiftUI app struct must match")
    (assert (string-contains? appSwift "WindowGroup") "SwiftUI app must include WindowGroup")
    (assert (string-contains? storeSwift "@Observable") "State store must use Swift 6 @Observable")
    (assert (string-contains? storeSwift "asl_eval") "State store must call asl_eval")
    (assert (string-contains? storeSwift "asl_free_buffer") "State store must free buffer")
    true))

(df testKotlinJniGeneration [] -> Bool
  :d "Verifies Kotlin JNI external class and Gradle dependency generation."
  (let [(spec (kt/KotlinTargetSpec
                :packageId "io.genseam.asl"
                :className "ASLAgent"))
        (jniKt (kt/generateJniBinding spec))
        (gradle (kt/generateGradleDependency spec))]
    (assert (string-contains? jniKt "package io.genseam.asl") "Kotlin package must match")
    (assert (string-contains? jniKt "class ASLAgent") "Kotlin class name must match")
    (assert (string-contains? jniKt "System.loadLibrary(\"asl_wamr_jni\")") "Kotlin must load native lib")
    (assert (string-contains? gradle "implementation(\"io.genseam:asl-wamr-runtime") "Gradle dep must match")
    true))

(df testKotlinKmpAndComposeGeneration [] -> Bool
  :d "Verifies Kotlin Multiplatform build.gradle.kts, Compose Activity, and StateFlow store generation."
  (let [(appSpec (kt/KotlinAppSpec
                    :packageId "io.genseam.mobile"
                    :appName "MainActivity"
                    :minSdk 26
                    :targetSdk 34))
        (kmpGradle (kt/generateKmpBuildGradle appSpec))
        (activityKt (kt/generateComposeActivity appSpec))
        (stateKt (kt/generateKmpStateFlow "io.genseam.mobile"))]
    (assert (string-contains? kmpGradle "kotlin(\"multiplatform\")") "KMP gradle must apply multiplatform plugin")
    (assert (string-contains? kmpGradle "androidTarget()") "KMP gradle must declare androidTarget")
    (assert (string-contains? kmpGradle "iosArm64()") "KMP gradle must declare iosArm64")
    (assert (string-contains? kmpGradle "wasmJs { browser() }") "KMP gradle must declare wasmJs browser target")
    (assert (string-contains? kmpGradle "org.jetbrains.compose") "KMP gradle must apply compose plugin")
    (assert (string-contains? activityKt "class MainActivity : ComponentActivity()") "Activity must inherit ComponentActivity")
    (assert (string-contains? activityKt "setContent {") "Activity must call setContent")
    (assert (string-contains? activityKt "MaterialTheme") "Activity must wrap MaterialTheme")
    (assert (string-contains? stateKt "StateFlow<String>") "State store must expose StateFlow")
    (assert (string-contains? stateKt "MutableStateFlow") "State store must initialize MutableStateFlow")
    true))

(df testMobilePreviewGeneration [] -> Bool
  :d "Verifies HTML5 dual-device simulator and Wasm runtime preview manifest generation."
  (let [(prevSpec (prev/MobilePreviewSpec
                     :appName "ASL Mobile Preview"
                     :defaultPlatform "ios"
                     :enableHotReload true
                     :reloadPort 8080))
        (html (prev/generateDevicePreviewHtml prevSpec))
        (manifest (prev/generatePreviewWasmManifest prevSpec))]
    (assert (string-contains? html "<title>ASL Mobile Preview - In-Browser Mobile Preview</title>") "HTML title must match")
    (assert (string-contains? html "dynamic-island") "HTML simulator must contain dynamic island")
    (assert (string-contains? html "device-frame") "HTML simulator must contain device frame")
    (assert (string-contains? html "new WebSocket('ws://localhost:8080')") "HTML simulator must connect WebSocket")
    (assert (string-contains? manifest ":wasm-preview-config") "Wasm manifest must have config header")
    (assert (string-contains? manifest ":platform \"ios\"") "Wasm manifest must match platform")
    (assert (string-contains? manifest ":hot-reload true") "Wasm manifest must enable hot reload")
    (assert (string-contains? manifest ":port 8080") "Wasm manifest must match port")
    true))

(df testPreviewServer [] -> Bool
  :d "Verifies WebSocket hot-reload server script generation and patch frame formatting."
  (let [(srvSpec (ps/makePreviewServerSpec 8080 "scratch"))
        (patchFrame (ps/formatHotReloadPatchFrame "MobilePreview" "<div>updated</div>"))
        (srvScript (ps/generatePreviewServerScript srvSpec))]
    (assert (= (.-port srvSpec) 8080) "Server spec port must match 8080")
    (assert (string-contains? patchFrame "patch") "Patch frame must contain patch type")
    (assert (string-contains? patchFrame "MobilePreview") "Patch frame must target MobilePreview")
    (assert (string-contains? srvScript "PORT = 8080") "Server script must configure PORT 8080")
    (assert (string-contains? srvScript "http.createServer") "Server script must create HTTP server")
    true))

(df runTests [] -> Bool
  :d "Executes mobile target test suites."
  (do
    (assert (testSwiftPackageGeneration) "test-swift-package-generation must pass")
    (assert (testSwiftAppAndXcframeworkGeneration) "test-swift-app-and-xcframework-generation must pass")
    (assert (testKotlinJniGeneration) "test-kotlin-jni-generation must pass")
    (assert (testKotlinKmpAndComposeGeneration) "test-kotlin-kmp-and-compose-generation must pass")
    (assert (testMobilePreviewGeneration) "test-mobile-preview-generation must pass")
    (assert (testPreviewServer) "test-preview-server must pass")
    true))
