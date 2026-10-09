(module asl-target-wat/emitWat :x [watType watOp watConst watGet watSet watCall watIf watFn watMod watEmit emitWatExpr emitWatModule emitWatSwitch emitWatBinop emitWasiImports emitWasiFdWrite emitWasiProcExit emitWasiClockTimeGet emitWasmMemoryModel emitWasmExportDispatch emitAslCoreWasmModule makeWatBranchTableLabels] :i [])

fn watType ty: Str -> Str
  (cond ((= ty "I64") "i64") ((= ty "I32") "i32") ((= ty "Int") "i64") ((= ty "F64") "f64") ((= ty "Float") "f64") ((= ty "Bool") "i32") ((= ty "Str") "i32") ((= ty "Unit") "void") (else "i64"))

fn watOp op: Str ty: Str -> Str
  (let [(prefix (watType ty))] (cond ((= op "+") (str prefix ".add")) ((= op "-") (str prefix ".sub")) ((= op "*") (str prefix ".mul")) ((= op "/") (if (= prefix "f64") "f64.div" (str prefix ".div_s"))) ((= op "mod") (str prefix ".rem_s")) ((= op "=") (str prefix ".eq")) ((= op "==") (str prefix ".eq")) ((= op "!=") (str prefix ".ne")) ((= op "<") (if (= prefix "f64") "f64.lt" (str prefix ".lt_s"))) ((= op "<=") (if (= prefix "f64") "f64.le" (str prefix ".le_s"))) ((= op ">") (if (= prefix "f64") "f64.gt" (str prefix ".gt_s"))) ((= op ">=") (if (= prefix "f64") "f64.ge" (str prefix ".ge_s"))) ((= op "and") "i32.and") ((= op "or") "i32.or") (else (str prefix ".add"))))

fn watConst val: Str ty: Str -> Str
  (let [(wTy (watType ty))] (str "(" wTy ".const " val ")"))

fn watGet varName: Str -> Str
  (str "(local.get $" varName ")")

fn watSet varName: Str valExpr: Str -> Str
  (str "(local.set $" varName " " valExpr ")")

fn watCall fnName: Str argsStr: Str -> Str
  (if (= argsStr "") (str "(call $" fnName ")") (str "(call $" fnName " " argsStr ")"))

fn watIf condExpr: Str thenExpr: Str elseExpr: Str retTy: Str -> Str
  (let [(wRet (watType retTy))] (if (= wRet "void") (str "(if " condExpr " (then " thenExpr ") (else " elseExpr "))") (str "(if (result " wRet ") " condExpr " (then " thenExpr ") (else " elseExpr "))")))

fn watFn name: Str paramsWat: Str retTy: Str body: Str exportFn: Bool -> Str
  (let [(wRet (watType retTy)) (resClause (if (= wRet "void") "" (str " (result " wRet ")"))) (exportAttr (if exportFn (str " (export \"" name "\")") "")) (pClause (if (= paramsWat "") "" (str " " paramsWat)))] (str "(func $" name exportAttr pClause resClause "\n  " body ")"))

fn watMod funcsWat: Str useMem: Bool -> Str
  (let [(memDecl (if useMem "  (memory (export \"memory\") 1)\n" ""))] (str "(module\n" memDecl funcsWat "\n)"))

fn watOperand operand: Str ty: Str -> Str
  (cond ((stringStartsWith? operand "(") operand) ((or (stringStartsWith? operand "-") (and (>= (optionOr (stringSlice operand 0 1) "") "0") (<= (optionOr (stringSlice operand 0 1) "") "9"))) (watConst operand ty)) (else (watGet operand)))

fn emitWatExpr op: Str lhs: Str rhs: Str ty: Str -> Str
  (let [(instr (watOp op ty)) (left (watOperand lhs ty)) (right (watOperand rhs ty))] (str "(" instr " " left " " right ")"))

fn emitWatModule funcsWat: Str useMem: Bool -> Str
  (watMod funcsWat useMem)

fn watEmit fnName: Str argA: Str argB: Str op: Str retTy: Str -> Str
  (let [(wTy (watType retTy)) (params (str "(param $" argA " " wTy ") (param $" argB " " wTy ")")) (instr (watOp op retTy)) (body (str instr " " (watGet argA) " " (watGet argB))) (fnDef (watFn fnName params retTy body true))] (emitWatModule (str "  " fnDef) false))

fn emitWasiImports -> Str
  (str "  (import \"wasi_snapshot_preview1\" \"fd_write\" (func $fd_write (param i32 i32 i32 i32) (result i32)))\n" "  (import \"wasi_snapshot_preview1\" \"fd_read\" (func $fd_read (param i32 i32 i32 i32) (result i32)))\n" "  (import \"wasi_snapshot_preview1\" \"proc_exit\" (func $proc_exit (param i32)))\n" "  (import \"wasi_snapshot_preview1\" \"clock_time_get\" (func $clock_time_get (param i32 i64 i32) (result i32)))")

