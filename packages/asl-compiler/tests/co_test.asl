(module asl-compiler/coTest
  :d "Pure AgentScript co-testing parity verification suite comparing evaluator outputs and WASM lowering semantics across algebraic, boolean, and control forms."
  :x [testCoAlgebraicParity
      testCoComparisonParity
      testCoLogicParity
      testCoControlParity
      testCoWasmLoweringParity
      runTests]
  :i [(evaluator :a ev) (reader :a rd)])

(df evalIntExpr [(expr rd/SExpr)] -> Int64
  :d "Evaluates an S-expression with root environment and extracts integer value."
  (let [(env (ev/makeRootEnv))
        (res (ev/evalSexpr expr env))]
    (mt res
      ((ev/valInt n) n)
      (_ 0))))

(df evalBoolExpr [(expr rd/SExpr)] -> Bool
  :d "Evaluates an S-expression with root environment and extracts boolean value."
  (let [(env (ev/makeRootEnv))
        (res (ev/evalSexpr expr env))]
    (mt res
      ((ev/valBool b) b)
      (_ false))))

(df lowerWatBinop [(op Str) (ty Str)] -> Str
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

(df lowerWatConst [(v Str) (ty Str)] -> Str
  :d "Lowers a literal value to WebAssembly const instruction."
  (let [(pfx (if (= ty "I32") "i32" (if (= ty "Bool") "i32" "i64")))]
    (str "(" pfx ".const " v ")")))

(df testCoAlgebraicParity [] -> Bool
  :d "Verifies evaluator evaluation parity for basic and nested algebraic expressions."
  (let [(e-add (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "100") (rd/makeAtom "250"))))
        (eSub (rd/makeList (list (rd/makeAtom "-") (rd/makeAtom "500") (rd/makeAtom "125"))))
        (eMul (rd/makeList (list (rd/makeAtom "*") (rd/makeAtom "12") (rd/makeAtom "12"))))
        (eDiv (rd/makeList (list (rd/makeAtom "/") (rd/makeAtom "144") (rd/makeAtom "12"))))
        (eMod (rd/makeList (list (rd/makeAtom "mod") (rd/makeAtom "47") (rd/makeAtom "7"))))
        (nestedInner (rd/makeList (list (rd/makeAtom "*") (rd/makeAtom "3") (rd/makeAtom "5"))))
        (eNested (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "10") nestedInner)))]
    (assert (= (evalIntExpr e-add) 350) "Addition parity: 100 + 250 must equal 350")
    (assert (= (evalIntExpr eSub) 375) "Subtraction parity: 500 - 125 must equal 375")
    (assert (= (evalIntExpr eMul) 144) "Multiplication parity: 12 * 12 must equal 144")
    (assert (= (evalIntExpr eDiv) 12) "Division parity: 144 / 12 must equal 12")
    (assert (= (evalIntExpr eMod) 5) "Modulo parity: 47 mod 7 must equal 5")
    (assert (= (evalIntExpr eNested) 25) "Nested algebraic parity: 10 + (3 * 5) must equal 25")
    true))

(df testCoComparisonParity [] -> Bool
  :d "Verifies evaluator comparison predicates match strict relational semantics."
  (let [(eEq (rd/makeList (list (rd/makeAtom "=") (rd/makeAtom "42") (rd/makeAtom "42"))))
        (eEqF (rd/makeList (list (rd/makeAtom "=") (rd/makeAtom "42") (rd/makeAtom "43"))))
        (eNeq (rd/makeList (list (rd/makeAtom "!=") (rd/makeAtom "10") (rd/makeAtom "20"))))
        (eLt (rd/makeList (list (rd/makeAtom "<") (rd/makeAtom "5") (rd/makeAtom "15"))))
        (eGte (rd/makeList (list (rd/makeAtom ">=") (rd/makeAtom "20") (rd/makeAtom "20"))))
        (eGt (rd/makeList (list (rd/makeAtom ">") (rd/makeAtom "30") (rd/makeAtom "10"))))]
    (assert (evalBoolExpr eEq) "Equality parity: 42 = 42 must evaluate true")
    (assert (not (evalBoolExpr eEqF)) "Equality disparity: 42 = 43 must evaluate false")
    (assert (evalBoolExpr eNeq) "Inequality parity: 10 != 20 must evaluate true")
    (assert (evalBoolExpr eLt) "Less-than parity: 5 < 15 must evaluate true")
    (assert (evalBoolExpr eGte) "Greater-or-equal parity: 20 >= 20 must evaluate true")
    (assert (evalBoolExpr eGt) "Greater-than parity: 30 > 10 must evaluate true")
    true))

