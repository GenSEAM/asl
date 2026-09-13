(module asl-compiler/evaluatorTest
  :d "Unit tests for 100% pure AgentScript evaluator engine."
  :x [testEvalLiterals
      testEvalArithmetic
      testEvalComparison
      testEvalLogic
      testEvalStrings
      testEvalEnvBinding
      testEvalAssert
      testEvalIfBranch
      runTests]
  :i [(evaluator :a ev) (reader :a rd)])

(df testEvalLiterals [] -> Bool
  :d "Verifies evaluation of integer, boolean, string, and null literals."
  (let [(env (ev/makeRootEnv))
        (vInt (ev/evalSexpr (rd/makeAtom "42") env))
        (vTrue (ev/evalSexpr (rd/makeAtom "true") env))
        (vFalse (ev/evalSexpr (rd/makeAtom "false") env))
        (vNull (ev/evalSexpr (rd/makeAtom "null") env))]
    (assert (mt vInt ((ev/valInt n) (= n 42)) (_ false)) "int literal")
    (assert (mt vTrue ((ev/valBool b) b) (_ false)) "true literal")
    (assert (mt vFalse ((ev/valBool b) (not b)) (_ false)) "false literal")
    (assert (mt vNull ((ev/valNull) true) (_ false)) "null literal")
    true))

(df testEvalArithmetic [] -> Bool
  :d "Verifies evaluation of arithmetic builtins (+, -, *, /, mod)."
  (let [(env (ev/makeRootEnv))
        (addExpr (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "10") (rd/makeAtom "20"))))
        (subExpr (rd/makeList (list (rd/makeAtom "-") (rd/makeAtom "50") (rd/makeAtom "15"))))
        (mulExpr (rd/makeList (list (rd/makeAtom "*") (rd/makeAtom "6") (rd/makeAtom "7"))))
        (divExpr (rd/makeList (list (rd/makeAtom "/") (rd/makeAtom "100") (rd/makeAtom "4"))))
        (modExpr (rd/makeList (list (rd/makeAtom "mod") (rd/makeAtom "17") (rd/makeAtom "5"))))
        (rAdd (ev/evalSexpr addExpr env))
        (rSub (ev/evalSexpr subExpr env))
        (rMul (ev/evalSexpr mulExpr env))
        (rDiv (ev/evalSexpr divExpr env))
        (rMod (ev/evalSexpr modExpr env))]
    (assert (mt rAdd ((ev/valInt n) (= n 30)) (_ false)) "add")
    (assert (mt rSub ((ev/valInt n) (= n 35)) (_ false)) "sub")
    (assert (mt rMul ((ev/valInt n) (= n 42)) (_ false)) "mul")
    (assert (mt rDiv ((ev/valInt n) (= n 25)) (_ false)) "div")
    (assert (mt rMod ((ev/valInt n) (= n 2)) (_ false)) "mod")
    true))

(df testEvalComparison [] -> Bool
  :d "Verifies evaluation of comparison operators (=, !=, <, >=)."
  (let [(env (ev/makeRootEnv))
        (eqExpr (rd/makeList (list (rd/makeAtom "=") (rd/makeAtom "5") (rd/makeAtom "5"))))
        (neqExpr (rd/makeList (list (rd/makeAtom "!=") (rd/makeAtom "5") (rd/makeAtom "6"))))
        (ltExpr (rd/makeList (list (rd/makeAtom "<") (rd/makeAtom "3") (rd/makeAtom "8"))))
        (gteExpr (rd/makeList (list (rd/makeAtom ">=") (rd/makeAtom "10") (rd/makeAtom "10"))))
        (rEq (ev/evalSexpr eqExpr env))
        (rNeq (ev/evalSexpr neqExpr env))
        (rLt (ev/evalSexpr ltExpr env))
        (rGte (ev/evalSexpr gteExpr env))]
    (assert (mt rEq ((ev/valBool b) b) (_ false)) "eq")
    (assert (mt rNeq ((ev/valBool b) b) (_ false)) "neq")
    (assert (mt rLt ((ev/valBool b) b) (_ false)) "lt")
    (assert (mt rGte ((ev/valBool b) b) (_ false)) "gte")
    true))

(df testEvalLogic [] -> Bool
  :d "Verifies evaluation of boolean logic builtins (and, or)."
  (let [(env (ev/makeRootEnv))
        (andExpr (rd/makeList (list (rd/makeAtom "and") (rd/makeAtom "true") (rd/makeAtom "false"))))
        (orExpr (rd/makeList (list (rd/makeAtom "or") (rd/makeAtom "false") (rd/makeAtom "true"))))
        (rAnd (ev/evalSexpr andExpr env))
        (rOr (ev/evalSexpr orExpr env))]
    (assert (mt rAnd ((ev/valBool b) (not b)) (_ false)) "and")
    (assert (mt rOr ((ev/valBool b) b) (_ false)) "or")
    true))

