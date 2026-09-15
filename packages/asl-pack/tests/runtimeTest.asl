(module aslPack/runtimeTest
  :d "Unit tests for runtime profile generation."
  :x [runTests]
  :i [(runtime :a r)])

(df testProfileForRuntime [] -> Bool
  :d "Verifies profile-for-runtime output for various combinations."
  (let [(wasmtimeJit (r/profileForRuntime (r/rtWasmtime) (r/modeJit)))
        (wasm3Interp (r/profileForRuntime (r/rtWasm3) (r/modeInterpreted)))
        (wamrAot (r/profileForRuntime (r/rtWamr) (r/modeAot)))]
    (assert (== (.-appleAppstoreCompliant wasmtimeJit) false) "Wasmtime JIT is not app store compliant")
    (assert (== (.-appleAppstoreCompliant wasm3Interp) true) "Wasm3 is app store compliant")
    (assert (== (.-supportsSimd wamrAot) true) "WAMR supports SIMD")
    true))

(df runTests [] -> Bool
  :d "Executes runtime test suite."
  (do
    (assert (testProfileForRuntime) "test-profile-for-runtime must pass")
    true))
