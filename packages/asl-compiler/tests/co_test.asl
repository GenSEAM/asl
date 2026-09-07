(module asl-compiler/co-test
  :d "Pure AgentScript co-testing parity verification suite comparing evaluator outputs and WASM lowering semantics across algebraic, boolean, and control forms."
  :x [test-co-algebraic-parity
      test-co-comparison-parity
      test-co-logic-parity
      test-co-control-parity
      test-co-wasm-lowering-parity
      run-tests]
  :i [(evaluator :a ev) (reader :a rd)])

(df eval-int-expr [(expr rd/SExpr)] -> Int64
  :d "Evaluates an S-expression with root environment and extracts integer value."
  (let [(env (ev/make-root-env))
        (res (ev/eval-sexpr expr env))]
    (mt res
      ((ev/val-int n) n)
      (_ 0))))

(df eval-bool-expr [(expr rd/SExpr)] -> Bool
  :d "Evaluates an S-expression with root environment and extracts boolean value."
  (let [(env (ev/make-root-env))
        (res (ev/eval-sexpr expr env))]
    (mt res
      ((ev/val-bool b) b)
      (_ false))))

(df lower-wat-binop [(op Str) (ty Str)] -> Str
  :d "Lowers a binary operator to standard WebAssembly instruction mnemonic."
  (let [(pfx (if (= ty "I32") "i32" (if (= ty "F64") "f64" "i64")))]
    (cond
      ((= op "+") (str pfx ".add"))
      ((= op "-") (str pfx ".sub"))
      ((= op "*") (str pfx ".mul"))
      ((= op "/") (if (= pfx "f64") "f64.div" (str pfx ".div_s")))
      ((= op "mod") (str pfx ".rem_s"))
      ((= op "=") (str pfx ".eq"))
      ((= op "!=") (str pfx ".ne"))
      ((= op "<") (if (= pfx "f64") "f64.lt" (str pfx ".lt_s")))
      ((= op "<=") (if (= pfx "f64") "f64.le" (str pfx ".le_s")))
      ((= op ">") (if (= pfx "f64") "f64.gt" (str pfx ".gt_s")))
      ((= op ">=") (if (= pfx "f64") "f64.ge" (str pfx ".ge_s")))
      ((= op "and") "i32.and")
      ((= op "or") "i32.or")
      (:else (str pfx ".add")))))

(df lower-wat-const [(v Str) (ty Str)] -> Str
  :d "Lowers a literal value to WebAssembly const instruction."
  (let [(pfx (if (= ty "I32") "i32" (if (= ty "Bool") "i32" "i64")))]
    (str "(" pfx ".const " v ")")))

(df test-co-algebraic-parity [] -> Bool
  :d "Verifies evaluator evaluation parity for basic and nested algebraic expressions."
  (let [(e-add (rd/make-list (list (rd/make-atom "+") (rd/make-atom "100") (rd/make-atom "250"))))
        (e-sub (rd/make-list (list (rd/make-atom "-") (rd/make-atom "500") (rd/make-atom "125"))))
        (e-mul (rd/make-list (list (rd/make-atom "*") (rd/make-atom "12") (rd/make-atom "12"))))
        (e-div (rd/make-list (list (rd/make-atom "/") (rd/make-atom "144") (rd/make-atom "12"))))
        (e-mod (rd/make-list (list (rd/make-atom "mod") (rd/make-atom "47") (rd/make-atom "7"))))
        (nested-inner (rd/make-list (list (rd/make-atom "*") (rd/make-atom "3") (rd/make-atom "5"))))
        (e-nested (rd/make-list (list (rd/make-atom "+") (rd/make-atom "10") nested-inner)))]
    (assert (= (eval-int-expr e-add) 350) "Addition parity: 100 + 250 must equal 350")
    (assert (= (eval-int-expr e-sub) 375) "Subtraction parity: 500 - 125 must equal 375")
    (assert (= (eval-int-expr e-mul) 144) "Multiplication parity: 12 * 12 must equal 144")
    (assert (= (eval-int-expr e-div) 12) "Division parity: 144 / 12 must equal 12")
    (assert (= (eval-int-expr e-mod) 5) "Modulo parity: 47 mod 7 must equal 5")
    (assert (= (eval-int-expr e-nested) 25) "Nested algebraic parity: 10 + (3 * 5) must equal 25")
    true))

(df test-co-comparison-parity [] -> Bool
  :d "Verifies evaluator comparison predicates match strict relational semantics."
  (let [(e-eq (rd/make-list (list (rd/make-atom "=") (rd/make-atom "42") (rd/make-atom "42"))))
        (e-eq-f (rd/make-list (list (rd/make-atom "=") (rd/make-atom "42") (rd/make-atom "43"))))
        (e-neq (rd/make-list (list (rd/make-atom "!=") (rd/make-atom "10") (rd/make-atom "20"))))
        (e-lt (rd/make-list (list (rd/make-atom "<") (rd/make-atom "5") (rd/make-atom "15"))))
        (e-gte (rd/make-list (list (rd/make-atom ">=") (rd/make-atom "20") (rd/make-atom "20"))))
        (e-gt (rd/make-list (list (rd/make-atom ">") (rd/make-atom "30") (rd/make-atom "10"))))]
    (assert (eval-bool-expr e-eq) "Equality parity: 42 = 42 must evaluate true")
    (assert (not (eval-bool-expr e-eq-f)) "Equality disparity: 42 = 43 must evaluate false")
    (assert (eval-bool-expr e-neq) "Inequality parity: 10 != 20 must evaluate true")
    (assert (eval-bool-expr e-lt) "Less-than parity: 5 < 15 must evaluate true")
    (assert (eval-bool-expr e-gte) "Greater-or-equal parity: 20 >= 20 must evaluate true")
    (assert (eval-bool-expr e-gt) "Greater-than parity: 30 > 10 must evaluate true")
    true))