(df testCoLogicParity [] -> Bool
  :d "Verifies boolean logic evaluation across truth tables."
  (let [(eAndTt (rd/makeList (list (rd/makeAtom "and") (rd/makeAtom "true") (rd/makeAtom "true"))))
        (eAndTf (rd/makeList (list (rd/makeAtom "and") (rd/makeAtom "true") (rd/makeAtom "false"))))
        (eOrFt (rd/makeList (list (rd/makeAtom "or") (rd/makeAtom "false") (rd/makeAtom "true"))))
        (eOrFf (rd/makeList (list (rd/makeAtom "or") (rd/makeAtom "false") (rd/makeAtom "false"))))
        (eNotT (rd/makeList (list (rd/makeAtom "not") (rd/makeAtom "true"))))
        (eNotF (rd/makeList (list (rd/makeAtom "not") (rd/makeAtom "false"))))]
    (assert (evalBoolExpr eAndTt) "Boolean logic and (true, true) must evaluate true")
    (assert (not (evalBoolExpr eAndTf)) "Boolean logic and (true, false) must evaluate false")
    (assert (evalBoolExpr eOrFt) "Boolean logic or (false, true) must evaluate true")
    (assert (not (evalBoolExpr eOrFf)) "Boolean logic or (false, false) must evaluate false")
    (assert (not (evalBoolExpr eNotT)) "Boolean logic not (true) must evaluate false")
    (assert (evalBoolExpr eNotF) "Boolean logic not (false) must evaluate true")
    true))

(df testCoControlParity [] -> Bool
  :d "Verifies conditional branching and nested control flow evaluator execution."
  (let [(eIfThen (rd/makeList (list (rd/makeAtom "if") (rd/makeAtom "true") (rd/makeAtom "100") (rd/makeAtom "200"))))
        (eIfElse (rd/makeList (list (rd/makeAtom "if") (rd/makeAtom "false") (rd/makeAtom "100") (rd/makeAtom "200"))))
        (innerCond (rd/makeList (list (rd/makeAtom "<") (rd/makeAtom "10") (rd/makeAtom "20"))))
        (eIfDynamic (rd/makeList (list (rd/makeAtom "if") innerCond (rd/makeAtom "777") (rd/makeAtom "888"))))
        (nestedElse (rd/makeList (list (rd/makeAtom "if") (rd/makeAtom "false") (rd/makeAtom "1") (rd/makeAtom "2"))))
        (eNestedIf (rd/makeList (list (rd/makeAtom "if") (rd/makeAtom "false") (rd/makeAtom "99") nestedElse)))]
    (assert (= (evalIntExpr eIfThen) 100) "If branch then: truth condition must select 100")
    (assert (= (evalIntExpr eIfElse) 200) "If branch else: falsy condition must select 200")
    (assert (= (evalIntExpr eIfDynamic) 777) "Dynamic predicate branch must select 777")
    (assert (= (evalIntExpr eNestedIf) 2) "Nested if branch must resolve alternate inner branch 2")
    true))

(df testCoWasmLoweringParity [] -> Bool
  :d "Verifies WebAssembly Text lowering mappings match evaluator arithmetic and logical operators."
  (let [(wAdd (lowerWatBinop "+" "I64"))
        (wSub (lowerWatBinop "-" "I64"))
        (wMul (lowerWatBinop "*" "I64"))
        (wDiv (lowerWatBinop "/" "I64"))
        (wRem (lowerWatBinop "mod" "I64"))
        (wEq (lowerWatBinop "=" "I64"))
        (wLt (lowerWatBinop "<" "I64"))
        (wAnd (lowerWatBinop "and" "Bool"))
        (wOr (lowerWatBinop "or" "Bool"))
        (cVal (lowerWatConst "42" "I64"))]
    (assert (= wAdd "i64.add") "WASM lowering for + must emit i64.add")
    (assert (= wSub "i64.sub") "WASM lowering for - must emit i64.sub")
    (assert (= wMul "i64.mul") "WASM lowering for * must emit i64.mul")
    (assert (= wDiv "i64.div_s") "WASM lowering for / must emit i64.div_s")
    (assert (= wRem "i64.rem_s") "WASM lowering for mod must emit i64.rem_s")
    (assert (= wEq "i64.eq") "WASM lowering for = must emit i64.eq")
    (assert (= wLt "i64.lt_s") "WASM lowering for < must emit i64.lt_s")
    (assert (= wAnd "i32.and") "WASM lowering for and must emit i32.and")
    (assert (= wOr "i32.or") "WASM lowering for or must emit i32.or")
    (assert (= cVal "(i64.const 42)") "WASM lowering for constant 42 must emit (i64.const 42)")
    true))

(df runTests [] -> Bool
  :d "Runs all co-testing parity test suites."
  (let [(t1 (testCoAlgebraicParity))
        (t2 (testCoComparisonParity))
        (t3 (testCoLogicParity))
        (t4 (testCoControlParity))
        (t5 (testCoWasmLoweringParity))] (and t1 (and t2 (and t3 (and t4 t5))))))