(df testEvalStrings [] -> Bool
  :d "Verifies evaluation of string operations (str-concat, str-len, str-contains?)."
  (let [(env (ev/makeRootEnv))
        (catExpr (rd/makeList (list (rd/makeAtom "str-concat") (rd/makeAtom "\"hello \"") (rd/makeAtom "\"world\""))))
        (lenExpr (rd/makeList (list (rd/makeAtom "str-len") (rd/makeAtom "\"pipeline\""))))
        (contExpr (rd/makeList (list (rd/makeAtom "str-contains?") (rd/makeAtom "\"runtime engine\"") (rd/makeAtom "\"engine\""))))
        (rCat (ev/evalSexpr catExpr env))
        (rLen (ev/evalSexpr lenExpr env))
        (rCont (ev/evalSexpr contExpr env))]
    (assert (mt rCat ((ev/valStr s) (= s "hello world")) (_ false)) "cat")
    (assert (mt rLen ((ev/valInt n) (= n 8)) (_ false)) "len")
    (assert (mt rCont ((ev/valBool b) b) (_ false)) "cont")
    true))

(df testEvalEnvBinding [] -> Bool
  :d "Verifies environment binding creation and lexical lookup."
  (let [(root (ev/makeRootEnv))
        (b1 (ev/envBind root "x" (ev/valInt 100)))
        (child (ev/makeChildEnv b1))
        (b2 (ev/envBind child "y" (ev/valInt 200)))
        (lookX (ev/envLookup b2 "x"))
        (lookY (ev/envLookup b2 "y"))
        (lookZ (ev/envLookup b2 "z"))]
    (assert (mt lookX ((some (ev/valInt v)) (= v 100)) (_ false)) "lookup x")
    (assert (mt lookY ((some (ev/valInt v)) (= v 200)) (_ false)) "lookup y")
    (assert (mt lookZ ((none) true) (_ false)) "lookup z none")
    true))

(df testEvalAssert [] -> Bool
  :d "Verifies falsifiable assertion semantics: truthy returns ok, falsy returns val-error."
  (let [(env (ev/makeRootEnv))
        (passExpr (rd/makeList (list (rd/makeAtom "assert") (rd/makeAtom "true") (rd/makeAtom "\"should pass\""))))
        (failExpr (rd/makeList (list (rd/makeAtom "assert") (rd/makeAtom "false") (rd/makeAtom "\"expected failure\""))))
        (rPass (ev/evalSexpr passExpr env))
        (rFail (ev/evalSexpr failExpr env))]
    (assert (ev/evalResultIsOk? rPass) "r-pass ok")
    (assert (not (ev/evalResultIsOk? rFail)) "r-fail not ok")
    (assert (mt rFail ((ev/valError msg) (= msg "expected failure")) (_ false)) "r-fail msg")
    true))

(df testEvalIfBranch [] -> Bool
  :d "Verifies branch selection in conditional if forms."
  (let [(env (ev/makeRootEnv))
        (thenExpr (rd/makeList (list (rd/makeAtom "if") (rd/makeAtom "true") (rd/makeAtom "1") (rd/makeAtom "2"))))
        (elseExpr (rd/makeList (list (rd/makeAtom "if") (rd/makeAtom "false") (rd/makeAtom "1") (rd/makeAtom "2"))))
        (rThen (ev/evalSexpr thenExpr env))
        (rElse (ev/evalSexpr elseExpr env))]
    (assert (mt rThen ((ev/valInt n) (= n 1)) (_ false)) "then branch")
    (assert (mt rElse ((ev/valInt n) (= n 2)) (_ false)) "else branch")
    true))

(df runTests [] -> Bool
  :d "Runs all pure AgentScript evaluator engine test suites."
  (do
    (assert (testEvalLiterals) "test-eval-literals must pass")
    (assert (testEvalArithmetic) "test-eval-arithmetic must pass")
    (assert (testEvalComparison) "test-eval-comparison must pass")
    (assert (testEvalLogic) "test-eval-logic must pass")
    (assert (testEvalStrings) "test-eval-strings must pass")
    (assert (testEvalEnvBinding) "test-eval-env-binding must pass")
    (assert (testEvalAssert) "test-eval-assert must pass")
    (assert (testEvalIfBranch) "test-eval-if-branch must pass")
    true))