(df test-co-logic-parity [] -> Bool
  :d "Verifies boolean logic evaluation across truth tables."
  (let [(e-and-tt (rd/make-list (list (rd/make-atom "and") (rd/make-atom "true") (rd/make-atom "true"))))
        (e-and-tf (rd/make-list (list (rd/make-atom "and") (rd/make-atom "true") (rd/make-atom "false"))))
        (e-or-ft (rd/make-list (list (rd/make-atom "or") (rd/make-atom "false") (rd/make-atom "true"))))
        (e-or-ff (rd/make-list (list (rd/make-atom "or") (rd/make-atom "false") (rd/make-atom "false"))))
        (e-not-t (rd/make-list (list (rd/make-atom "not") (rd/make-atom "true"))))
        (e-not-f (rd/make-list (list (rd/make-atom "not") (rd/make-atom "false"))))]
    (assert (eval-bool-expr e-and-tt) "Boolean logic and (true, true) must evaluate true")
    (assert (not (eval-bool-expr e-and-tf)) "Boolean logic and (true, false) must evaluate false")
    (assert (eval-bool-expr e-or-ft) "Boolean logic or (false, true) must evaluate true")
    (assert (not (eval-bool-expr e-or-ff)) "Boolean logic or (false, false) must evaluate false")
    (assert (not (eval-bool-expr e-not-t)) "Boolean logic not (true) must evaluate false")
    (assert (eval-bool-expr e-not-f) "Boolean logic not (false) must evaluate true")
    true))

(df test-co-control-parity [] -> Bool
  :d "Verifies conditional branching and nested control flow evaluator execution."
  (let [(e-if-then (rd/make-list (list (rd/make-atom "if") (rd/make-atom "true") (rd/make-atom "100") (rd/make-atom "200"))))
        (e-if-else (rd/make-list (list (rd/make-atom "if") (rd/make-atom "false") (rd/make-atom "100") (rd/make-atom "200"))))
        (inner-cond (rd/make-list (list (rd/make-atom "<") (rd/make-atom "10") (rd/make-atom "20"))))
        (e-if-dynamic (rd/make-list (list (rd/make-atom "if") inner-cond (rd/make-atom "777") (rd/make-atom "888"))))
        (nested-else (rd/make-list (list (rd/make-atom "if") (rd/make-atom "false") (rd/make-atom "1") (rd/make-atom "2"))))
        (e-nested-if (rd/make-list (list (rd/make-atom "if") (rd/make-atom "false") (rd/make-atom "99") nested-else)))]
    (assert (= (eval-int-expr e-if-then) 100) "If branch then: truth condition must select 100")
    (assert (= (eval-int-expr e-if-else) 200) "If branch else: falsy condition must select 200")
    (assert (= (eval-int-expr e-if-dynamic) 777) "Dynamic predicate branch must select 777")
    (assert (= (eval-int-expr e-nested-if) 2) "Nested if branch must resolve alternate inner branch 2")
    true))

(df test-co-wasm-lowering-parity [] -> Bool
  :d "Verifies WebAssembly Text lowering mappings match evaluator arithmetic and logical operators."
  (let [(w-add (lower-wat-binop "+" "I64"))
        (w-sub (lower-wat-binop "-" "I64"))
        (w-mul (lower-wat-binop "*" "I64"))
        (w-div (lower-wat-binop "/" "I64"))
        (w-rem (lower-wat-binop "mod" "I64"))
        (w-eq (lower-wat-binop "=" "I64"))
        (w-lt (lower-wat-binop "<" "I64"))
        (w-and (lower-wat-binop "and" "Bool"))
        (w-or (lower-wat-binop "or" "Bool"))
        (c-val (lower-wat-const "42" "I64"))]
    (assert (= w-add "i64.add") "WASM lowering for + must emit i64.add")
    (assert (= w-sub "i64.sub") "WASM lowering for - must emit i64.sub")
    (assert (= w-mul "i64.mul") "WASM lowering for * must emit i64.mul")
    (assert (= w-div "i64.div_s") "WASM lowering for / must emit i64.div_s")
    (assert (= w-rem "i64.rem_s") "WASM lowering for mod must emit i64.rem_s")
    (assert (= w-eq "i64.eq") "WASM lowering for = must emit i64.eq")
    (assert (= w-lt "i64.lt_s") "WASM lowering for < must emit i64.lt_s")
    (assert (= w-and "i32.and") "WASM lowering for and must emit i32.and")
    (assert (= w-or "i32.or") "WASM lowering for or must emit i32.or")
    (assert (= c-val "(i64.const 42)") "WASM lowering for constant 42 must emit (i64.const 42)")
    true))

(df run-tests [] -> Bool
  :d "Runs all co-testing parity test suites."
  (let [(_t1 (test-co-algebraic-parity))
        (_t2 (test-co-comparison-parity))
        (_t3 (test-co-logic-parity))
        (_t4 (test-co-control-parity))
        (_t5 (test-co-wasm-lowering-parity))]
    true))
