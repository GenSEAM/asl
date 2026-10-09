(module asl-target-c/tests/targetCTest
  :x [testC11Types testC11Closure testC11Panic testC11StandaloneCases testC11Expressions testC11SourceCompiles testC11SourceMissingMain testC11SourceNullaryConstruct testC11MainWrapperRecordReturn testC11FloorDivOverflowGuard runTests]
  :i [(asl-ir/types :a irTy)
      (asl-target-c/types :a ty)
      (asl-target-c/emit :a em)])

fn testC11Types -> Bool
  (do
    (assert (= (ty/emitC11Type (irTy/makeIrType "i64" "raw" false)) "int64_t") "i64 maps to int64_t")
    (refute (!= (ty/emitC11Type (irTy/makeIrType "i64" "raw" false)) "int64_t") "i64 refutes non-int64_t")
    (assert (= (ty/emitC11Type (irTy/makeIrType "i32" "raw" false)) "int32_t") "i32 maps to int32_t")
    (refute (!= (ty/emitC11Type (irTy/makeIrType "i32" "raw" false)) "int32_t") "i32 refutes non-int32_t")
    (assert (= (ty/emitC11Type (irTy/makeIrType "f64" "raw" false)) "double") "f64 maps to double")
    (refute (!= (ty/emitC11Type (irTy/makeIrType "f64" "raw" false)) "double") "f64 refutes non-double")
    (assert (= (ty/emitC11Type (irTy/makeIrType "bool" "raw" false)) "bool") "bool maps to bool")
    (refute (!= (ty/emitC11Type (irTy/makeIrType "bool" "raw" false)) "bool") "bool refutes non-bool")
    (assert (= (ty/emitC11Type (irTy/makeIrType "unit" "raw" false)) "void") "unit maps to void")
    (refute (!= (ty/emitC11Type (irTy/makeIrType "unit" "raw" false)) "void") "unit refutes non-void")
    (assert (= (ty/emitC11Type (irTy/makeIrType "str" "raw" false)) "const char*") "str maps to const char*")
    (refute (!= (ty/emitC11Type (irTy/makeIrType "str" "raw" false)) "const char*") "str refutes non-const char*")
    (assert (= (ty/emitC11Type (irTy/makeIrType "buf" "raw" true)) "asl_buf_t") "buf maps to asl_buf_t")
    (refute (!= (ty/emitC11Type (irTy/makeIrType "buf" "raw" true)) "asl_buf_t") "buf refutes non-asl_buf_t")
    (assert (= (ty/emitC11Type (irTy/makeIrType "option" "tagged" false)) "asl_opt_i64_t") "tagged option maps to asl_opt_i64_t")
    (refute (!= (ty/emitC11Type (irTy/makeIrType "option" "tagged" false)) "asl_opt_i64_t") "tagged option refutes non-asl_opt_i64_t")
    (assert (= (ty/emitC11Type (irTy/makeIrType "option" "nullable" false)) "void*") "nullable option maps to void*")
    (refute (!= (ty/emitC11Type (irTy/makeIrType "option" "nullable" false)) "void*") "nullable option refutes non-void*")
    true)

fn testC11Closure -> Bool
  (let [(cStr (ty/emitC11Closure "captureEnv" (list "x" "y")))]
    (do
      (assert (stringContains? cStr "typedef struct {") "contains struct header")
      (refute (not (stringContains? cStr "typedef struct {")) "refutes missing struct header")
      (assert (stringContains? cStr "int64_t x;") "contains field x")
      (assert (stringContains? cStr "int64_t y;") "contains field y")
      (assert (stringContains? cStr "} asl_env_captureEnv_t;") "contains typedef footer")
      (refute (not (stringContains? cStr "} asl_env_captureEnv_t;")) "refutes missing typedef footer")
      true))

fn testC11Panic -> Bool
  (let [(pStr (ty/emitC11Panic 42 "unreachable path reached"))]
    (do
      (assert (stringContains? pStr "PANIC: unreachable path reached") "contains panic message")
      (assert (stringContains? pStr "exit(42);") "contains exit code 42")
      (refute (not (stringContains? pStr "exit(42);")) "refutes missing exit code 42")
      true))

fn testC11StandaloneCases -> Bool
  (let [(cDiv (em/emitC11StandaloneCase "div_mod_positive"))
        (cShift (em/emitC11StandaloneCase "shift_mask_overflow"))
        (cOpt (em/emitC11StandaloneCase "option_unit_repr"))]
    (do
      (assert (stringContains? cDiv "asl_floor_div(14, 3)") "contains floor div")
      (assert (stringContains? cDiv "asl_floor_mod(14, 3)") "contains floor mod")
      (assert (stringContains? cShift "(67 & 63)") "contains masked shift")
      (assert (stringContains? cOpt "asl_opt_unit_t") "contains option unit struct")
      true))

