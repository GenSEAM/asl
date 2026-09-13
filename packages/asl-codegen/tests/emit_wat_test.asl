(module asl-codegen/tests/emitWatTest
  :d "Unit tests for WebAssembly Text (WAT) code generator."
  :x [runTests]
  :i [(emitWat :a w)])

(df testWatType [] -> Bool
  :d "Verifies AgentScript to WebAssembly type mapping."
  (let [(t1 (w/watType "I64"))
        (t2 (w/watType "I32"))
        (t3 (w/watType "Bool"))
        (t4 (w/watType "F64"))
        (t5 (w/watType "Unit"))]
    (assert (= t1 "i64") "I64 must map to i64")
    (assert (= t2 "i32") "I32 must map to i32")
    (assert (= t3 "i32") "Bool must map to i32")
    (assert (= t4 "f64") "F64 must map to f64")
    (assert (= t5 "void") "Unit must map to void")
    true))

(df testWatOp [] -> Bool
  :d "Verifies WebAssembly opcode selection."
  (let [(opAdd (w/watOp "+" "I64"))
        (opSub (w/watOp "-" "I64"))
        (opMul (w/watOp "*" "I64"))
        (opDiv (w/watOp "/" "I64"))
        (opEq (w/watOp "=" "I64"))
        (opLt (w/watOp "<" "I64"))]
    (assert (= opAdd "i64.add") "Addition op must be i64.add")
    (assert (= opSub "i64.sub") "Subtraction op must be i64.sub")
    (assert (= opMul "i64.mul") "Multiplication op must be i64.mul")
    (assert (= opDiv "i64.div_s") "Division op must be i64.div_s")
    (assert (= opEq "i64.eq") "Equality op must be i64.eq")
    (assert (= opLt "i64.lt_s") "Less-than op must be i64.lt_s")
    true))

(df testWatConst [] -> Bool
  :d "Verifies constant instruction formatting."
  (let [(c1 (w/watConst "42" "I64"))
        (c2 (w/watConst "1" "Bool"))]
    (assert (= c1 "(i64.const 42)") "I64 constant must format with i64.const")
    (assert (= c2 "(i32.const 1)") "Bool constant must format with i32.const")
    true))

(df testWatFn [] -> Bool
  :d "Verifies WebAssembly function declaration."
  (let [(fnStr (w/watFn "add" "(param $a i64) (param $b i64)" "I64" "i64.add (local.get $a) (local.get $b)" true))]
    (assert (string-contains? fnStr "(func $add (export \"add\")") "Function declaration must contain export attribute")
    (assert (string-contains? fnStr "(param $a i64)") "Function declaration must contain parameter clause")
    (assert (string-contains? fnStr "(result i64)") "Function declaration must contain result clause")
    true))

(df testWatMod [] -> Bool
  :d "Verifies module envelope emission."
  (let [(modStr (w/watMod "  (func $dummy)" true))]
    (assert (string-contains? modStr "(module") "Module envelope must start with (module")
    (assert (string-contains? modStr "(memory (export \"memory\") 1)") "Module envelope must include exported memory")
    (assert (string-contains? modStr "(func $dummy)") "Module envelope must contain nested functions")
    true))

(df testWatEmit [] -> Bool
  :d "Verifies binary arithmetic module emission."
  (let [(modStr (w/watEmit "calc" "x" "y" "+" "I64"))]
    (assert (string-contains? modStr "(module") "Emitted module must contain module header")
    (assert (string-contains? modStr "(func $calc (export \"calc\")") "Emitted module must contain calc function export")
    (assert (string-contains? modStr "(param $x i64)") "Emitted module must contain param $x i64")
    (assert (string-contains? modStr "i64.add (local.get $x) (local.get $y)") "Emitted module body must perform i64.add")
    true))

