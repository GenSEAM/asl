(module asl-compiler/evaluatorTest :x [testEvalLiterals! testEvalArithmetic! testEvalComparison! testEvalLogic! testEvalStrings! testEvalEnvBinding testEvalAssert! testEvalIfBranch! testZeroTruthiness runTests] :i [(evaluator :a ev) (reader :a rd)])

fn testEvalLiterals! -> Bool
  (let [(env (ev/makeRootEnv)) (vInt (ev/evalSexpr! (rd/makeAtom "42") env)) (vTrue (ev/evalSexpr! (rd/makeAtom "true") env)) (vFalse (ev/evalSexpr! (rd/makeAtom "false") env)) (vNull (ev/evalSexpr! (rd/makeAtom "null") env))]
    (do
      (assert (mt vInt ((ev/valInt n) (= n 42)) (_ false)) "int literal")
      (refute (mt vInt ((ev/valInt n) (!= n 42)) (_ true)) "int literal refutes non-42")
      (assert (mt vTrue ((ev/valBool b) b) (_ false)) "true literal")
      (refute (mt vTrue ((ev/valBool b) (not b)) (_ true)) "true literal refutes false")
      (assert (mt vFalse ((ev/valBool b) (not b)) (_ false)) "false literal")
      (refute (mt vFalse ((ev/valBool b) b) (_ true)) "false literal refutes true")
      (assert (mt vNull ((ev/valNull) true) (_ false)) "null literal")
      (refute (mt vNull ((ev/valNull) false) (_ true)) "null literal refutes non-null")
      true))

fn testEvalArithmetic! -> Bool
  (let [(env (ev/makeRootEnv)) (addExpr (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "10") (rd/makeAtom "20")))) (subExpr (rd/makeList (list (rd/makeAtom "-") (rd/makeAtom "50") (rd/makeAtom "15")))) (mulExpr (rd/makeList (list (rd/makeAtom "*") (rd/makeAtom "6") (rd/makeAtom "7")))) (divExpr (rd/makeList (list (rd/makeAtom "/") (rd/makeAtom "100") (rd/makeAtom "4")))) (modExpr (rd/makeList (list (rd/makeAtom "mod") (rd/makeAtom "17") (rd/makeAtom "5")))) (rAdd (ev/evalSexpr! addExpr env)) (rSub (ev/evalSexpr! subExpr env)) (rMul (ev/evalSexpr! mulExpr env)) (rDiv (ev/evalSexpr! divExpr env)) (rMod (ev/evalSexpr! modExpr env))]
    (do
      (assert (mt rAdd ((ev/valInt n) (= n 30)) (_ false)) "add")
      (refute (mt rAdd ((ev/valInt n) (!= n 30)) (_ true)) "add refutes non-30")
      (assert (mt rSub ((ev/valInt n) (= n 35)) (_ false)) "sub")
      (refute (mt rSub ((ev/valInt n) (!= n 35)) (_ true)) "sub refutes non-35")
      (assert (mt rMul ((ev/valInt n) (= n 42)) (_ false)) "mul")
      (refute (mt rMul ((ev/valInt n) (!= n 42)) (_ true)) "mul refutes non-42")
      (assert (mt rDiv ((ev/valInt n) (= n 25)) (_ false)) "div")
      (refute (mt rDiv ((ev/valInt n) (!= n 25)) (_ true)) "div refutes non-25")
      (assert (mt rMod ((ev/valInt n) (= n 2)) (_ false)) "mod")
      (refute (mt rMod ((ev/valInt n) (!= n 2)) (_ true)) "mod refutes non-2")
      true))

fn testEvalComparison! -> Bool
  (let [(env (ev/makeRootEnv)) (eqExpr (rd/makeList (list (rd/makeAtom "=") (rd/makeAtom "5") (rd/makeAtom "5")))) (neqExpr (rd/makeList (list (rd/makeAtom "!=") (rd/makeAtom "5") (rd/makeAtom "6")))) (ltExpr (rd/makeList (list (rd/makeAtom "<") (rd/makeAtom "3") (rd/makeAtom "8")))) (gteExpr (rd/makeList (list (rd/makeAtom ">=") (rd/makeAtom "10") (rd/makeAtom "10")))) (rEq (ev/evalSexpr! eqExpr env)) (rNeq (ev/evalSexpr! neqExpr env)) (rLt (ev/evalSexpr! ltExpr env)) (rGte (ev/evalSexpr! gteExpr env))]
    (do
      (assert (mt rEq ((ev/valBool b) b) (_ false)) "eq")
      (refute (mt rEq ((ev/valBool b) (not b)) (_ true)) "eq refutes false")
      (assert (mt rNeq ((ev/valBool b) b) (_ false)) "neq")
      (refute (mt rNeq ((ev/valBool b) (not b)) (_ true)) "neq refutes false")
      (assert (mt rLt ((ev/valBool b) b) (_ false)) "lt")
      (refute (mt rLt ((ev/valBool b) (not b)) (_ true)) "lt refutes false")
      (assert (mt rGte ((ev/valBool b) b) (_ false)) "gte")
      (refute (mt rGte ((ev/valBool b) (not b)) (_ true)) "gte refutes false")
      true))

