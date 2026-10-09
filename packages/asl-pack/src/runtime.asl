(module aslPack/runtime :x [WasmRuntimeKind TargetEnvironment ExecutionMode RuntimeProfile runtimeName modeName profileForRuntime recommendRuntimeProfile] :i [])

(enum WasmRuntimeKind (:c rtWasmtime [] "Bytecode Alliance Cranelift JIT / WASI p1-p2, SIMD-128, threads") (:c rtWamr [] "WebAssembly Micro Runtime (Intel): small footprint, interpreter/AOT/JIT") (:c rtWasm3 [] "Pure C interpreter: zero JIT allocation, instant boot, strict sandboxing") (:c rtV8Node [] "Embedded V8 / Node.js / Bun runtime with full JS host environment") (:c rtBrowserNative [] "Standard browser WebAssembly engine") (:c rtAotNative [] "Direct Ahead-of-Time native machine code compilation via LLVM/Cranelift"))

(enum TargetEnvironment (:c envCli [] "Developer terminal tools and single-executable CLIs") (:c envServer [] "Cloud servers, container microVMs, high-throughput daemons") (:c envMobileIos [] "iOS native applications (strict Apple App Store no-JIT policy)") (:c envMobileAndroid [] "Android native applications (JNI / NDK)") (:c envBrowser [] "Web client applications and browser copilot extensions") (:c envEmbedded [] "Microcontrollers, IoT devices, severe RAM limits < 1MB"))

(enum ExecutionMode (:c modeJit [] "Dynamic Just-in-Time compilation to native machine code") (:c modeAot [] "Ahead-of-Time compiled static native object code") (:c modeInterpreted [] "Pure bytecode interpreter without dynamic executable memory"))

(schema RuntimeProfile (:f runtime WasmRuntimeKind) (:f mode ExecutionMode) (:f supportsSimd Bool) (:f appleAppstoreCompliant Bool) (:f coldStartMs F64) (:f binaryOverheadMb F64) (:f recommendationNotes Str))

fn runtimeName rt: WasmRuntimeKind -> Str
  (mt rt ((rtWasmtime) "Wasmtime (Cranelift)") ((rtWamr) "WAMR (Intel Micro Runtime)") ((rtWasm3) "Wasm3 (Fast C Interpreter)") ((rtV8Node) "V8 / Node Embed") ((rtBrowserNative) "Browser Native Engine") ((rtAotNative) "LLVM / Cranelift AOT Native"))

fn modeName m: ExecutionMode -> Str
  (mt m ((modeJit) "JIT (Just-In-Time)") ((modeAot) "AOT (Ahead-Of-Time)") ((modeInterpreted) "Interpreted (Zero-JIT)"))

fn profileForRuntime rt: WasmRuntimeKind mode: ExecutionMode -> RuntimeProfile
  (mt rt ((rtWasmtime) (RuntimeProfile :runtime rt :mode mode :supportsSimd true :appleAppstoreCompliant false :coldStartMs 1.5 :binaryOverheadMb 12.0 :recommendationNotes "Best-in-class performance for CLI and server. High throughput, SIMD-128, and robust WASI preview2.")) ((rtWamr) (RuntimeProfile :runtime rt :mode mode :supportsSimd true :appleAppstoreCompliant true :coldStartMs 0.2 :binaryOverheadMb 0.8 :recommendationNotes "Intel WAMR: ultra-compact footprint (<1MB), multi-tier AOT/interpreter, optimal for Android and mobile.")) ((rtWasm3) (RuntimeProfile :runtime rt :mode mode :supportsSimd false :appleAppstoreCompliant true :coldStartMs 0.05 :binaryOverheadMb 0.15 :recommendationNotes "Wasm3: instant cold start (<0.05ms), tiny 150KB footprint, zero JIT allocation. Ideal for strict sandbox/iOS.")) ((rtV8Node) (RuntimeProfile :runtime rt :mode mode :supportsSimd true :appleAppstoreCompliant false :coldStartMs 15.0 :binaryOverheadMb 35.0 :recommendationNotes "V8 / Node: rich JS ecosystem integration, fast JIT, higher binary footprint.")) ((rtBrowserNative) (RuntimeProfile :runtime rt :mode mode :supportsSimd true :appleAppstoreCompliant true :coldStartMs 0.01 :binaryOverheadMb 0.0 :recommendationNotes "Zero-bundle overhead; leverages browser-resident WebAssembly JIT engine directly.")) ((rtAotNative) (RuntimeProfile :runtime rt :mode mode :supportsSimd true :appleAppstoreCompliant true :coldStartMs 0.001 :binaryOverheadMb 1.5 :recommendationNotes "Direct native machine code emission. 100% Apple App Store compliant, zero runtime compilation overhead.")))

fn isIos? env: TargetEnvironment -> Bool
  (mt env ((envMobileIos) true) ((envCli) false) ((envServer) false) ((envMobileAndroid) false) ((envBrowser) false) ((envEmbedded) false))

fn recommendRuntimeProfile env: TargetEnvironment needsSimd: Bool strictNoJit: Bool -> RuntimeProfile
  (if (or strictNoJit (isIos? env)) (if needsSimd (profileForRuntime (rtAotNative) (modeAot)) (profileForRuntime (rtWasm3) (modeInterpreted))) (mt env ((envCli) (profileForRuntime (rtWasmtime) (modeJit))) ((envServer) (profileForRuntime (rtWasmtime) (modeJit))) ((envMobileIos) (profileForRuntime (rtAotNative) (modeAot))) ((envMobileAndroid) (profileForRuntime (rtWamr) (modeAot))) ((envBrowser) (profileForRuntime (rtBrowserNative) (modeJit))) ((envEmbedded) (profileForRuntime (rtWasm3) (modeInterpreted)))))
