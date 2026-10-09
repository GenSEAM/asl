(module asl/packages/asl-target-llvm/tests/llvmRuntimeHelpersTest
  :x [testLlvmRuntimeTypes testLlvmPreambleBuiltins testLlvmExpressionLowering runTests]
  :i [(asl-ir/types :a irTy)
      (asl-target-llvm/types :a ty)
      (asl-target-llvm/emit :a em)])

fn testLlvmRuntimeTypes -> Bool
  (do
    (assert (= (ty/emitLlvmType (irTy/makeIrType "str" "raw" false)) "ptr") "str maps to ptr")
    (refute (!= (ty/emitLlvmType (irTy/makeIrType "str" "raw" false)) "ptr") "str refutes non-ptr")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "list" "raw" false)) "ptr") "list maps to ptr")
    (refute (!= (ty/emitLlvmType (irTy/makeIrType "list" "raw" false)) "ptr") "list refutes non-ptr")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "map" "raw" false)) "ptr") "map maps to ptr")
    (refute (!= (ty/emitLlvmType (irTy/makeIrType "map" "raw" false)) "ptr") "map refutes non-ptr")
    true)

fn testLlvmPreambleBuiltins -> Bool
  (let [(preamble (em/llvmPreamble "arm64-apple-macosx"))]
    (do
      (assert (stringContains? preamble "@asl_string_len") "preamble declares or defines @asl_string_len")
      (refute (not (stringContains? preamble "@asl_string_len")) "refutes missing @asl_string_len")
      (assert (stringContains? preamble "@asl_string_slice") "preamble declares or defines @asl_string_slice")
      (refute (not (stringContains? preamble "@asl_string_slice")) "refutes missing @asl_string_slice")
      (assert (stringContains? preamble "@asl_string_cmp") "preamble declares or defines @asl_string_cmp")
      (refute (not (stringContains? preamble "@asl_string_cmp")) "refutes missing @asl_string_cmp")
      (assert (stringContains? preamble "@asl_string_concat") "preamble declares or defines @asl_string_concat")
      (refute (not (stringContains? preamble "@asl_string_concat")) "refutes missing @asl_string_concat")
      (assert (stringContains? preamble "@asl_println") "preamble declares or defines @asl_println")
      (refute (not (stringContains? preamble "@asl_println")) "refutes missing @asl_println")
      true))

fn testLlvmExpressionLowering -> Bool
  (let [(eCall (irTy/IrExpr :kind "call" :op "asl_string_len" :left "" :right "" :args (list "s0") :ty (irTy/makeIrType "i64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))
        (res (em/emitLlvmExpr eCall "r0" (irTy/makeIrType "i64" "raw" false)))]
    (do
      (assert (stringContains? res "call i64 @asl_string_len(ptr %s0)") "emits call to asl_string_len with ptr argument")
      (refute (not (stringContains? res "@asl_string_len")) "refutes missing call")
      true))

fn runTests -> Bool
  (do
    (assert (testLlvmRuntimeTypes) "testLlvmRuntimeTypes")
    (assert (testLlvmPreambleBuiltins) "testLlvmPreambleBuiltins")
    (assert (testLlvmExpressionLowering) "testLlvmExpressionLowering")
    true)
