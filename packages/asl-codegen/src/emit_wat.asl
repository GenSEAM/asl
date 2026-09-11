(module asl-codegen/emit-wat
  :d "WebAssembly Text (WAT) and linear memory bytecode generator for AgentScript."
  :x [wat-type
      wat-op
      wat-const
      wat-get
      wat-set
      wat-call
      wat-if
      wat-fn
      wat-mod
      wat-emit
      emit-wat-expr
      emit-wat-module
      emit-wasi-imports
      emit-wasi-fd-write
      emit-wasi-proc-exit
      emit-wasi-clock-time-get
      emit-wasm-memory-model
      emit-wasm-export-dispatch
      emit-asl-core-wasm-module]
  :i [])

(df wat-type [(ty Str)] -> Str
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

(df wat-op [(op Str) (ty Str)] -> Str
  :d "Maps binary or comparison operator to WebAssembly instruction."
  (let [(prefix (wat-type ty))]
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

(df wat-const [(val Str) (ty Str)] -> Str
  :d "Emits a WebAssembly constant instruction."
  (let [(w-ty (wat-type ty))]
    (str "(" w-ty ".const " val ")")))

(df wat-get [(var-name Str)] -> Str
  :d "Emits local.get instruction for variable."
  (str "(local.get $" var-name ")"))

(df wat-set [(var-name Str) (val-expr Str)] -> Str
  :d "Emits local.set instruction for variable."
  (str "(local.set $" var-name " " val-expr ")"))

(df wat-call [(fn-name Str) (args-str Str)] -> Str
  :d "Emits function call instruction."
  (if (= args-str "")
      (str "(call $" fn-name ")")
      (str "(call $" fn-name " " args-str ")")))

(df wat-if [(cond-expr Str) (then-expr Str) (else-expr Str) (ret-ty Str)] -> Str
  :d "Emits structured if-then-else expression in WAT."
  (let [(w-ret (wat-type ret-ty))]
    (if (= w-ret "void")
        (str "(if " cond-expr " (then " then-expr ") (else " else-expr "))")
        (str "(if (result " w-ret ") " cond-expr " (then " then-expr ") (else " else-expr "))"))))

(df wat-fn [(name Str) (params-wat Str) (ret-ty Str) (body Str) (export-fn Bool)] -> Str
  :d "Emits a complete WebAssembly function declaration with optional export."
  (let [(w-ret (wat-type ret-ty))
        (res-clause (if (= w-ret "void") "" (str " (result " w-ret ")")))
        (export-attr (if export-fn (str " (export \"" name "\")") ""))
        (p-clause (if (= params-wat "") "" (str " " params-wat)))]
    (str "(func $" name export-attr p-clause res-clause "\n  " body ")")))

(df wat-mod [(funcs-wat Str) (use-mem Bool)] -> Str
  :d "Wraps WebAssembly function definitions inside a module envelope."
  (let [(mem-decl (if use-mem "  (memory (export \"memory\") 1)\n" ""))]
    (str "(module\n" mem-decl funcs-wat "\n)")))

(df wat-operand [(operand Str) (ty Str)] -> Str
  :d "Formats an expression operand as subexpression, constant, or local variable."
  (cond
    ((string-starts-with? operand "(") operand)
    ((or (string-starts-with? operand "-")
         (and (>= (option-or (string-slice operand 0 1) "") "0")
              (<= (option-or (string-slice operand 0 1) "") "9")))
     (wat-const operand ty))
    (:else (wat-get operand))))

(df emit-wat-expr [(op Str) (lhs Str) (rhs Str) (ty Str)] -> Str
  :d "Lowers a binary arithmetic, relational, or logical expression into WebAssembly Text format."
  (let [(instr (wat-op op ty))
        (left (wat-operand lhs ty))
        (right (wat-operand rhs ty))]
    (str "(" instr " " left " " right ")")))

(df emit-wat-module [(funcs-wat Str) (use-mem Bool)] -> Str
  :d "Lowers WebAssembly function definitions into a complete module envelope."
  (wat-mod funcs-wat use-mem))

(df wat-emit [(fn-name Str) (arg-a Str) (arg-b Str) (op Str) (ret-ty Str)] -> Str
  :d "Helper to emit a two-argument binary arithmetic function in WAT."
  (let [(w-ty (wat-type ret-ty))
        (params (str "(param $" arg-a " " w-ty ") (param $" arg-b " " w-ty ")"))
        (instr (wat-op op ret-ty))
        (body (str instr " " (wat-get arg-a) " " (wat-get arg-b)))
        (fn-def (wat-fn fn-name params ret-ty body true))]
    (emit-wat-module (str "  " fn-def) false)))

(df emit-wasi-imports [] -> Str
  :d "Emits WASI snapshot preview 1 host function import declarations for wasm32-wasip1 runtime linking."
  (str "  (import \"wasi_snapshot_preview1\" \"fd_write\" (func $fd_write (param i32 i32 i32 i32) (result i32)))\n"
       "  (import \"wasi_snapshot_preview1\" \"fd_read\" (func $fd_read (param i32 i32 i32 i32) (result i32)))\n"
       "  (import \"wasi_snapshot_preview1\" \"proc_exit\" (func $proc_exit (param i32)))\n"
       "  (import \"wasi_snapshot_preview1\" \"clock_time_get\" (func $clock_time_get (param i32 i64 i32) (result i32)))"))

(df emit-wasi-fd-write [(fd I64) (iovs-offset I64) (iovs-len I64) (nwritten-offset I64)] -> Str
  :d "Emits WebAssembly Text lowering for wasi_snapshot_preview1 fd_write invocation with iovec buffer arguments."
  (str "(call $fd_write (i32.const " fd ") (i32.const " iovs-offset ") (i32.const " iovs-len ") (i32.const " nwritten-offset "))"))

(df emit-wasi-proc-exit [(exit-code I64)] -> Str
  :d "Emits WebAssembly Text lowering for wasi_snapshot_preview1 proc_exit invocation terminating process execution."
  (str "(call $proc_exit (i32.const " exit-code "))"))

(df emit-wasi-clock-time-get [(clock-id I64) (precision I64) (time-offset I64)] -> Str
  :d "Emits WebAssembly Text lowering for wasi_snapshot_preview1 clock_time_get high-resolution timestamp queries."
  (str "(call $clock_time_get (i32.const " clock-id ") (i64.const " precision ") (i32.const " time-offset "))"))

(df emit-wasm-memory-model [(initial-pages I64) (max-pages I64)] -> Str
  :d "Emits WebAssembly linear memory export declaration with initial and maximum page bounds."
  (if (> max-pages 0)
      (str "  (memory (export \"memory\") " initial-pages " " max-pages ")\n")
      (str "  (memory (export \"memory\") " initial-pages ")\n")))

(df emit-wasm-export-dispatch [(module-name Str)] -> Str
  :d "Emits sovereign in-browser Batch RPC dispatcher export signatures for WebAssembly linear memory."
  (str "  (func $asl_alloc (export \"asl_alloc\") (param $size i32) (result i32)\n"
       "    (i32.const 65536))\n"
       "  (func $asl_free (export \"asl_free\") (param $ptr i32) (param $size i32))\n"
       "  (func $asl_rpc_dispatch (export \"asl_rpc_dispatch\") (param $in_ptr i32) (param $in_len i32) (param $out_ptr i32) (result i32)\n"
       "    (i32.const 0))\n"))

(df emit-asl-core-wasm-module [(funcs-wat Str)] -> Str
  :d "Emits complete standalone asl-core.wasm module envelope with WASI preview 1 imports and Batch RPC exports."
  (str "(module\n"
       (emit-wasi-imports) "\n"
       (emit-wasm-memory-model 1 256)
       (emit-wasm-export-dispatch "asl-core")
       funcs-wat "\n"
       ")"))

