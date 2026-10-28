(module asl-target-llvm/tests/llvmPackageAcceptanceTest
  :x [testPackageIntegrity! testLlvmTypeAndSsaGeneration testLlvmNativeCompilation! testDualPolarityRefutations! RunTests! runTests]
  :i [(asl-ir/types :a irTy)
      (asl-target-llvm/types :a ty)
      (asl-target-llvm/emit :a em)
      (asl-tools/fleet/run :a run)])

fn testPackageIntegrity! -> Bool
  (let [(mRes (fileReadString "asl/packages/asl-target-llvm/manifest.asn"))
        (gRes (fileReadString "asl/packages/asl-target-llvm/src/ssa.asl"))
        (tRes (fileReadString "asl/packages/asl-target-llvm/src/types.asl"))
        (eRes (fileReadString "asl/packages/asl-target-llvm/src/emit.asl"))
        (mainRes (fileReadString "asl/packages/asl-target-llvm/src/main.asl"))]
    (match mRes
      ((err e) (assert false (str "Failed to read manifest.asn: " e)))
      ((ok mSrc)
        (do
          (assert (stringContains? mSrc "asl-target-llvm") "manifest defines asl-target-llvm")
          (assert (stringContains? mSrc ":aslFirst true") "manifest asserts aslFirst true")
          (refute (stringContains? mSrc "JavaScriptCore") "manifest has zero JSC references"))))
    (match gRes
      ((err e2) (assert false (str "Failed to read grammar.asn: " e2)))
      ((ok gSrc)
        (do
          (assert (stringContains? gSrc "emitLlvmModule") "SSA source exports emitLlvmModule")
          (assert (stringContains? gSrc "emitLlvmProgram") "SSA source exports emitLlvmProgram"))))
    (match tRes
      ((err e3) (assert false (str "Failed to read types.asl: " e3)))
      ((ok tSrc)
        (do
          (assert (stringContains? tSrc "emitLlvmType") "types.asl defines emitLlvmType")
          (refute (stringContains? tSrc "JavaScriptCore") "types.asl has zero foreign runtime references"))))
    (match eRes
      ((err e4) (assert false (str "Failed to read emit.asl: " e4)))
      ((ok eSrc)
        (do
          (assert (stringContains? eSrc "emitLlvmModule") "emit.asl defines emitLlvmModule")
          (assert (stringContains? eSrc "asl_floor_div") "emit.asl defines asl_floor_div helper")
          (assert (stringContains? eSrc "asl_floor_mod") "emit.asl defines asl_floor_mod helper")
          (refute (stringContains? eSrc "deprecated") "emit.asl has zero deprecated stubs"))))
    (match mainRes
      ((err e5) (assert false (str "Failed to read main.asl: " e5)))
      ((ok mainSrc)
        (do
          (assert (stringContains? mainSrc "emitLlvmModule") "main.asl exports emitLlvmModule")
          (assert (stringContains? mainSrc "emitLlvmProgram") "main.asl exports emitLlvmProgram"))))
    true)

