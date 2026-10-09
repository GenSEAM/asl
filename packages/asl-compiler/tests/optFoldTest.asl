(module asl-compiler/tests/optFoldTest
  :x [RunTests runTests]
  :i [(asl-parser/reader :a rd) (optFold :a opt)])

fn testArithmeticConstantFolding -> Bool
  (let [(eAdd (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "12") (rd/makeAtom "30"))))
        (eSub (rd/makeList (list (rd/makeAtom "-") (rd/makeAtom "50") (rd/makeAtom "8"))))
        (eMul (rd/makeList (list (rd/makeAtom "*") (rd/makeAtom "6") (rd/makeAtom "7"))))
        (eDiv (rd/makeList (list (rd/makeAtom "/") (rd/makeAtom "100") (rd/makeAtom "4"))))
        (fAdd (opt/foldConstants eAdd))
        (fSub (opt/foldConstants eSub))
        (fMul (opt/foldConstants eMul))
        (fDiv (opt/foldConstants eDiv))]
    (do
      (assert (= (rd/renderSexpr fAdd) "42") "Fold (+ 12 30) -> 42")
      (assert (= (rd/renderSexpr fSub) "42") "Fold (- 50 8) -> 42")
      (assert (= (rd/renderSexpr fMul) "42") "Fold (* 6 7) -> 42")
      (assert (= (rd/renderSexpr fDiv) "25") "Fold (/ 100 4) -> 25")
      (refute (= (rd/renderSexpr fAdd) "(+ 12 30)") "Refutation: Constant arithmetic must not remain unfurled")
      true))

fn testAlgebraicIdentities -> Bool
  (let [(eAddZero (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "x") (rd/makeAtom "0"))))
        (eMulZero (rd/makeList (list (rd/makeAtom "*") (rd/makeAtom "y") (rd/makeAtom "0"))))
        (eMulOne (rd/makeList (list (rd/makeAtom "*") (rd/makeAtom "z") (rd/makeAtom "1"))))
        (eSubSelf (rd/makeList (list (rd/makeAtom "-") (rd/makeAtom "var") (rd/makeAtom "var"))))
        (eDivSelf (rd/makeList (list (rd/makeAtom "/") (rd/makeAtom "n") (rd/makeAtom "n"))))
        (fAddZero (opt/foldConstants eAddZero))
        (fMulZero (opt/foldConstants eMulZero))
        (fMulOne (opt/foldConstants eMulOne))
        (fSubSelf (opt/foldConstants eSubSelf))
        (fDivSelf (opt/foldConstants eDivSelf))]
    (do
      (assert (= (rd/renderSexpr fAddZero) "x") "Identity (+ x 0) -> x")
      (assert (= (rd/renderSexpr fMulZero) "0") "Identity (* y 0) -> 0")
      (assert (= (rd/renderSexpr fMulOne) "z") "Identity (* z 1) -> z")
      (assert (= (rd/renderSexpr fSubSelf) "0") "Identity (- var var) -> 0")
      (assert (= (rd/renderSexpr fDivSelf) "1") "Identity (/ n n) -> 1")
      (refute (= (rd/renderSexpr fSubSelf) "(- var var)") "Refutation: (- var var) must be reduced to 0")
      (refute (= (rd/renderSexpr fAddZero) "(+ x 0)") "Refutation: Identity must be reduced")
      true))

fn testBooleanLogicAndBranchPruning -> Bool
  (let [(eAndFalse (rd/makeList (list (rd/makeAtom "and") (rd/makeAtom "false") (rd/makeAtom "unknownSymbol"))))
        (eOrTrue (rd/makeList (list (rd/makeAtom "or") (rd/makeAtom "true") (rd/makeAtom "unknownSymbol"))))
        (eNotFalse (rd/makeList (list (rd/makeAtom "not") (rd/makeAtom "false"))))
        (eIfTrue (rd/makeList (list (rd/makeAtom "if") (rd/makeAtom "true") (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "1") (rd/makeAtom "2"))) (rd/makeAtom "99"))))
        (eIfFalse (rd/makeList (list (rd/makeAtom "if") (rd/makeAtom "false") (rd/makeAtom "10") (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "20") (rd/makeAtom "22"))))))
        (fAnd (opt/foldConstants eAndFalse))
        (fOr (opt/foldConstants eOrTrue))
        (fNot (opt/foldConstants eNotFalse))
        (fIfTrue (opt/foldConstants eIfTrue))
        (fIfFalse (opt/foldConstants eIfFalse))]
    (do
      (assert (= (rd/renderSexpr fAnd) "false") "Short-circuit (and false x) -> false")
      (assert (= (rd/renderSexpr fOr) "true") "Short-circuit (or true x) -> true")
      (assert (= (rd/renderSexpr fNot) "true") "Fold (not false) -> true")
      (assert (= (rd/renderSexpr fIfTrue) "3") "Prune (if true (+ 1 2) 99) -> 3")
      (assert (= (rd/renderSexpr fIfFalse) "42") "Prune (if false 10 (+ 20 22)) -> 42")
      (refute (= (rd/renderSexpr fAnd) "(and false unknownSymbol)") "Refutation: Short-circuit must eliminate unknown expression")
      (refute (= (rd/renderSexpr fIfTrue) "(if true 3 99)") "Refutation: Dead branch must be pruned completely")
      true))