(df testEmitWatExpr [] -> Bool
  :d "Verifies WebAssembly Text expression lowering for arithmetic and bindings."
  (let [(e1 (w/emitWatExpr "+" "a" "b" "I32"))
        (e2 (w/emitWatExpr "-" "x" "10" "I64"))
        (e3 (w/emitWatExpr "*" "count" "(local.get $step)" "I32"))]
    (assert (string-contains? e1 "i32.add (local.get $a) (local.get $b)") "e1 must emit i32.add with local.get variables")
    (assert (string-contains? e2 "i64.sub (local.get $x) (i64.const 10)") "e2 must emit i64.sub with literal constant")
    (assert (string-contains? e3 "i32.mul (local.get $count) (local.get $step)") "e3 must emit i32.mul preserving subexpressions")
    true))

(df testEmitWatModule [] -> Bool
  :d "Verifies full WebAssembly Text module lowering with exports and operations."
  (let [(exprCode (w/emitWatExpr "+" "a" "b" "I32"))
        (fnCode (w/watFn "add" "(param $a i32) (param $b i32)" "I32" exprCode true))
        (modStr (w/emitWatModule (str "  " fnCode) true))]
    (assert (string-contains? modStr "(module") "Module envelope must open with (module")
    (assert (string-contains? modStr "(memory (export \"memory\") 1)") "Module must declare exported memory")
    (assert (string-contains? modStr "(func $add (export \"add\")") "Module must declare exported add function")
    (assert (string-contains? modStr "i32.add") "Module must contain i32.add instruction")
    true))

(df testWasiImports [] -> Bool
  :d "Verifies WASI host import declarations emission."
  (let [(imports (w/emitWasiImports))]
    (assert (string-contains? imports "(import \"wasi_snapshot_preview1\" \"fd_write\"") "WASI imports must declare fd_write")
    (assert (string-contains? imports "(import \"wasi_snapshot_preview1\" \"fd_read\"") "WASI imports must declare fd_read")
    (assert (string-contains? imports "(import \"wasi_snapshot_preview1\" \"proc_exit\"") "WASI imports must declare proc_exit")
    (assert (string-contains? imports "(import \"wasi_snapshot_preview1\" \"clock_time_get\"") "WASI imports must declare clock_time_get")
    (assert (string-contains? imports "(func $fd_write (param i32 i32 i32 i32) (result i32))") "fd_write must take 4 i32 params and return i32")
    (assert (string-contains? imports "(func $fd_read (param i32 i32 i32 i32) (result i32))") "fd_read must take 4 i32 params and return i32")
    (assert (string-contains? imports "(func $proc_exit (param i32))") "proc_exit must take 1 i32 param with no result clause")
    (assert (string-contains? imports "(func $clock_time_get (param i32 i64 i32) (result i32))") "clock_time_get must take i32 i64 i32 and return i32")
    true))

(df testWasiFdWrite [] -> Bool
  :d "Verifies WASI fd_write invocation lowering."
  (let [(stdoutCall (w/emitWasiFdWrite 1 1024 1 2048))
        (stderrCall (w/emitWasiFdWrite 2 4096 2 5120))]
    (assert (string-contains? stdoutCall "call $fd_write") "stdout call must invoke call $fd_write")
    (assert (string-contains? stdoutCall "(i32.const 1)") "stdout call must contain fd 1")
    (assert (string-contains? stdoutCall "(i32.const 1024)") "stdout call must contain iovs offset 1024")
    (assert (string-contains? stdoutCall "(i32.const 1)") "stdout call must contain iovs length 1")
    (assert (string-contains? stdoutCall "(i32.const 2048)") "stdout call must contain nwritten offset 2048")
    (assert (string-contains? stderrCall "(i32.const 2)") "stderr call must contain fd 2")
    (assert (and (string-contains? stderrCall "(i32.const 4096)") (string-contains? stderrCall "(i32.const 5120)")) "stderr call must contain memory offsets 4096 and 5120")
    true))

(df testWasiProcExit [] -> Bool
  :d "Verifies WASI proc_exit invocation lowering."
  (let [(exit0 (w/emitWasiProcExit 0))
        (exit1 (w/emitWasiProcExit 1))
        (exit137 (w/emitWasiProcExit 137))]
    (assert (string-contains? exit0 "call $proc_exit") "proc-exit lowering must invoke call $proc_exit")
    (assert (string-contains? exit0 "(i32.const 0)") "exit code 0 must format with i32.const 0")
    (assert (string-contains? exit1 "(i32.const 1)") "exit code 1 must format with i32.const 1")
    (assert (string-contains? exit137 "(i32.const 137)") "custom exit code 137 must format with i32.const 137")
    (assert (not (string-contains? exit0 "result")) "proc-exit must not emit a result type clause")
    true))

