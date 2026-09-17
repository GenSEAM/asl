(module asl-target-wat/emitWat
  :d "Standalone WebAssembly Text (WAT) emitter backend for AgentScript."
  :x [watType
      watOp
      watConst
      watGet
      watSet
      watCall
      watIf
      watFn
      watMod
      watEmit
      emitWatExpr
      emitWatModule
      emitWasiImports
      emitWasiFdWrite
      emitWasiProcExit
      emitWasiClockTimeGet
      emitWasmMemoryModel
      emitWasmExportDispatch
      emitAslCoreWasmModule]
  :i [])

(df watType [(ty Str)] -> Str
  :d "Maps AgentScript type to WebAssembly value type (i32, i64, f64)."
  (cond
    ((= ty "I64") "i64")
    ((= ty "I32") "i32")
    ((= ty "Int") "i64")
    ((= ty "F64") "f64")
    ((= ty "Float") "f64")
    ((= ty "Bool") "i32")
    ((= ty "Str") "i32")
    ((= ty "Unit") "void")
    (:else "i64")))

(df watOp [(op Str) (ty Str)] -> Str
  :d "Maps binary or comparison operator to WebAssembly instruction."
  (let [(prefix (watType ty))]
    (cond
      ((= op "+") (str prefix ".add"))
      ((= op "-") (str prefix ".sub"))
      ((= op "*") (str prefix ".mul"))
      ((= op "/") (if (= prefix "f64") "f64.div" (str prefix ".div_s")))
      ((= op "mod") (str prefix ".rem_s"))
      ((= op "=") (str prefix ".eq"))
      ((= op "==") (str prefix ".eq"))
      ((= op "!=") (str prefix ".ne"))
      ((= op "<") (if (= prefix "f64") "f64.lt" (str prefix ".lt_s")))
      ((= op "<=") (if (= prefix "f64") "f64.le" (str prefix ".le_s")))
      ((= op ">") (if (= prefix "f64") "f64.gt" (str prefix ".gt_s")))
      ((= op ">=") (if (= prefix "f64") "f64.ge" (str prefix ".ge_s")))
      ((= op "and") "i32.and")
      ((= op "or") "i32.or")
      (:else (str prefix ".add")))))

(df watConst [(val Str) (ty Str)] -> Str
  :d "Emits a WebAssembly constant instruction."
  (let [(wTy (watType ty))]
    (str "(" wTy ".const " val ")")))

(df watGet [(varName Str)] -> Str
  :d "Emits local.get instruction for variable."
  (str "(local.get $" varName ")"))

(df watSet [(varName Str) (valExpr Str)] -> Str
  :d "Emits local.set instruction for variable."
  (str "(local.set $" varName " " valExpr ")"))

(df watCall [(fnName Str) (argsStr Str)] -> Str
  :d "Emits function call instruction."
  (if (= argsStr "")
      (str "(call $" fnName ")")
      (str "(call $" fnName " " argsStr ")")))

(df watIf [(condExpr Str) (thenExpr Str) (elseExpr Str) (retTy Str)] -> Str
  :d "Emits structured if-then-else expression in WAT."
  (let [(wRet (watType retTy))]
    (if (= wRet "void")
        (str "(if " condExpr " (then " thenExpr ") (else " elseExpr "))")
        (str "(if (result " wRet ") " condExpr " (then " thenExpr ") (else " elseExpr "))"))))

(df watFn [(name Str) (paramsWat Str) (retTy Str) (body Str) (exportFn Bool)] -> Str
  :d "Emits a complete WebAssembly function declaration with optional export."
  (let [(wRet (watType retTy))
        (resClause (if (= wRet "void") "" (str " (result " wRet ")")))
        (exportAttr (if exportFn (str " (export \"" name "\")") ""))
        (pClause (if (= paramsWat "") "" (str " " paramsWat)))]
    (str "(func $" name exportAttr pClause resClause "\n  " body ")")))

(df watMod [(funcsWat Str) (useMem Bool)] -> Str
  :d "Wraps WebAssembly function definitions inside a module envelope."
  (let [(memDecl (if useMem "  (memory (export \"memory\") 1)\n" ""))]
    (str "(module\n" memDecl funcsWat "\n)")))

(df watOperand [(operand Str) (ty Str)] -> Str
  :d "Formats an expression operand as subexpression, constant, or local variable."
  (cond
    ((string-starts-with? operand "(") operand)
    ((or (string-starts-with? operand "-")
         (and (>= (option-or (string-slice operand 0 1) "") "0")
              (<= (option-or (string-slice operand 0 1) "") "9")))
     (watConst operand ty))
    (:else (watGet operand))))

(df emitWatExpr [(op Str) (lhs Str) (rhs Str) (ty Str)] -> Str
  :d "Lowers a binary arithmetic, relational, or logical expression into WebAssembly Text format."
  (let [(instr (watOp op ty))
        (left (watOperand lhs ty))
        (right (watOperand rhs ty))]
    (str "(" instr " " left " " right ")")))

(df emitWatModule [(funcsWat Str) (useMem Bool)] -> Str
  :d "Lowers WebAssembly function definitions into a complete module envelope."
  (watMod funcsWat useMem))

