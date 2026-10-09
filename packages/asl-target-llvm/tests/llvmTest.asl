(module asl-target-llvm/tests/llvmTest
  :x [testLlvmTypes testLlvmClosure testLlvmPanic testLlvmTargetTriple testLlvmExpressions testLlvmStatements testLlvmModule testLlvmFloatAndOverflow testLlvmSourceLowering testLlvmSourceMissingEntry runTests]
  :i [(asl-ir/types :a irTy)
      (asl-target-llvm/types :a ty)
      (asl-target-llvm/emit :a em)
      (asl-target-llvm :a llvm)])

fn testLlvmTypes -> Bool
  (do
    (assert (= (ty/emitLlvmType (irTy/makeIrType "i64" "raw" false)) "i64") "i64 maps to i64")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "i32" "raw" false)) "i32") "i32 maps to i32")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "f64" "raw" false)) "double") "f64 maps to double")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "bool" "raw" false)) "i1") "bool maps to i1")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "unit" "raw" false)) "void") "unit maps to void")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "str" "raw" false)) "ptr") "str maps to ptr")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "buf" "raw" true)) "ptr") "buf maps to ptr")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "option" "tagged" false)) "{ i1, i64 }") "tagged option maps to struct")
    (assert (= (ty/emitLlvmType (irTy/makeIrType "option" "nullable" false)) "ptr") "nullable option maps to ptr")
    true)

fn testLlvmClosure -> Bool
  (let [(cStr (ty/emitLlvmClosure "workerState" (list "x" "y")))]
    (do
      (assert (stringContains? cStr "%asl_env_workerState_t = type {") "closure defines env type")
      (assert (stringContains? cStr "i64, i64") "closure fields typed i64")
      true))

fn testLlvmPanic -> Bool
  (let [(pStr (ty/emitLlvmPanic 42 "unreachable"))]
    (do
      (assert (stringContains? pStr "call void @asl_panic(i64 42)") "panic calls asl_panic")
      (assert (stringContains? pStr "unreachable") "panic terminates with unreachable")
      true))

fn testLlvmTargetTriple -> Bool
  (let [(tMac (ty/emitLlvmTargetTriple "arm64-apple-darwin"))
        (tLinux (ty/emitLlvmTargetTriple "x86_64-unknown-linux-gnu"))
        (tWasm (ty/emitLlvmTargetTriple "wasm32-unknown-wasi"))]
    (do
      (assert (stringContains? tMac "target triple = \"arm64-apple-macosx") "resolves macos arm64 triple")
      (assert (stringContains? tLinux "target triple = \"x86_64-unknown-linux-gnu\"") "resolves linux x64 triple")
      (assert (stringContains? tWasm "target triple = \"wasm32-unknown-wasi\"") "resolves wasm triple")
      true))

