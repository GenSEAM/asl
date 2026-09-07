(module asl-codegen/tests/emit-wat-test
  :d "Unit tests for WebAssembly Text (WAT) code generator."
  :x [run-tests]
  :i [(emit-wat :a w)])

(df test-wat-type [] -> Bool
  :d "Verifies AgentScript to WebAssembly type mapping."
  (let [(t1 (w/wat-type "I64"))
        (t2 (w/wat-type "I32"))
        (t3 (w/wat-type "Bool"))
        (t4 (w/wat-type "F64"))
        (t5 (w/wat-type "Unit"))]
    (assert (= t1 "i64") "I64 must map to i64")
    (assert (= t2 "i32") "I32 must map to i32")
    (assert (= t3 "i32") "Bool must map to i32")
    (assert (= t4 "f64") "F64 must map to f64")
    (assert (= t5 "void") "Unit must map to void")
    true))

(df test-wat-op [] -> Bool
  :d "Verifies WebAssembly opcode selection."
  (let [(op-add (w/wat-op "+" "I64"))
        (op-sub (w/wat-op "-" "I64"))
        (op-mul (w/wat-op "*" "I64"))
        (op-div (w/wat-op "/" "I64"))
        (op-eq (w/wat-op "=" "I64"))
        (op-lt (w/wat-op "<" "I64"))]
    (assert (= op-add "i64.add") "Addition op must be i64.add")
    (assert (= op-sub "i64.sub") "Subtraction op must be i64.sub")
    (assert (= op-mul "i64.mul") "Multiplication op must be i64.mul")
    (assert (= op-div "i64.div_s") "Division op must be i64.div_s")
    (assert (= op-eq "i64.eq") "Equality op must be i64.eq")
    (assert (= op-lt "i64.lt_s") "Less-than op must be i64.lt_s")
    true))

(df test-wat-const [] -> Bool
  :d "Verifies constant instruction formatting."
  (let [(c1 (w/wat-const "42" "I64"))
        (c2 (w/wat-const "1" "Bool"))]
    (assert (= c1 "(i64.const 42)") "I64 constant must format with i64.const")
    (assert (= c2 "(i32.const 1)") "Bool constant must format with i32.const")
    true))

(df test-wat-fn [] -> Bool
  :d "Verifies WebAssembly function declaration."
  (let [(fn-str (w/wat-fn "add" "(param $a i64) (param $b i64)" "I64" "i64.add (local.get $a) (local.get $b)" true))]
    (assert (string-contains? fn-str "(func $add (export \"add\")") "Function declaration must contain export attribute")
    (assert (string-contains? fn-str "(param $a i64)") "Function declaration must contain parameter clause")
    (assert (string-contains? fn-str "(result i64)") "Function declaration must contain result clause")
    true))

(df test-wat-mod [] -> Bool
  :d "Verifies module envelope emission."
  (let [(mod-str (w/wat-mod "  (func $dummy)" true))]
    (assert (string-contains? mod-str "(module") "Module envelope must start with (module")
    (assert (string-contains? mod-str "(memory (export \"memory\") 1)") "Module envelope must include exported memory")
    (assert (string-contains? mod-str "(func $dummy)") "Module envelope must contain nested functions")
    true))

(df test-wat-emit [] -> Bool
  :d "Verifies binary arithmetic module emission."
  (let [(mod-str (w/wat-emit "calc" "x" "y" "+" "I64"))]
    (assert (string-contains? mod-str "(module") "Emitted module must contain module header")
    (assert (string-contains? mod-str "(func $calc (export \"calc\")") "Emitted module must contain calc function export")
    (assert (string-contains? mod-str "(param $x i64)") "Emitted module must contain param $x i64")
    (assert (string-contains? mod-str "i64.add (local.get $x) (local.get $y)") "Emitted module body must perform i64.add")
    true))

(df test-emit-wat-expr [] -> Bool
  :d "Verifies WebAssembly Text expression lowering for arithmetic and bindings."
  (let [(e1 (w/emit-wat-expr "+" "a" "b" "I32"))
        (e2 (w/emit-wat-expr "-" "x" "10" "I64"))
        (e3 (w/emit-wat-expr "*" "count" "(local.get $step)" "I32"))]
    (assert (string-contains? e1 "i32.add (local.get $a) (local.get $b)") "e1 must emit i32.add with local.get variables")
    (assert (string-contains? e2 "i64.sub (local.get $x) (i64.const 10)") "e2 must emit i64.sub with literal constant")
    (assert (string-contains? e3 "i32.mul (local.get $count) (local.get $step)") "e3 must emit i32.mul preserving subexpressions")
    true))

(df test-emit-wat-module [] -> Bool
  :d "Verifies full WebAssembly Text module lowering with exports and operations."
  (let [(expr-code (w/emit-wat-expr "+" "a" "b" "I32"))
        (fn-code (w/wat-fn "add" "(param $a i32) (param $b i32)" "I32" expr-code true))
        (mod-str (w/emit-wat-module (str "  " fn-code) true))]
    (assert (string-contains? mod-str "(module") "Module envelope must open with (module")
    (assert (string-contains? mod-str "(memory (export \"memory\") 1)") "Module must declare exported memory")
    (assert (string-contains? mod-str "(func $add (export \"add\")") "Module must declare exported add function")
    (assert (string-contains? mod-str "i32.add") "Module must contain i32.add instruction")
    true))

(df run-tests [] -> Bool
  :d "Runs all WebAssembly codegen unit tests."
  (let [(_t1 (test-wat-type))
        (_t2 (test-wat-op))
        (_t3 (test-wat-const))
        (_t4 (test-wat-fn))
        (_t5 (test-wat-mod))
        (_t6 (test-wat-emit))
        (_t7 (test-emit-wat-expr))
        (_t8 (test-emit-wat-module))]
    true))