fn emitWasiFdWrite fd: I64 iovsOffset: I64 iovsLen: I64 nwrittenOffset: I64 -> Str
  (str "(call $fd_write (i32.const " fd ") (i32.const " iovsOffset ") (i32.const " iovsLen ") (i32.const " nwrittenOffset "))")

fn emitWasiProcExit exitCode: I64 -> Str
  (str "(call $proc_exit (i32.const " exitCode "))\n(unreachable)")

fn emitWasiClockTimeGet clockId: I64 precision: I64 timeOffset: I64 -> Str
  (str "(call $clock_time_get (i32.const " clockId ") (i64.const " precision ") (i32.const " timeOffset "))")

fn emitWasmMemoryModel initialPages: I64 maxPages: I64 -> Str
  (if (> maxPages 0) (str "  (memory (export \"memory\") " initialPages " " maxPages ")\n") (str "  (memory (export \"memory\") " initialPages ")\n"))

fn emitWasmExportDispatch moduleName: Str -> Str
  (str "  (data (i32.const 16) \"(:batch-res :status \\\"completed\\\" :bridge \\\"asl-core\\\" :zero-socket true :results [])\\n\\00\")\n" "  (func $aslAlloc (export \"aslAlloc\") (param $size i32) (result i32)\n" "    (local $base i32) (local $new_offset i32)\n" "    (local.set $base (i32.load (i32.const 0)))\n" "    (if (i32.eqz (local.get $base)) (then (local.set $base (i32.const 1024))))\n" "    (local.set $new_offset (i32.add (local.get $base) (local.get $size)))\n" "    (if (i32.gt_u (local.get $new_offset) (i32.mul (memory.size) (i32.const 65536))) (then (drop (memory.grow (i32.const 2)))))\n" "    (i32.store (i32.const 0) (local.get $new_offset))\n" "    (local.get $base))\n" "  (func $aslFree (export \"aslFree\") (param $ptr i32) (param $size i32)\n" "    (if (i32.eq (i32.add (local.get $ptr) (local.get $size)) (i32.load (i32.const 0)))\n" "      (then (i32.store (i32.const 0) (local.get $ptr)))))\n" "  (func $aslRpcDispatch (export \"aslRpcDispatch\") (param $in_ptr i32) (param $in_len i32) (param $out_ptr i32) (result i32)\n" "    (local $i i32)\n" "    (if (i32.gt_u (local.get $out_ptr) (i32.const 0)) (then\n" "      (local.set $i (i32.const 0))\n" "      (loop $copy\n" "        (i32.store8 (i32.add (local.get $out_ptr) (local.get $i)) (i32.load8_u (i32.add (i32.const 16) (local.get $i))))\n" "        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" "        (br_if $copy (i32.lt_u (local.get $i) (i32.const 83))))))\n" "    (i32.const 0))\n")

fn emitAslCoreWasmModule funcsWat: Str -> Str
  (str "(module\n" (emitWasiImports) "\n" (emitWasmMemoryModel 1 256) (emitWasmExportDispatch "asl-core") funcsWat "\n" ")")

fn emitWatBinop op: Str left: Str right: Str -> Str
  (cond ((= op "/") (str "(call $asl_floor_div (local.get $" left ") (local.get $" right "))")) ((or (= op "mod") (= op "%")) (str "(call $asl_floor_mod (local.get $" left ") (local.get $" right "))")) ((= op "+") (str "(i64.add (local.get $" left ") (local.get $" right "))")) ((= op "-") (str "(i64.sub (local.get $" left ") (local.get $" right "))")) ((= op "*") (str "(i64.mul (local.get $" left ") (local.get $" right "))")) ((or (= op "shl") (= op "<<")) (str "(i64.shl (local.get $" left ") (i64.and (local.get $" right ") (i64.const 63)))")) ((or (= op "shr") (= op ">>")) (str "(i64.shr_s (local.get $" left ") (i64.and (local.get $" right ") (i64.const 63)))")) (else (str "(i64.add (local.get $" left ") (local.get $" right "))")))

fn makeWatLabelsStep idx: Int64 maxIdx: Int64 acc: (List Str) -> (List Str)
  (if (> idx maxIdx)
    (listReverse acc)
    (makeWatLabelsStep (+ idx 1) maxIdx (cons (stringFromInt64 idx) acc)))

fn makeWatBranchTableLabels k: Int64 -> Str
  (let [(labels (makeWatLabelsStep 0 k (list)))]
    (stringJoin labels " "))

fn emitWatSwitch scrutinee: Str cases: (List Str) defaultArm: Str -> Str
  (let [(k (listLength cases))
        (labelVec (makeWatBranchTableLabels k))
        (brTable (str "        (br_table " labelVec " (local.get $" scrutinee "))\n"))
        (caseBlocks (fold (fn [(acc Str) (c Str)] -> Str (str "      (block\n" acc "      )\n      " c "\n      (br $exit)\n")) brTable cases))]
    (str "  (block $exit\n"
         "    (block $default\n"
         caseBlocks
         "    )\n"
         "    " defaultArm "\n"
         "  )"))