fn testSimplifyBoolean -> Bool
  (let [(eDoubleNot (rd/makeList (list (rd/makeAtom "not") (rd/makeList (list (rd/makeAtom "not") (rd/makeAtom "x"))))))
        (eDeMorgan (rd/makeList (list (rd/makeAtom "not") (rd/makeList (list (rd/makeAtom "and") (rd/makeAtom "a") (rd/makeAtom "b"))))))
        (eIdempotentAnd (rd/makeList (list (rd/makeAtom "and") (rd/makeAtom "p") (rd/makeAtom "p"))))
        (eIdempotentOr (rd/makeList (list (rd/makeAtom "or") (rd/makeAtom "q") (rd/makeAtom "q"))))
        (eComplementAnd (rd/makeList (list (rd/makeAtom "and") (rd/makeAtom "k") (rd/makeList (list (rd/makeAtom "not") (rd/makeAtom "k"))))))
        (eComplementOr (rd/makeList (list (rd/makeAtom "or") (rd/makeAtom "m") (rd/makeList (list (rd/makeAtom "not") (rd/makeAtom "m"))))))
        (sDoubleNot (opt/simplifyBoolean eDoubleNot))
        (sDeMorgan (opt/simplifyBoolean eDeMorgan))
        (sIdemAnd (opt/simplifyBoolean eIdempotentAnd))
        (sIdemOr (opt/simplifyBoolean eIdempotentOr))
        (sCompAnd (opt/simplifyBoolean eComplementAnd))
        (sCompOr (opt/simplifyBoolean eComplementOr))]
    (do
      (assert (= (rd/renderSexpr sDoubleNot) "x") "Double negation elimination (not (not x)) -> x")
      (refute (= (rd/renderSexpr sDoubleNot) "(not (not x))") "Refute uneliminated double negation")
      (assert (= (rd/renderSexpr sDeMorgan) "(or (not a) (not b))") "De Morgan expansion (not (and a b)) -> (or (not a) (not b))")
      (assert (= (rd/renderSexpr sIdemAnd) "p") "Idempotent and (and p p) -> p")
      (assert (= (rd/renderSexpr sIdemOr) "q") "Idempotent or (or q q) -> q")
      (assert (= (rd/renderSexpr sCompAnd) "false") "Complement and (and k (not k)) -> false")
      (assert (= (rd/renderSexpr sCompOr) "true") "Complement or (or m (not m)) -> true")
      true))

fn testDceBlock -> Bool
  (let [(eDo (rd/makeList (list (rd/makeAtom "do") (rd/makeAtom "42") (rd/makeAtom "\"unused\"") (rd/makeList (list (rd/makeAtom "launch") (rd/makeAtom "job"))))))
        (eIfT (rd/makeList (list (rd/makeAtom "if") (rd/makeAtom "true") (rd/makeAtom "good") (rd/makeAtom "bad"))))
        (eLetEmpty (rd/makeList (list (rd/makeAtom "let") (rd/makeVect (list)) (rd/makeAtom "result"))))
        (dDo (opt/dceBlock eDo))
        (dIfT (opt/dceBlock eIfT))
        (dLet (opt/dceBlock eLetEmpty))]
    (do
      (assert (= (rd/renderSexpr dDo) "(launch job)") "DCE eliminates pure literals in do sequence")
      (refute (stringContains? (rd/renderSexpr dDo) "42") "Refute eliminated literal 42 remains")
      (assert (= (rd/renderSexpr dIfT) "good") "DCE resolves (if true good bad) -> good")
      (assert (= (rd/renderSexpr dLet) "result") "DCE eliminates empty let bindings")
      true))

fn testComptimeConstantFoldingAndLetBinding -> Bool
  (let [(eConst (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "10") (rd/makeAtom "20"))))
        (resConst (opt/evalComptimeConstant eConst))
        (bindX (rd/makeList (list (rd/makeAtom "x") (rd/makeAtom "15"))))
        (bindY (rd/makeList (list (rd/makeAtom "y") (rd/makeAtom "25"))))
        (binds (rd/makeVect (list bindX bindY)))
        (body (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "x") (rd/makeAtom "y"))))
        (letExpr (rd/makeList (list (rd/makeAtom "let") binds body)))
        (foldedLet (opt/foldLetBindings letExpr))]
    (assert (some? resConst) "pure addition evaluates at comptime")
    (assert (= (rd/renderSexpr (optionOr resConst (rd/makeAtom ""))) "30") "comptime fold evaluates to 30")
    (assert (= (rd/renderSexpr foldedLet) "40") "let constant propagation evaluates (+ x y) to 40")
    (refute (= (rd/renderSexpr foldedLet) "(+ x y)") "refutation: folded let must not remain unresolved")
    true)

fn runTests -> Bool
  (do
    (assert (testArithmeticConstantFolding) "testArithmeticConstantFolding")
    (assert (testAlgebraicIdentities) "testAlgebraicIdentities")
    (assert (testBooleanLogicAndBranchPruning) "testBooleanLogicAndBranchPruning")
    (assert (testSimplifyBoolean) "testSimplifyBoolean")
    (assert (testDceBlock) "testDceBlock")
    (assert (testComptimeConstantFoldingAndLetBinding) "testComptimeConstantFoldingAndLetBinding")
    true)

fn RunTests -> Bool
  (runTests)