fn testLlvmExpressions -> Bool
  (let [(eAdd (irTy/IrExpr :kind "binop" :op "+" :left "a" :right "b" :args (list) :ty (irTy/makeIrType "i64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))
        (eDiv (irTy/IrExpr :kind "binop" :op "/" :left "a" :right "b" :args (list) :ty (irTy/makeIrType "i64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))
        (eShl (irTy/IrExpr :kind "binop" :op "shl" :left "x" :right "n" :args (list) :ty (irTy/makeIrType "i64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))
        (eCmp (irTy/IrExpr :kind "cmp" :op "<" :left "a" :right "b" :args (list) :ty (irTy/makeIrType "bool" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))]
    (do
      (assert (stringContains? (em/emitLlvmExpr eAdd "t0" (irTy/makeIrType "i64" "raw" false)) "%t0 = add i64 %a, %b") "emits add SSA instruction")
      (assert (stringContains? (em/emitLlvmExpr eDiv "t1" (irTy/makeIrType "i64" "raw" false)) "call i64 @asl_floor_div(i64 %a, i64 %b)") "emits floor div call")
      (assert (stringContains? (em/emitLlvmExpr eShl "t2" (irTy/makeIrType "i64" "raw" false)) "and i64 %n, 63") "emits masked shift")
      (assert (stringContains? (em/emitLlvmExpr eCmp "t3" (irTy/makeIrType "bool" "raw" false)) "%t3 = icmp slt i64 %a, %b") "emits icmp slt instruction")
      true))

fn testLlvmStatements -> Bool
  (let [(sLet (irTy/makeIrLet "r0" (irTy/makeIrType "i64" "raw" false) (irTy/IrExpr :kind "binop" :op "+" :left "x" :right "1" :args (list) :ty (irTy/makeIrType "i64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel "")))
        (sRet (irTy/makeIrReturn "r0" (irTy/makeIrType "i64" "raw" false)))
        (sDrop (irTy/makeIrDrop "p0" (irTy/makeIrType "str" "raw" false)))
        (sLoop1 (irTy/IrStmt :kind "loop" :target "outer" :field "" :value "" :ty (irTy/makeIrType "unit" "raw" false) :expr (irTy/IrExpr :kind "atom" :op "" :left "" :right "" :args (list) :ty (irTy/makeIrType "unit" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel "") :label "outer" :args (list) :scrutinee "" :cases (list) :defaultBody (list) :loopBody (list)))
        (sLoop2 (irTy/IrStmt :kind "loop" :target "inner" :field "" :value "" :ty (irTy/makeIrType "unit" "raw" false) :expr (irTy/IrExpr :kind "atom" :op "" :left "" :right "" :args (list) :ty (irTy/makeIrType "unit" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel "") :label "inner" :args (list) :scrutinee "" :cases (list) :defaultBody (list) :loopBody (list)))
        (sSwitch1 (irTy/IrStmt :kind "switch" :target "" :field "" :value "" :ty (irTy/makeIrType "unit" "raw" false) :expr (irTy/IrExpr :kind "atom" :op "" :left "" :right "" :args (list) :ty (irTy/makeIrType "unit" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel "") :label "swA" :args (list) :scrutinee "tagA" :cases (list (irTy/IrSwitchCase :tag "0" :bindings (list) :body (list))) :defaultBody (list) :loopBody (list)))
        (sSwitch2 (irTy/IrStmt :kind "switch" :target "" :field "" :value "" :ty (irTy/makeIrType "unit" "raw" false) :expr (irTy/IrExpr :kind "atom" :op "" :left "" :right "" :args (list) :ty (irTy/makeIrType "unit" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel "") :label "swB" :args (list) :scrutinee "tagB" :cases (list (irTy/IrSwitchCase :tag "0" :bindings (list) :body (list))) :defaultBody (list) :loopBody (list)))]
    (do
      (assert (stringContains? (em/emitLlvmStmt sLet) "%r0 = add i64 %x, 1") "let statement emits add")
      (assert (stringContains? (em/emitLlvmStmt sRet) "ret i64 %r0") "return statement emits ret")
      (assert (stringContains? (em/emitLlvmStmt sDrop) "call void @asl_release(ptr %p0)") "drop statement emits release")
      (assert (stringContains? (em/emitLlvmStmt sLoop1) "%loop_entry_outer") "loop1 has outer label")
      (assert (stringContains? (em/emitLlvmStmt sLoop2) "%loop_entry_inner") "loop2 has inner label")
      (refute (= (em/emitLlvmStmt sLoop1) (em/emitLlvmStmt sLoop2)) "distinct loops have distinct labels")
      (assert (stringContains? (em/emitLlvmStmt sSwitch1) "switch_default_swA") "switch1 has swA default")
      (assert (stringContains? (em/emitLlvmStmt sSwitch2) "switch_default_swB") "switch2 has swB default")
      (refute (= (em/emitLlvmStmt sSwitch1) (em/emitLlvmStmt sSwitch2)) "distinct switches have distinct labels")
      true))

fn testLlvmModule -> Bool
  (let [(paramA (irTy/makeIrParam "a" (irTy/makeIrType "i64" "raw" false)))
        (paramB (irTy/makeIrParam "b" (irTy/makeIrType "i64" "raw" false)))
        (stmtAdd (irTy/makeIrLet "t0" (irTy/makeIrType "i64" "raw" false) (irTy/IrExpr :kind "binop" :op "+" :left "a" :right "b" :args (list) :ty (irTy/makeIrType "i64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel "")))
        (stmtRet (irTy/makeIrReturn "t0" (irTy/makeIrType "i64" "raw" false)))
        (fnCalc (irTy/makeIrFunction "asl_main" (list paramA paramB) (irTy/makeIrType "i64" "raw" false) (list stmtAdd stmtRet)))
        (mod (irTy/makeIrModule "calcMod" "llvm" (list fnCalc)))
        (emitRes (em/emitLlvmModule mod))]
    (mt emitRes
      ((err diags) (do (assert false "emitLlvmModule returned error") false))
      ((ok modStr)
        (do
          (assert (stringContains? modStr "define i64 @asl_main(i64 %a, i64 %b)") "emitted module defines asl_main")
          (assert (stringContains? modStr "%t0 = add i64 %a, %b") "emitted module contains add instruction")
          (assert (stringContains? modStr "ret i64 %t0") "emitted module contains ret instruction")
          (assert (stringContains? modStr "define i32 @main(i32 %argc, ptr %argv)") "emitted module defines main wrapper")
          (assert (stringContains? modStr "call i64 @asl_main()") "main wrapper calls asl_main")
          true))))

fn testLlvmFloatAndOverflow -> Bool
  (let [(eFAdd (irTy/IrExpr :kind "binop" :op "+" :left "x" :right "y" :args (list) :ty (irTy/makeIrType "f64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))
        (eFSub (irTy/IrExpr :kind "binop" :op "-" :left "x" :right "y" :args (list) :ty (irTy/makeIrType "f64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))
        (eFMul (irTy/IrExpr :kind "binop" :op "*" :left "x" :right "y" :args (list) :ty (irTy/makeIrType "f64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))
        (eFDiv (irTy/IrExpr :kind "binop" :op "/" :left "x" :right "y" :args (list) :ty (irTy/makeIrType "f64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))
        (eFCmp (irTy/IrExpr :kind "cmp" :op "<" :left "x" :right "y" :args (list) :ty (irTy/makeIrType "f64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))
        (preamble (em/llvmPreamble "arm64-apple-macosx"))]
    (do
      (assert (stringContains? (em/emitLlvmExpr eFAdd "f0" (irTy/makeIrType "f64" "raw" false)) "%f0 = fadd double %x, %y") "emits fadd double instruction")
      (refute (stringContains? (em/emitLlvmExpr eFAdd "f0" (irTy/makeIrType "f64" "raw" false)) "add i64") "fadd refutes integer add")
      (assert (stringContains? (em/emitLlvmExpr eFSub "f1" (irTy/makeIrType "f64" "raw" false)) "%f1 = fsub double %x, %y") "emits fsub double instruction")
      (assert (stringContains? (em/emitLlvmExpr eFMul "f2" (irTy/makeIrType "f64" "raw" false)) "%f2 = fmul double %x, %y") "emits fmul double instruction")
      (assert (stringContains? (em/emitLlvmExpr eFDiv "f3" (irTy/makeIrType "f64" "raw" false)) "%f3 = fdiv double %x, %y") "emits fdiv double instruction")
      (assert (stringContains? (em/emitLlvmExpr eFCmp "f4" (irTy/makeIrType "bool" "raw" false)) "%f4 = fcmp olt double %x, %y") "emits fcmp olt double instruction")
      (assert (stringContains? preamble "-9223372036854775808") "preamble guards INT64_MIN overflow")
      (assert (stringContains? preamble "memory(none) nounwind willreturn") "floor div and mod marked memory(none)")
      (assert (stringContains? preamble "memory(read) nounwind willreturn") "string len and cmp marked memory(read)")
      (assert (stringContains? preamble "dprintf(i32 2") "eprintln routes to stderr via dprintf")
      (assert (stringContains? preamble "@strnlen") "string slice uses strnlen optimization")
      true))

fn divModSource -> String
  (stringJoin (list "(module dm :x [dm])" "" "(fn dm [] -> Int64" "  (+ (/ -7 3) (mod -7 3)))") "\n")

fn testLlvmSourceLowering -> Bool
  (mt (llvm/emitLlvmSource (divModSource) "dm")
    ((err diags) (do (assert false (str "divMod source lowers: " (stringJoin (map (fn [(d irTy/IrDiag)] -> String d.message) diags) "; "))) false))
    ((ok code)
      (let [(divAt (stringIndexOf code "select i1 %$252.p.zero, i32 5, i32 3"))
            (modAt (stringIndexOf code "call void @rterr.int(i32 6)"))
            (addAt (stringIndexOf code "@llvm.sadd.with.overflow.i64(i64 %$252, i64 %$255)"))]
        (do
          (assert (stringContains? code "define tailcc i64 @dm()") "lowered source defines its function over raw i64, as its Int64 annotation says")
          (refute (stringContains? code "@asl_rt_int(i64 -7)") "the negative literal stays raw, never boxed")
          (refute (stringContains? code "@asl_rt_builtin") "no operator goes through the builtin by name")
          (refute (stringContains? code "@asl_rt_int_trap") "the deleted abi.c asl_rt_int_trap is neither declared nor called")
          (assert (and (some? divAt) (and (some? modAt) (some? addAt))) (str "division fails as the host does on a zero divisor (kind 5) or INT64_MIN by -1 (kind 3), mod on a zero divisor (kind 6), add on overflow:\n" code))
          (assert (and (< (optionOr divAt 0) (optionOr modAt 0)) (< (optionOr modAt 0) (optionOr addAt 0))) "operands are evaluated before the add that consumes them")
          (assert (stringContains? code "%$252 = sub i64 %$252.p.q, %$252.p.step") "division floors: a truncated quotient steps down when the remainder's sign differs from the divisor's")
          (assert (stringContains? code "%result = call tailcc i64 @dm()") "entry wrapper calls the entry function")
          (assert (stringContains? code "%code = trunc i64 %result to i32") "entry wrapper narrows the raw result to the exit code")
          true))))

fn testLlvmSourceMissingEntry -> Bool
  (mt (llvm/emitLlvmSource (divModSource) "absent")
    ((ok _) (do (assert false "a missing entry function is refused") false))
    ((err diags)
      (do
        (assert (listAny? (fn [(d irTy/IrDiag)] -> Bool (= d.code "ERR_LLVM_NO_ENTRY")) diags) "missing entry is reported as ERR_LLVM_NO_ENTRY")
        true)))

fn runTests -> Bool
  (do
    (assert (testLlvmTypes) "testLlvmTypes")
    (assert (testLlvmClosure) "testLlvmClosure")
    (assert (testLlvmPanic) "testLlvmPanic")
    (assert (testLlvmTargetTriple) "testLlvmTargetTriple")
    (assert (testLlvmExpressions) "testLlvmExpressions")
    (assert (testLlvmStatements) "testLlvmStatements")
    (assert (testLlvmModule) "testLlvmModule")
    (assert (testLlvmFloatAndOverflow) "testLlvmFloatAndOverflow")
    (assert (testLlvmSourceLowering) "testLlvmSourceLowering")
    (assert (testLlvmSourceMissingEntry) "testLlvmSourceMissingEntry")
    true)
