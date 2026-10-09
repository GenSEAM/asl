(module asl-codegen/tests/emitWatTest :x [runTests] :i [(asl-target-wat/emitWat :a w)])

fn testWatType -> Bool
  (let [(t1 (w/watType "I64")) (t2 (w/watType "I32")) (t3 (w/watType "Bool")) (t4 (w/watType "F64")) (t5 (w/watType "Unit"))] (assert (= t1 "i64") "I64 must map to i64") (assert (= t2 "i32") "I32 must map to i32") (assert (= t3 "i32") "Bool must map to i32") (assert (= t4 "f64") "F64 must map to f64") (assert (= t5 "void") "Unit must map to void") true)

fn testWatOp -> Bool
  (let [(opAdd (w/watOp "+" "I64")) (opSub (w/watOp "-" "I64")) (opMul (w/watOp "*" "I64")) (opDiv (w/watOp "/" "I64")) (opEq (w/watOp "=" "I64")) (opLt (w/watOp "<" "I64"))] (assert (= opAdd "i64.add") "Addition op must be i64.add") (assert (= opSub "i64.sub") "Subtraction op must be i64.sub") (assert (= opMul "i64.mul") "Multiplication op must be i64.mul") (assert (= opDiv "i64.div_s") "Division op must be i64.div_s") (assert (= opEq "i64.eq") "Equality op must be i64.eq") (assert (= opLt "i64.lt_s") "Less-than op must be i64.lt_s") true)

fn testWatConst -> Bool
  (let [(c1 (w/watConst "42" "I64")) (c2 (w/watConst "1" "Bool"))] (assert (= c1 "(i64.const 42)") "I64 constant must format with i64.const") (assert (= c2 "(i32.const 1)") "Bool constant must format with i32.const") true)

fn testWatFn -> Bool
  (let [(fnStr (w/watFn "add" "(param $a i64) (param $b i64)" "I64" "i64.add (local.get $a) (local.get $b)" true))] (assert (stringContains? fnStr "(func $add (export \"add\")") "Function declaration must contain export attribute") (assert (stringContains? fnStr "(param $a i64)") "Function declaration must contain parameter clause") (assert (stringContains? fnStr "(result i64)") "Function declaration must contain result clause") true)

fn testWatMod -> Bool
  (let [(modStr (w/watMod "  (func $dummy)" true))] (assert (stringContains? modStr "(module") "Module envelope must start with (module") (assert (stringContains? modStr "(memory (export \"memory\") 1)") "Module envelope must include exported memory") (assert (stringContains? modStr "(func $dummy)") "Module envelope must contain nested functions") true)

fn testWatEmit -> Bool
  (let [(modStr (w/watEmit "calc" "x" "y" "+" "I64"))] (assert (stringContains? modStr "(module") "Emitted module must contain module header") (assert (stringContains? modStr "(func $calc (export \"calc\")") "Emitted module must contain calc function export") (assert (stringContains? modStr "(param $x i64)") "Emitted module must contain param $x i64") (assert (stringContains? modStr "i64.add (local.get $x) (local.get $y)") "Emitted module body must perform i64.add") true)

fn testEmitWatExpr -> Bool
  (let [(e1 (w/emitWatExpr "+" "a" "b" "I32")) (e2 (w/emitWatExpr "-" "x" "10" "I64")) (e3 (w/emitWatExpr "*" "count" "(local.get $step)" "I32"))] (assert (stringContains? e1 "i32.add (local.get $a) (local.get $b)") "e1 must emit i32.add with local.get variables") (assert (stringContains? e2 "i64.sub (local.get $x) (i64.const 10)") "e2 must emit i64.sub with literal constant") (assert (stringContains? e3 "i32.mul (local.get $count) (local.get $step)") "e3 must emit i32.mul preserving subexpressions") true)

fn testEmitWatModule -> Bool
  (let [(exprCode (w/emitWatExpr "+" "a" "b" "I32")) (fnCode (w/watFn "add" "(param $a i32) (param $b i32)" "I32" exprCode true)) (modStr (w/emitWatModule (str "  " fnCode) true))] (assert (stringContains? modStr "(module") "Module envelope must open with (module") (assert (stringContains? modStr "(memory (export \"memory\") 1)") "Module must declare exported memory") (assert (stringContains? modStr "(func $add (export \"add\")") "Module must declare exported add function") (assert (stringContains? modStr "i32.add") "Module must contain i32.add instruction") true)

fn testWasiImports -> Bool
  (let [(imports (w/emitWasiImports))] (assert (stringContains? imports "(import \"wasi_snapshot_preview1\" \"fd_write\"") "WASI imports must declare fd_write") (assert (stringContains? imports "(import \"wasi_snapshot_preview1\" \"fd_read\"") "WASI imports must declare fd_read") (assert (stringContains? imports "(import \"wasi_snapshot_preview1\" \"proc_exit\"") "WASI imports must declare proc_exit") (assert (stringContains? imports "(import \"wasi_snapshot_preview1\" \"clock_time_get\"") "WASI imports must declare clock_time_get") (assert (stringContains? imports "(func $fd_write (param i32 i32 i32 i32) (result i32))") "fd_write must take 4 i32 params and return i32") (assert (stringContains? imports "(func $fd_read (param i32 i32 i32 i32) (result i32))") "fd_read must take 4 i32 params and return i32") (assert (stringContains? imports "(func $proc_exit (param i32))") "proc_exit must take 1 i32 param with no result clause") (assert (stringContains? imports "(func $clock_time_get (param i32 i64 i32) (result i32))") "clock_time_get must take i32 i64 i32 and return i32") true)