(df watEmit [(fnName Str) (argA Str) (argB Str) (op Str) (retTy Str)] -> Str
  :d "Helper to emit a two-argument binary arithmetic function in WAT."
  (let [(wTy (watType retTy))
        (params (str "(param $" argA " " wTy ") (param $" argB " " wTy ")"))
        (instr (watOp op retTy))
        (body (str instr " " (watGet argA) " " (watGet argB)))
        (fnDef (watFn fnName params retTy body true))]
    (emitWatModule (str "  " fnDef) false)))

(df emitWasiImports [] -> Str
  :d "Emits WASI snapshot preview 1 host function import declarations for wasm32-wasip1 runtime linking."
  (str "  (import \"wasi_snapshot_preview1\" \"fd_write\" (func $fd_write (param i32 i32 i32 i32) (result i32)))\n"
       "  (import \"wasi_snapshot_preview1\" \"fd_read\" (func $fd_read (param i32 i32 i32 i32) (result i32)))\n"
       "  (import \"wasi_snapshot_preview1\" \"proc_exit\" (func $proc_exit (param i32)))\n"
       "  (import \"wasi_snapshot_preview1\" \"clock_time_get\" (func $clock_time_get (param i32 i64 i32) (result i32)))"))

(df emitWasiFdWrite [(fd I64) (iovsOffset I64) (iovsLen I64) (nwrittenOffset I64)] -> Str
  :d "Emits WebAssembly Text lowering for wasi_snapshot_preview1 fd_write invocation with iovec buffer arguments."
  (str "(call $fd_write (i32.const " fd ") (i32.const " iovsOffset ") (i32.const " iovsLen ") (i32.const " nwrittenOffset "))"))

(df emitWasiProcExit [(exitCode I64)] -> Str
  :d "Emits WebAssembly Text lowering for wasi_snapshot_preview1 proc_exit invocation terminating process execution."
  (str "(call $proc_exit (i32.const " exitCode "))"))

(df emitWasiClockTimeGet [(clockId I64) (precision I64) (timeOffset I64)] -> Str
  :d "Emits WebAssembly Text lowering for wasi_snapshot_preview1 clock_time_get high-resolution timestamp queries."
  (str "(call $clock_time_get (i32.const " clockId ") (i64.const " precision ") (i32.const " timeOffset "))"))

(df emitWasmMemoryModel [(initialPages I64) (maxPages I64)] -> Str
  :d "Emits WebAssembly linear memory export declaration with initial and maximum page bounds."
  (if (> maxPages 0)
      (str "  (memory (export \"memory\") " initialPages " " maxPages ")\n")
      (str "  (memory (export \"memory\") " initialPages ")\n")))

(df emitWasmExportDispatch [(moduleName Str)] -> Str
  :d "Emits sovereign in-browser Batch RPC dispatcher export signatures for WebAssembly linear memory."
  (str "  (data (i32.const 16) \"(:batch-res :status \\\"completed\\\" :bridge \\\"asl-core\\\" :zero-socket true :results [])\\n\\00\")\n"
       "  (func $aslAlloc (export \"aslAlloc\") (param $size i32) (result i32)\n"
       "    (local $base i32) (local $new_offset i32)\n"
       "    (local.set $base (i32.load (i32.const 0)))\n"
       "    (if (i32.eqz (local.get $base)) (then (local.set $base (i32.const 1024))))\n"
       "    (local.set $new_offset (i32.add (local.get $base) (local.get $size)))\n"
       "    (if (i32.gt_u (local.get $new_offset) (i32.mul (memory.size) (i32.const 65536))) (then (drop (memory.grow (i32.const 2)))))\n"
       "    (i32.store (i32.const 0) (local.get $new_offset))\n"
       "    (local.get $base))\n"
       "  (func $aslFree (export \"aslFree\") (param $ptr i32) (param $size i32)\n"
       "    (if (i32.eq (i32.add (local.get $ptr) (local.get $size)) (i32.load (i32.const 0)))\n"
       "      (then (i32.store (i32.const 0) (local.get $ptr)))))\n"
       "  (func $aslRpcDispatch (export \"aslRpcDispatch\") (param $in_ptr i32) (param $in_len i32) (param $out_ptr i32) (result i32)\n"
       "    (local $i i32)\n"
       "    (if (i32.gt_u (local.get $out_ptr) (i32.const 0)) (then\n"
       "      (local.set $i (i32.const 0))\n"
       "      (loop $copy\n"
       "        (i32.store8 (i32.add (local.get $out_ptr) (local.get $i)) (i32.load8_u (i32.add (i32.const 16) (local.get $i))))\n"
       "        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n"
       "        (br_if $copy (i32.lt_u (local.get $i) (i32.const 83))))))\n"
       "    (i32.const 0))\n"))

(df emitAslCoreWasmModule [(funcsWat Str)] -> Str
  :d "Emits complete standalone asl-core.wasm module envelope with WASI preview 1 imports and Batch RPC exports."
  (str "(module\n"
       (emitWasiImports) "\n"
       (emitWasmMemoryModel 1 256)
       (emitWasmExportDispatch "asl-core")
       funcsWat "\n"
       ")"))