(df testWasiClockTimeGet [] -> Bool
  :d "Verifies WASI clock_time_get invocation lowering."
  (let [(realtimeCall (w/emitWasiClockTimeGet 0 1000 8192))
        (monotonicCall (w/emitWasiClockTimeGet 1 0 8200))]
    (assert (string-contains? realtimeCall "call $clock_time_get") "clock_time_get lowering must invoke call $clock_time_get")
    (assert (string-contains? realtimeCall "(i32.const 0)") "realtime clock-id must be (i32.const 0)")
    (assert (string-contains? realtimeCall "(i64.const 1000)") "precision argument must use i64.const 1000")
    (assert (string-contains? realtimeCall "(i32.const 8192)") "time-offset argument must be (i32.const 8192)")
    (assert (string-contains? monotonicCall "(i32.const 1)") "monotonic clock-id must be (i32.const 1)")
    (assert (string-contains? monotonicCall "(i64.const 0)") "monotonic precision argument must be (i64.const 0)")
    true))

(df testWasmMemoryModel [] -> Bool
  :d "Verifies WebAssembly linear memory export declaration emission."
  (let [(mBounded (w/emitWasmMemoryModel 1 256))
        (mUnbounded (w/emitWasmMemoryModel 2 0))]
    (assert (string-contains? mBounded "(memory (export \"memory\") 1 256)") "Bounded memory must declare initial 1 and max 256 pages")
    (assert (string-contains? mUnbounded "(memory (export \"memory\") 2)") "Unbounded memory must declare initial 2 pages")
    true))

(df testWasmExportDispatch [] -> Bool
  :d "Verifies Batch RPC linear memory dispatch export definitions."
  (let [(dispatchWat (w/emitWasmExportDispatch "asl-core"))]
    (assert (string-contains? dispatchWat "(export \"asl_alloc\")") "Dispatch WAT must export asl_alloc")
    (assert (string-contains? dispatchWat "(export \"asl_free\")") "Dispatch WAT must export asl_free")
    (assert (string-contains? dispatchWat "(export \"asl_rpc_dispatch\")") "Dispatch WAT must export asl_rpc_dispatch")
    (assert (string-contains? dispatchWat "(param $in_ptr i32)") "asl_rpc_dispatch must receive in_ptr i32")
    true))

(df testAslCoreWasmModule [] -> Bool
  :d "Verifies complete standalone asl-core.wasm module envelope."
  (let [(envelope (w/emitAslCoreWasmModule "  (func $dummy)"))]
    (assert (string-contains? envelope "(module") "Module envelope must open with (module")
    (assert (string-contains? envelope "wasi_snapshot_preview1") "Module must contain WASI preview 1 imports")
    (assert (string-contains? envelope "(memory (export \"memory\") 1 256)") "Module must declare 1..256 page memory")
    (assert (string-contains? envelope "(export \"asl_rpc_dispatch\")") "Module must export asl_rpc_dispatch")
    (assert (string-contains? envelope "(func $dummy)") "Module must embed payload functions")
    true))

(df runTests [] -> Bool
  :d "Runs all WebAssembly codegen unit tests."
  (let [(t1 (testWatType))
        (t2 (testWatOp))
        (t3 (testWatConst))
        (t4 (testWatFn))
        (t5 (testWatMod))
        (t6 (testWatEmit))
        (t7 (testEmitWatExpr))
        (t8 (testEmitWatModule))
        (t9 (testWasiImports))
        (t10 (testWasiFdWrite))
        (t11 (testWasiProcExit))
        (t12 (testWasiClockTimeGet))
        (t13 (testWasmMemoryModel))
        (t14 (testWasmExportDispatch))
        (t15 (testAslCoreWasmModule))] (and t1 (and t2 (and t3 (and t4 (and t5 (and t6 (and t7 (and t8 (and t9 (and t10 (and t11 (and t12 (and t13 (and t14 t15))))))))))))))))

