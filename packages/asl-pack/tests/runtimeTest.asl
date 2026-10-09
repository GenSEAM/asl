(module aslPack/runtimeTest :x [runTests] :i [(runtime :a r)])

fn testProfileForRuntime -> Bool
  (let [(wasmtimeJit (r/profileForRuntime (r/rtWasmtime) (r/modeJit))) (wasm3Interp (r/profileForRuntime (r/rtWasm3) (r/modeInterpreted))) (wamrAot (r/profileForRuntime (r/rtWamr) (r/modeAot)))] (assert (== wasmtimeJit.appleAppstoreCompliant false) "Wasmtime JIT is not app store compliant") (assert (== wasm3Interp.appleAppstoreCompliant true) "Wasm3 is app store compliant") (assert (== wamrAot.supportsSimd true) "WAMR supports SIMD") true)

fn runTests -> Bool
  (do (assert (testProfileForRuntime) "test-profile-for-runtime must pass") true)