fn testWasiFdWrite -> Bool
  (let [(stdoutCall (w/emitWasiFdWrite 1 1024 1 2048)) (stderrCall (w/emitWasiFdWrite 2 4096 2 5120))] (assert (stringContains? stdoutCall "call $fd_write") "stdout call must invoke call $fd_write") (assert (stringContains? stdoutCall "(i32.const 1)") "stdout call must contain fd 1") (assert (stringContains? stdoutCall "(i32.const 1024)") "stdout call must contain iovs offset 1024") (assert (stringContains? stdoutCall "(i32.const 1)") "stdout call must contain iovs length 1") (assert (stringContains? stdoutCall "(i32.const 2048)") "stdout call must contain nwritten offset 2048") (assert (stringContains? stderrCall "(i32.const 2)") "stderr call must contain fd 2") (assert (and (stringContains? stderrCall "(i32.const 4096)") (stringContains? stderrCall "(i32.const 5120)")) "stderr call must contain memory offsets 4096 and 5120") true)

fn testWasiProcExit -> Bool
  (let [(exit0 (w/emitWasiProcExit 0)) (exit1 (w/emitWasiProcExit 1)) (exit137 (w/emitWasiProcExit 137))] (assert (stringContains? exit0 "call $proc_exit") "proc-exit lowering must invoke call $proc_exit") (assert (stringContains? exit0 "(i32.const 0)") "exit code 0 must format with i32.const 0") (assert (stringContains? exit1 "(i32.const 1)") "exit code 1 must format with i32.const 1") (assert (stringContains? exit137 "(i32.const 137)") "custom exit code 137 must format with i32.const 137") (assert (not (stringContains? exit0 "result")) "proc-exit must not emit a result type clause") true)

fn testWasiClockTimeGet -> Bool
  (let [(realtimeCall (w/emitWasiClockTimeGet 0 1000 8192)) (monotonicCall (w/emitWasiClockTimeGet 1 0 8200))] (assert (stringContains? realtimeCall "call $clock_time_get") "clock_time_get lowering must invoke call $clock_time_get") (assert (stringContains? realtimeCall "(i32.const 0)") "realtime clock-id must be (i32.const 0)") (assert (stringContains? realtimeCall "(i64.const 1000)") "precision argument must use i64.const 1000") (assert (stringContains? realtimeCall "(i32.const 8192)") "time-offset argument must be (i32.const 8192)") (assert (stringContains? monotonicCall "(i32.const 1)") "monotonic clock-id must be (i32.const 1)") (assert (stringContains? monotonicCall "(i64.const 0)") "monotonic precision argument must be (i64.const 0)") true)

fn testWasmMemoryModel -> Bool
  (let [(mBounded (w/emitWasmMemoryModel 1 256)) (mUnbounded (w/emitWasmMemoryModel 2 0))] (assert (stringContains? mBounded "(memory (export \"memory\") 1 256)") "Bounded memory must declare initial 1 and max 256 pages") (assert (stringContains? mUnbounded "(memory (export \"memory\") 2)") "Unbounded memory must declare initial 2 pages") true)

fn testWasmExportDispatch -> Bool
  (let [(dispatchWat (w/emitWasmExportDispatch "asl-core"))] (assert (stringContains? dispatchWat "(export \"aslAlloc\")") "Dispatch WAT must export aslAlloc") (assert (stringContains? dispatchWat "(export \"aslFree\")") "Dispatch WAT must export aslFree") (assert (stringContains? dispatchWat "(export \"aslRpcDispatch\")") "Dispatch WAT must export aslRpcDispatch") (assert (stringContains? dispatchWat "(param $in_ptr i32)") "aslRpcDispatch must receive in_ptr i32") true)

fn testAslCoreWasmModule -> Bool
  (let [(envelope (w/emitAslCoreWasmModule "  (func $dummy)"))] (assert (stringContains? envelope "(module") "Module envelope must open with (module") (assert (stringContains? envelope "wasi_snapshot_preview1") "Module must contain WASI preview 1 imports") (assert (stringContains? envelope "(memory (export \"memory\") 1 256)") "Module must declare 1..256 page memory") (assert (stringContains? envelope "(export \"aslRpcDispatch\")") "Module must export aslRpcDispatch") (assert (stringContains? envelope "(func $dummy)") "Module must embed payload functions") true)

fn runTests -> Bool
  (let [(t1 (testWatType)) (t2 (testWatOp)) (t3 (testWatConst)) (t4 (testWatFn)) (t5 (testWatMod)) (t6 (testWatEmit)) (t7 (testEmitWatExpr)) (t8 (testEmitWatModule)) (t9 (testWasiImports)) (t10 (testWasiFdWrite)) (t11 (testWasiProcExit)) (t12 (testWasiClockTimeGet)) (t13 (testWasmMemoryModel)) (t14 (testWasmExportDispatch)) (t15 (testAslCoreWasmModule))] (and t1 (and t2 (and t3 (and t4 (and t5 (and t6 (and t7 (and t8 (and t9 (and t10 (and t11 (and t12 (and t13 (and t14 t15)))))))))))))))
