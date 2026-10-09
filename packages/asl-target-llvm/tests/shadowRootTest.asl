(module asl/packages/asl-target-llvm/tests/shadowRootTest
  :x [runTests]
  :i [(asl-target-llvm/gcRoute :a gr)
      (asl-target-llvm/target :a target)
      (asl-target-llvm/libc :a libc)])

fn wasmGcText -> (Option String)
  (mt (libc/libcFacts "darwin-arm64")
    ((none) (none))
    ((some facts) (mt (gr/collectorTextForTarget facts (target/wasm32TargetFacts))
                    ((ok text) (some text))
                    ((err _) (none)))))

fn nativeGcText -> (Option String)
  (mt (libc/libcFacts "darwin-arm64")
    ((none) (none))
    ((some facts) (mt (gr/collectorTextForTarget facts (target/nativeTargetFacts "x86_64-apple-darwin"))
                    ((ok text) (some text))
                    ((err _) (none)))))

fn testWasmMarkSkipsNativeStack -> Bool
  (mt (wasmGcText)
    ((none) false)
    ((some text) (and (stringContains? text "br label %bb.frames\n")
                      (stringContains? text "br i1 %fmore, label %bb.fbody, label %bb.roots\n"))))

fn testWasmMarkOmitsNativeStackBase -> Bool
  (mt (wasmGcText)
    ((none) false)
    ((some text) (not (stringContains? text "call i64 @gcAslStackBase"))))

fn testWasmMarkOmitsNativeStackBranch -> Bool
  (mt (wasmGcText)
    ((none) false)
    ((some text) (not (stringContains? text "br i1 %skip, label %bb.roots"))))

fn testNativeMarkRetainsConservativeStack -> Bool
  (mt (nativeGcText)
    ((none) false)
    ((some text) (and (stringContains? text "@gcAslStackBase")
                      (stringContains? text "br i1 %skip, label %bb.roots"))))

fn testWasmMarkWalksShadowFrames -> Bool
  (mt (wasmGcText)
    ((none) false)
    ((some text) (and (stringContains? text "@asl_gc_shadow_top = global i64 0")
                      (stringContains? text "call i64 @gcAslShadowTop()"))))

fn testNativeHasNoShadowFrames -> Bool
  (mt (nativeGcText)
    ((none) false)
    ((some text) (not (stringContains? text "asl_gc_shadow_top"))))

fn runTests -> Bool
  (do (assert (testWasmMarkSkipsNativeStack) "wasm collector branches from its root hooks to the shadow-root frames, then to explicit roots")
      (assert (testWasmMarkOmitsNativeStackBase) "wasm collector omits the native stack-base call")
      (assert (testWasmMarkOmitsNativeStackBranch) "wasm collector omits the native stack branch")
      (assert (testNativeMarkRetainsConservativeStack) "native collector keeps the conservative stack path")
      (assert (testWasmMarkWalksShadowFrames) "wasm collector defines the shadow-root chain head and marks from it")
      (assert (testNativeHasNoShadowFrames) "native collector has no shadow-root chain")
      true)
