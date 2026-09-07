(module asl-codegen/tests/emit-wat-test
  :d "Unit tests for WebAssembly Text (WAT) code generator."
  :x [run-tests]
  :i [(emit-wat :a w)])

(df test-wat-type [] -> Bool
  :d "Verifies AgentScript to WebAssembly type mapping."
  (and (= (w/wat-type "I64") "i64")
       (and (= (w/wat-type "I32") "i32")
            (and (= (w/wat-type "Bool") "i32")
                 (and (= (w/wat-type "F64") "f64")
                      (= (w/wat-type "Unit") "void"))))))

(df test-wat-op [] -> Bool
  :d "Verifies WebAssembly opcode selection."
  (and (= (w/wat-op "+" "I64") "i64.add")
       (and (= (w/wat-op "-" "I64") "i64.sub")
            (and (= (w/wat-op "*" "I64") "i64.mul")
                 (and (= (w/wat-op "/" "I64") "i64.div_s")
                      (and (= (w/wat-op "=" "I64") "i64.eq")
                           (= (w/wat-op "<" "I64") "i64.lt_s")))))))

(df test-wat-const [] -> Bool
  :d "Verifies constant instruction formatting."
  (and (= (w/wat-const "42" "I64") "(i64.const 42)")
       (= (w/wat-const "1" "Bool") "(i32.const 1)")))

(df test-wat-fn [] -> Bool
  :d "Verifies WebAssembly function declaration."
  (let [(fn-str (w/wat-fn "add" "(param $a i64) (param $b i64)" "I64" "i64.add (local.get $a) (local.get $b)" true))]
    (and (string-contains? fn-str "(func $add (export \"add\")")
         (and (string-contains? fn-str "(param $a i64)")
              (string-contains? fn-str "(result i64)")))))

(df test-wat-mod [] -> Bool
  :d "Verifies module envelope emission."
  (let [(mod-str (w/wat-mod "  (func $dummy)" true))]
    (and (string-contains? mod-str "(module")
         (and (string-contains? mod-str "(memory (export \"memory\") 1)")
              (string-contains? mod-str "(func $dummy)")))))

(df test-wat-emit [] -> Bool
  :d "Verifies binary arithmetic module emission."
  (let [(mod-str (w/wat-emit "calc" "x" "y" "+" "I64"))]
    (and (string-contains? mod-str "(module")
         (and (string-contains? mod-str "(func $calc (export \"calc\")")
              (and (string-contains? mod-str "(param $x i64)")
                   (string-contains? mod-str "i64.add (local.get $x) (local.get $y)"))))))

(df run-tests [] -> Bool
  :d "Runs all WebAssembly codegen unit tests."
  (and (test-wat-type)
       (and (test-wat-op)
            (and (test-wat-const)
                 (and (test-wat-fn)
                      (and (test-wat-mod)
                           (test-wat-emit)))))))
