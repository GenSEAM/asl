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

(df test-wasi-imports [] -> Bool
  :d "Verifies WASI host import declarations emission."
  (let [(imports (w/emit-wasi-imports))]
    (assert (string-contains? imports "(import \"wasi_snapshot_preview1\" \"fd_write\"") "WASI imports must declare fd_write")
    (assert (string-contains? imports "(import \"wasi_snapshot_preview1\" \"fd_read\"") "WASI imports must declare fd_read")
    (assert (string-contains? imports "(import \"wasi_snapshot_preview1\" \"proc_exit\"") "WASI imports must declare proc_exit")
    (assert (string-contains? imports "(import \"wasi_snapshot_preview1\" \"clock_time_get\"") "WASI imports must declare clock_time_get")
    (assert (string-contains? imports "(func $fd_write (param i32 i32 i32 i32) (result i32))") "fd_write must take 4 i32 params and return i32")
    (assert (string-contains? imports "(func $fd_read (param i32 i32 i32 i32) (result i32))") "fd_read must take 4 i32 params and return i32")
    (assert (string-contains? imports "(func $proc_exit (param i32))") "proc_exit must take 1 i32 param with no result clause")
    (assert (string-contains? imports "(func $clock_time_get (param i32 i64 i32) (result i32))") "clock_time_get must take i32 i64 i32 and return i32")
    true))

(df test-wasi-fd-write [] -> Bool
  :d "Verifies WASI fd_write invocation lowering."
  (let [(stdout-call (w/emit-wasi-fd-write 1 1024 1 2048))
        (stderr-call (w/emit-wasi-fd-write 2 4096 2 5120))]
    (assert (string-contains? stdout-call "call $fd_write") "stdout call must invoke call $fd_write")
    (assert (string-contains? stdout-call "(i32.const 1)") "stdout call must contain fd 1")
    (assert (string-contains? stdout-call "(i32.const 1024)") "stdout call must contain iovs offset 1024")
    (assert (string-contains? stdout-call "(i32.const 1)") "stdout call must contain iovs length 1")
    (assert (string-contains? stdout-call "(i32.const 2048)") "stdout call must contain nwritten offset 2048")
    (assert (string-contains? stderr-call "(i32.const 2)") "stderr call must contain fd 2")
    (assert (and (string-contains? stderr-call "(i32.const 4096)") (string-contains? stderr-call "(i32.const 5120)")) "stderr call must contain memory offsets 4096 and 5120")
    true))

(df test-wasi-proc-exit [] -> Bool
  :d "Verifies WASI proc_exit invocation lowering."
  (let [(exit-0 (w/emit-wasi-proc-exit 0))
        (exit-1 (w/emit-wasi-proc-exit 1))
        (exit-137 (w/emit-wasi-proc-exit 137))]
    (assert (string-contains? exit-0 "call $proc_exit") "proc-exit lowering must invoke call $proc_exit")
    (assert (string-contains? exit-0 "(i32.const 0)") "exit code 0 must format with i32.const 0")
    (assert (string-contains? exit-1 "(i32.const 1)") "exit code 1 must format with i32.const 1")
    (assert (string-contains? exit-137 "(i32.const 137)") "custom exit code 137 must format with i32.const 137")
    (assert (not (string-contains? exit-0 "result")) "proc-exit must not emit a result type clause")
    true))

(df test-wasi-clock-time-get [] -> Bool
  :d "Verifies WASI clock_time_get invocation lowering."
  (let [(realtime-call (w/emit-wasi-clock-time-get 0 1000 8192))
        (monotonic-call (w/emit-wasi-clock-time-get 1 0 8200))]
    (assert (string-contains? realtime-call "call $clock_time_get") "clock_time_get lowering must invoke call $clock_time_get")
    (assert (string-contains? realtime-call "(i32.const 0)") "realtime clock-id must be (i32.const 0)")
    (assert (string-contains? realtime-call "(i64.const 1000)") "precision argument must use i64.const 1000")
    (assert (string-contains? realtime-call "(i32.const 8192)") "time-offset argument must be (i32.const 8192)")
    (assert (string-contains? monotonic-call "(i32.const 1)") "monotonic clock-id must be (i32.const 1)")
    (assert (string-contains? monotonic-call "(i64.const 0)") "monotonic precision argument must be (i64.const 0)")
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
        (_t8 (test-emit-wat-module))
        (_t9 (test-wasi-imports))
        (_t10 (test-wasi-fd-write))
        (_t11 (test-wasi-proc-exit))
        (_t12 (test-wasi-clock-time-get))]
    true))