fn testEvalLogic! -> Bool
  (let [(env (ev/makeRootEnv)) (andExpr (rd/makeList (list (rd/makeAtom "and") (rd/makeAtom "true") (rd/makeAtom "false")))) (orExpr (rd/makeList (list (rd/makeAtom "or") (rd/makeAtom "false") (rd/makeAtom "true")))) (rAnd (ev/evalSexpr! andExpr env)) (rOr (ev/evalSexpr! orExpr env))]
    (do
      (assert (mt rAnd ((ev/valBool b) (not b)) (_ false)) "and")
      (refute (mt rAnd ((ev/valBool b) b) (_ true)) "and refutes true")
      (assert (mt rOr ((ev/valBool b) b) (_ false)) "or")
      (refute (mt rOr ((ev/valBool b) (not b)) (_ true)) "or refutes false")
      true))

fn testEvalStrings! -> Bool
  (let [(env (ev/makeRootEnv)) (catExpr (rd/makeList (list (rd/makeAtom "str-concat") (rd/makeAtom "\"hello \"") (rd/makeAtom "\"world\"")))) (lenExpr (rd/makeList (list (rd/makeAtom "str-len") (rd/makeAtom "\"pipeline\"")))) (contExpr (rd/makeList (list (rd/makeAtom "str-contains?") (rd/makeAtom "\"runtime engine\"") (rd/makeAtom "\"engine\"")))) (rCat (ev/evalSexpr! catExpr env)) (rLen (ev/evalSexpr! lenExpr env)) (rCont (ev/evalSexpr! contExpr env))]
    (do
      (assert (mt rCat ((ev/valStr s) (= s "hello world")) (_ false)) "cat")
      (refute (mt rCat ((ev/valStr s) (!= s "hello world")) (_ true)) "cat refutes non-matching")
      (assert (mt rLen ((ev/valInt n) (= n 8)) (_ false)) "len")
      (refute (mt rLen ((ev/valInt n) (!= n 8)) (_ true)) "len refutes non-8")
      (assert (mt rCont ((ev/valBool b) b) (_ false)) "cont")
      (refute (mt rCont ((ev/valBool b) (not b)) (_ true)) "cont refutes false")
      true))

fn testEvalEnvBinding -> Bool
  (let [(root (ev/makeRootEnv)) (b1 (ev/envBind root "x" (ev/valInt 100))) (child (ev/makeChildEnv b1)) (b2 (ev/envBind child "y" (ev/valInt 200))) (lookX (ev/envLookup b2 "x")) (lookY (ev/envLookup b2 "y")) (lookZ (ev/envLookup b2 "z"))]
    (do
      (assert (mt lookX ((some inner) (mt inner ((ev/valInt v) (= v 100)) (_ false))) ((none) false)) "lookup x")
      (refute (mt lookX ((some inner) (mt inner ((ev/valInt v) (!= v 100)) (_ true))) ((none) true)) "lookup x refutes non-100")
      (assert (mt lookY ((some inner) (mt inner ((ev/valInt v) (= v 200)) (_ false))) ((none) false)) "lookup y")
      (refute (mt lookY ((some inner) (mt inner ((ev/valInt v) (!= v 200)) (_ true))) ((none) true)) "lookup y refutes non-200")
      (assert (mt lookZ ((none) true) (_ false)) "lookup z none")
      (refute (mt lookZ ((some _) true) (_ false)) "lookup z refutes some")
      true))

fn testEvalAssert! -> Bool
  (let [(env (ev/makeRootEnv)) (passExpr (rd/makeList (list (rd/makeAtom "assert") (rd/makeAtom "true") (rd/makeAtom "\"should pass\"")))) (failExpr (rd/makeList (list (rd/makeAtom "assert") (rd/makeAtom "false") (rd/makeAtom "\"expected failure\"")))) (rPass (ev/evalSexpr! passExpr env)) (rFail (ev/evalSexpr! failExpr env))]
    (do
      (assert (ev/evalResultIsOk? rPass) "r-pass ok")
      (refute (not (ev/evalResultIsOk? rPass)) "r-pass refutes error")
      (assert (not (ev/evalResultIsOk? rFail)) "r-fail not ok")
      (refute (ev/evalResultIsOk? rFail) "r-fail refutes ok")
      (assert (mt rFail ((ev/valError msg) (= msg "expected failure")) (_ false)) "r-fail msg")
      (refute (mt rFail ((ev/valError msg) (!= msg "expected failure")) (_ true)) "r-fail msg refutes wrong msg")
      true))