fn testLlvmTypeAndSsaGeneration -> Bool
  (do
    (assert (= (ty/emitLlvmType (irTy/makeIrType "i64" "raw" false)) "i64") "i64 maps to i64")
    (refute (!= (ty/emitLlvmType (irTy/makeIrType "i64" "raw" false)) "i64") "i64 refutes non-i64")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "i32" "raw" false)) "i32") "i32 maps to i32")
    (refute (!= (ty/emitLlvmType (irTy/makeIrType "i32" "raw" false)) "i32") "i32 refutes non-i32")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "f64" "raw" false)) "double") "f64 maps to double")
    (refute (!= (ty/emitLlvmType (irTy/makeIrType "f64" "raw" false)) "double") "f64 refutes non-double")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "bool" "raw" false)) "i1") "bool maps to i1")
    (refute (!= (ty/emitLlvmType (irTy/makeIrType "bool" "raw" false)) "i1") "bool refutes non-i1")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "unit" "raw" false)) "void") "unit maps to void")
    (refute (!= (ty/emitLlvmType (irTy/makeIrType "unit" "raw" false)) "void") "unit refutes non-void")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "str" "raw" false)) "ptr") "str maps to ptr")
    (refute (!= (ty/emitLlvmType (irTy/makeIrType "str" "raw" false)) "ptr") "str refutes non-ptr")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "buf" "raw" true)) "ptr") "buf maps to ptr")
    (refute (!= (ty/emitLlvmType (irTy/makeIrType "buf" "raw" true)) "ptr") "buf refutes non-ptr")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "option" "tagged" false)) "{ i1, i64 }") "tagged option maps to struct")
    (refute (!= (ty/emitLlvmType (irTy/makeIrType "option" "tagged" false)) "{ i1, i64 }") "tagged option refutes non-struct")
    (let [(eDiv (irTy/IrExpr :kind "binop" :op "/" :left "x" :right "y" :args (list) :ty (irTy/makeIrType "i64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))
          (eShl (irTy/IrExpr :kind "binop" :op "shl" :left "a" :right "b" :args (list) :ty (irTy/makeIrType "i64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))
          (divStr (em/emitLlvmExpr eDiv "t0" (irTy/makeIrType "i64" "raw" false)))
          (shlStr (em/emitLlvmExpr eShl "t1" (irTy/makeIrType "i64" "raw" false)))]
      (assert (stringContains? divStr "call i64 @asl_floor_div(i64 %x, i64 %y)") "emits floor division call")
      (refute (not (stringContains? divStr "call i64 @asl_floor_div(i64 %x, i64 %y)")) "refutes missing floor div call")
      (assert (stringContains? shlStr "and i64 %b, 63") "emits masked shift count")
      (refute (not (stringContains? shlStr "and i64 %b, 63")) "refutes unmasked shift count"))
    true)

fn testLlvmNativeCompilation! -> Bool
  (let [(fDiv "tests/fixtures/llvm/div_mod.ll")
        (fShift "tests/fixtures/llvm/shift_mask.ll")
        (fWrap "tests/fixtures/llvm/int_wrap.ll")
        (fOpt "tests/fixtures/llvm/option_scalar.ll")]
    (do
      (assert (fileExists? fDiv) "div_mod.ll fixture exists on disk")
      (assert (fileExists? fShift) "shift_mask.ll fixture exists on disk")
      (assert (fileExists? fWrap) "int_wrap.ll fixture exists on disk")
      (assert (fileExists? fOpt) "option_scalar.ll fixture exists on disk")
      (let [(cDiv (run/runOneLimited (run/job (list "clang" "-x" "ir" "-c" "-o" "/dev/null" fDiv) "." (run/childEnv (list))) (run/limits 180 8)))
            (cShift (run/runOneLimited (run/job (list "clang" "-x" "ir" "-c" "-o" "/dev/null" fShift) "." (run/childEnv (list))) (run/limits 180 8)))
            (cWrap (run/runOneLimited (run/job (list "clang" "-x" "ir" "-c" "-o" "/dev/null" fWrap) "." (run/childEnv (list))) (run/limits 180 8)))
            (cOpt (run/runOneLimited (run/job (list "clang" "-x" "ir" "-c" "-o" "/dev/null" fOpt) "." (run/childEnv (list))) (run/limits 180 8)))]
        (assert (= cDiv.exit 0) "clang validates div_mod.ll LLVM IR with exit code 0")
        (refute (!= cDiv.exit 0) "clang must not fail on div_mod.ll")
        (assert (= cShift.exit 0) "clang validates shift_mask.ll LLVM IR with exit code 0")
        (refute (!= cShift.exit 0) "clang must not fail on shift_mask.ll")
        (assert (= cWrap.exit 0) "clang validates int_wrap.ll LLVM IR with exit code 0")
        (refute (!= cWrap.exit 0) "clang must not fail on int_wrap.ll")
        (assert (= cOpt.exit 0) "clang validates option_scalar.ll LLVM IR with exit code 0")
        (refute (!= cOpt.exit 0) "clang must not fail on option_scalar.ll")
        true)))

fn testDualPolarityRefutations! -> Bool
  (let [(fBad "tests/fixtures/llvm/invalid_syntax.ll")]
    (do
      (assert (fileExists? fBad) "invalid_syntax.ll fixture exists on disk")
      (let [(cBad (run/runOneLimited (run/job (list "clang" "-x" "ir" "-c" "-o" "/dev/null" fBad) "." (run/childEnv (list))) (run/limits 180 8)))]
        (assert (!= cBad.exit 0) "clang rejects invalid LLVM IR assembly with non-zero exit code")
        (refute (= cBad.exit 0) "clang must not succeed on invalid LLVM IR")
        (assert (stringContains? cBad.out "error") "clang diagnostic contains error keyword")
        true)))

fn RunTests! -> Bool
  (do
    (assert (testPackageIntegrity!) "testPackageIntegrity")
    (assert (testLlvmTypeAndSsaGeneration) "testLlvmTypeAndSsaGeneration")
    (assert (testLlvmNativeCompilation!) "testLlvmNativeCompilation")
    (assert (testDualPolarityRefutations!) "testDualPolarityRefutations")
    true)

fn ! runTests -> Bool
  (RunTests!)
