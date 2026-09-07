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
      emit-wat-module]
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