fn testEvalIfBranch! -> Bool
  (let [(env (ev/makeRootEnv)) (thenExpr (rd/makeList (list (rd/makeAtom "if") (rd/makeAtom "true") (rd/makeAtom "1") (rd/makeAtom "2")))) (elseExpr (rd/makeList (list (rd/makeAtom "if") (rd/makeAtom "false") (rd/makeAtom "1") (rd/makeAtom "2")))) (rThen (ev/evalSexpr! thenExpr env)) (rElse (ev/evalSexpr! elseExpr env))]
    (do
      (assert (mt rThen ((ev/valInt n) (= n 1)) (_ false)) "then branch")
      (refute (mt rThen ((ev/valInt n) (!= n 1)) (_ true)) "then branch refutes non-1")
      (assert (mt rElse ((ev/valInt n) (= n 2)) (_ false)) "else branch")
      (refute (mt rElse ((ev/valInt n) (!= n 2)) (_ true)) "else branch refutes non-2")
      true))

fn testZeroTruthiness -> Bool
  (do
    (assert (ev/truthy? (ev/valBool true)) "true is truthy")
    (refute (ev/truthy? (ev/valBool false)) "false is not truthy")
    (refute (ev/truthy? (ev/valNull)) "null is not truthy")
    (refute (ev/truthy? (ev/valInt 1)) "int 1 is not truthy under zero truthiness")
    (refute (ev/truthy? (ev/valInt 42)) "int 42 is not truthy under zero truthiness")
    (refute (ev/truthy? (ev/valStr "hello")) "non-empty str is not truthy under zero truthiness")
    (refute (ev/truthy? (ev/valList (list (ev/valInt 1)))) "non-empty list is not truthy under zero truthiness")
    (refute (ev/truthy? (ev/valMap (mapEmpty))) "empty map is not truthy under zero truthiness")
    true)

fn testValMapSemantics! -> Bool
  (let [(emptyMap (ev/valMap (mapEmpty))) (mapWithA (ev/valMap (mapSet (mapEmpty) "a" (ev/valInt 1)))) (mapWithA2 (ev/valMap (mapSet (mapEmpty) "a" (ev/valInt 1)))) (mapWithB (ev/valMap (mapSet (mapEmpty) "b" (ev/valInt 2))))]
    (do
      (assert (not (ev/truthy? emptyMap)) "valMap is not truthy")
      (refute (ev/truthy? emptyMap) "valMap truthiness refuted")
      (assert (not (ev/truthy? mapWithA)) "valMap with data is not truthy")
      (refute (ev/truthy? mapWithA) "valMap with data truthiness refuted")
      (assert (ev/evalResultIsOk? emptyMap) "valMap is ok result")
      (refute (not (ev/evalResultIsOk? emptyMap)) "valMap ok result refutes error")
      (assert (ev/evalValuesEqual? mapWithA mapWithA2) "valMap equality for identical maps")
      (refute (not (ev/evalValuesEqual? mapWithA mapWithA2)) "identical maps equality refuted")
      (assert (not (ev/evalValuesEqual? mapWithA mapWithB)) "valMap inequality for different keys")
      (refute (ev/evalValuesEqual? mapWithA mapWithB) "different keys equality refuted")
      (assert (not (ev/evalValuesEqual? mapWithA (ev/valInt 1))) "valMap inequality against valInt")
      (refute (ev/evalValuesEqual? mapWithA (ev/valInt 1)) "valMap vs valInt equality refuted")
      (let [(ltRes (ev/evalBuiltinComparison "<" emptyMap (ev/valInt 1)))]
        (assert (mt ltRes ((ev/valError msg) (= msg "ERR_TYPE_MISMATCH_COMPARISON")) (_ false)) "valMap comparison fails type mismatch"))
      (let [(callRes (ev/applyClosure! emptyMap (list)))]
        (assert (mt callRes ((ev/valError msg) (= msg "ERR_NOT_A_FUNCTION")) (_ false)) "valMap application fails not a function"))
      (assert (= (ev/formatVal emptyMap) "{...}") "valMap format string")
      (refute (!= (ev/formatVal emptyMap) "{...}") "valMap format string refuted")
      true))

fn ! runTests -> Bool
  (do (assert (testEvalLiterals!) "test-eval-literals must pass") (assert (testEvalArithmetic!) "test-eval-arithmetic must pass") (assert (testEvalComparison!) "test-eval-comparison must pass") (assert (testEvalLogic!) "test-eval-logic must pass") (assert (testEvalStrings!) "test-eval-strings must pass") (assert (testEvalEnvBinding) "test-eval-env-binding must pass") (assert (testEvalAssert!) "test-eval-assert must pass") (assert (testEvalIfBranch!) "test-eval-if-branch must pass") (assert (testZeroTruthiness) "test-zero-truthiness must pass") (assert (testValMapSemantics!) "test-val-map-semantics must pass") true)