fn testC11Expressions -> Bool
  (let [(eAdd (irTy/IrExpr :kind "binop" :op "+" :left "a" :right "b" :args (list) :ty (irTy/makeIrType "i64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))
        (eDiv (irTy/IrExpr :kind "binop" :op "/" :left "a" :right "b" :args (list) :ty (irTy/makeIrType "i64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))
        (eShl (irTy/IrExpr :kind "binop" :op "shl" :left "x" :right "n" :args (list) :ty (irTy/makeIrType "i64" "raw" false) :wrap "wrap" :shiftMask false :divModFloor false :codeLabel ""))]
    (do
      (assert (stringContains? (em/emitC11Expr eAdd) "(uint64_t)(a) + (uint64_t)(b)") "emits wrapped addition")
      (assert (stringContains? (em/emitC11Expr eDiv) "asl_floor_div(a, b)") "emits floor division")
      (refute (not (stringContains? (em/emitC11Expr eDiv) "asl_floor_div(a, b)")) "refutes missing floor division")
      (assert (stringContains? (em/emitC11Expr eShl) "& 63") "emits masked shift count")
      (refute (not (stringContains? (em/emitC11Expr eShl) "& 63")) "refutes missing masked shift")
      true))

fn testC11SourceCompiles -> Bool
  (let [(src (stringJoin (list "(module smoke :x [main] :i [])" "" "fn ! main -> (Result Int64 String)" "  (ok 42)") "\n"))
        (res (em/emitC11Source src "smoke.asl"))]
    (do
      (assert (mt res ((ok _) true) ((err _) false)) "emitC11Source compiles a real main returning (ok 42)")
      (assert (mt res ((ok code) (stringContains? code "asl_rt_exit_code")) ((err _) false)) "emitted program routes the exit code through asl_rt_exit_code")
      (assert (mt res ((ok code) (stringContains? code "int main(void)")) ((err _) false)) "emitted program defines a C main entry point")
      (assert (mt res ((ok code) (stringContains? code "INT64_C(42)")) ((err _) false)) "emitted program contains the literal the source returns")
      true))

fn testC11SourceMissingMain -> Bool
  (let [(src (stringJoin (list "(module noMain :x [helper] :i [])" "" "fn helper -> Int64" "  1") "\n"))
        (res (em/emitC11Source src "noMain.asl"))]
    (do
      (assert (mt res ((ok _) false) ((err m) (stringContains? m "entry function 'main' is not defined"))) "a module without main is refused naming the missing entry")
      true))

fn testC11SourceNullaryConstruct -> Bool
  (let [(src (stringJoin (list "(module flagMod :x [main] :i [])" "" "(enum Flag (:c on []) (:c off []))" "" "fn ! main -> (Result Int64 String)" "  (mt on" "    (on (ok 1))" "    (off (ok 0)))") "\n"))
        (res (em/emitC11Source src "flagMod.asl"))]
    (do
      (assert (mt res ((ok _) true) ((err _) false)) "emitC11Source compiles a nullary enum variant construction")
      (assert (mt res ((ok code) (stringContains? code "(AslVal*)0")) ((err _) false)) "a 0-field construct emits a typed null pointer, not an empty compound literal")
      true))

fn testC11MainWrapperRecordReturn -> Bool
  (let [(f (irTy/ssaFunction "main" (list) (list) (irTy/tyRec "Point") (list)))
        (m (irTy/ssaModule "recCMain" (list) (list) (list) (list) (list) (list f)))
        (wrapper (em/c11SMainWrapper m f))]
    (do
      (assert (stringContains? wrapper "int main(void) {") "a record-returning entry still defines a C main entry point")
      (assert (stringContains? wrapper "AslVal result = asl_main_fn();") "a record-returning entry calls main and keeps the result an AslVal")
      (assert (stringContains? wrapper "return asl_rt_exit_code(result);") "a record-returning entry routes its result through asl_rt_exit_code like a plain Val return")
      true))

fn testC11FloorDivOverflowGuard -> Bool
  (let [(cDiv (em/emitC11StandaloneCase "div_mod_positive"))]
    (do
      (assert (stringContains? cDiv "if (a == INT64_MIN && b == -1) { return INT64_MIN; }") "floor div guards INT64_MIN / -1")
      (assert (stringContains? cDiv "if (b == -1) { return 0; }") "floor mod guards x % -1")
      true))

fn ! runTests -> Bool
  (do
    (assert (testC11Types) "testC11Types")
    (assert (testC11Closure) "testC11Closure")
    (assert (testC11Panic) "testC11Panic")
    (assert (testC11StandaloneCases) "testC11StandaloneCases")
    (assert (testC11Expressions) "testC11Expressions")
    (assert (testC11SourceCompiles) "testC11SourceCompiles")
    (assert (testC11SourceMissingMain) "testC11SourceMissingMain")
    (assert (testC11SourceNullaryConstruct) "testC11SourceNullaryConstruct")
    (assert (testC11MainWrapperRecordReturn) "testC11MainWrapperRecordReturn")
    (assert (testC11FloorDivOverflowGuard) "testC11FloorDivOverflowGuard")
    true)
