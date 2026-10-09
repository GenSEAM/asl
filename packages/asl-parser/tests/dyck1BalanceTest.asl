(module asl/packages/asl-parser/tests/dyck1BalanceTest
  :x [runTests RunTests testDyck1BalancePhysics testPureDyck1ParameterAndBindingConversion testBalanceDelimitersDyck1 testDualPolarityRefutations]
  :i [(asl-parser/reader :a rd)
      (asl-parser/balance :a bal)
      (asl-parser/astConverter :a cv)
      (asl-parser/ast :a a)])

fn testDyck1BalancePhysics -> Bool
  (let [(r1 (bal/checkDyck1Balance "()"))]
    (assert r1.balanced "empty unit parens are balanced")
    (refute (not r1.balanced) "empty unit parens refute unbalanced")
    (assert (= r1.openParens 0) "empty unit parens have 0 unclosed")
    (refute (!= r1.openParens 0) "empty unit parens refute non-zero unclosed"))
  (let [(r2 (bal/checkDyck1Balance "((a b) (c (d e)))"))]
    (assert r2.balanced "nested Dyck-1 tree is balanced")
    (refute (not r2.balanced) "nested Dyck-1 tree refutes unbalanced")
    (assert (= r2.openParens 0) "nested Dyck-1 tree has 0 unclosed")
    (refute (!= r2.openParens 0) "nested Dyck-1 tree refutes unclosed non-zero"))
  (let [(r3 (bal/checkDyck1Balance "(let ((x 1) (y 2)) (+ x y))"))]
    (assert r3.balanced "pure Dyck-1 let expression is balanced")
    (refute (not r3.balanced) "pure Dyck-1 let refutes unbalanced"))
  (let [(rStr (bal/checkDyck1Balance "(println \"(hello) ) (world\")"))]
    (assert rStr.balanced "parens inside strings are ignored")
    (refute (not rStr.balanced) "parens inside strings refute imbalance"))
  (let [(rEsc (bal/checkDyck1Balance "(println \"escaped \\\" (paren \\\" inside\")"))]
    (assert rEsc.balanced "escaped quotes inside strings are handled")
    (refute (not rEsc.balanced) "escaped quotes refute imbalance"))
  (let [(u1 (bal/checkDyck1Balance "((a b)"))]
    (assert (not u1.balanced) "unclosed open parens are detected as unbalanced")
    (refute u1.balanced "unclosed open parens refute balanced")
    (assert (= u1.openParens 1) "unclosed parens count is 1")
    (refute (!= u1.openParens 1) "unclosed parens count refutes mismatch"))
  (let [(u2 (bal/checkDyck1Balance "())"))]
    (assert (not u2.balanced) "early closing paren is detected as unbalanced")
    (refute u2.balanced "early closing paren refutes balanced")
    (assert (< u2.openParens 0) "early closing paren produces negative depth indicator")
    (refute (>= u2.openParens 0) "early closing paren refutes non-negative depth"))
  (let [(u3 (bal/checkDyck1Balance ")("))]
    (assert (not u3.balanced) "inverted parens )( are unbalanced")
    (refute u3.balanced "inverted parens refute balanced"))
  true

fn testPureDyck1ParameterAndBindingConversion -> Bool
  (let [(pairX (rd/makeList (list (rd/makeAtom "x") (rd/makeAtom "10"))))
        (pairY (rd/makeList (list (rd/makeAtom "y") (rd/makeAtom "20"))))
        (bindingsList (rd/makeList (list pairX pairY)))
        (bodyExpr (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "x") (rd/makeAtom "y"))))
        (letSexpr (rd/makeList (list (rd/makeAtom "let") bindingsList bodyExpr)))
        (astExpr (cv/liftExpr letSexpr))]
    (mt astExpr
      ((a/exprLet bindings body)
        (assert (= (listLength bindings) 2) "pure Dyck-1 let lifts exactly 2 bindings")
        (refute (!= (listLength bindings) 2) "pure Dyck-1 let refutes wrong binding count")
        (assert (= (listLength body) 1) "pure Dyck-1 let has 1 body expression")
        (refute (!= (listLength body) 1) "pure Dyck-1 let refutes wrong body count"))
      (_
        (assert false "liftExpr failed to parse pure Dyck-1 let")
        (refute true "liftExpr must not fail on pure Dyck-1 let"))))
  (let [(letAst (a/exprLet
                  (list (pair (a/patVar "alpha") (a/exprLit (a/litInt 42))))
                  (list (a/exprIdent "alpha"))))
        (loweredSexpr (cv/lowerExpr letAst))
        (items (rd/sexprToList loweredSexpr))]
    (assert (rd/isList? loweredSexpr) "lowerExpr emits pure sexprList for let")
    (refute (rd/isVect? loweredSexpr) "lowerExpr refutes sexprVect for let")
    (assert (>= (listLength items) 3) "lowered let has head bindings and body")
    (refute (< (listLength items) 3) "lowered let refutes insufficient items")
    (let [(bindingsNode (optionOr (listGet items 1) (rd/makeAtom "")))]
      (assert (rd/isList? bindingsNode) "lowered let bindings are pure sexprList")
      (refute (rd/isVect? bindingsNode) "lowered let bindings refute sexprVect")))
  (let [(fnSig (rd/makeList (list
                  (rd/makeAtom "fn")
                  (rd/makeAtom "compute")
                  (rd/makeList (list
                    (rd/makeList (list (rd/makeAtom "a") (rd/makeAtom "I64")))
                    (rd/makeList (list (rd/makeAtom "b") (rd/makeAtom "Str")))))
                  (rd/makeAtom "->")
                  (rd/makeAtom "Bool")
                  (rd/makeList (list (rd/makeAtom "=") (rd/makeAtom "a") (rd/makeAtom "1"))))))
        (topRes (cv/sexprToTopForm fnSig))]
    (assert (ok? topRes) "sexprToTopForm accepts pure Dyck-1 parameter list")
    (refute (err? topRes) "sexprToTopForm refutes err on pure Dyck-1 params")
    (mt topRes
      ((ok tf)
        (mt tf
          ((a/topDefun d)
            (assert (= d.name "compute") "defun name matches compute")
            (refute (!= d.name "compute") "defun name refutes divergence")
            (assert (= (listLength d.params) 2) "defun has 2 params")
            (refute (!= (listLength d.params) 2) "defun refutes wrong param count"))
          (_
            (assert false "expected topDefun")
            (refute true "expected topDefun"))))
      ((err _)
        (assert false "topForm error")
        (refute true "topForm error"))))
  true

fn testBalanceDelimitersDyck1 -> Bool
  (let [(s1 "((a b) (c d")
        (fixed1 (bal/balanceDelimiters s1))]
    (assert (= fixed1 "((a b) (c d))") "balanceDelimiters closes 2 missing parens")
    (refute (!= fixed1 "((a b) (c d))") "balanceDelimiters refutes incorrect closure")
    (assert (bal/isDelimiterBalanced? fixed1) "fixed string is balanced")
    (refute (not (bal/isDelimiterBalanced? fixed1)) "fixed string refutes unbalanced"))
  (let [(s2 "(fn test x: I64 -> Bool (= x 0")
        (fixed2 (bal/balanceDelimiters s2))]
    (assert (stringEndsWith? fixed2 ")") "fixed2 ends with closing paren")
    (refute (not (stringEndsWith? fixed2 ")")) "fixed2 refutes missing closing paren")
    (assert (bal/isDelimiterBalanced? fixed2) "fixed2 is balanced")
    (refute (not (bal/isDelimiterBalanced? fixed2)) "fixed2 refutes imbalance"))
  true

fn testDualPolarityRefutations -> Bool
  (let [(mismatched "[ ( ) }")
        (res (bal/checkDelimiterBalance mismatched))]
    (assert (not res.balanced) "mismatched bracket brace is unbalanced")
    (refute res.balanced "mismatched bracket brace refutes balanced"))
  (let [(emptyStr "")
        (resEmpty (bal/checkDyck1Balance emptyStr))]
    (assert resEmpty.balanced "empty string has 0 depth and is balanced")
    (refute (not resEmpty.balanced) "empty string refutes unbalanced"))
  (let [(deep "(((((((((())))))))))")
        (resDeep (bal/checkDyck1Balance deep))]
    (assert resDeep.balanced "deeply nested 10-level parens are balanced")
    (refute (not resDeep.balanced) "deeply nested parens refute unbalanced"))
  true

fn runTests -> Bool
  (do
    (assert (testDyck1BalancePhysics) "testDyck1BalancePhysics passed")
    (assert (testPureDyck1ParameterAndBindingConversion) "testPureDyck1ParameterAndBindingConversion passed")
    (assert (testBalanceDelimitersDyck1) "testBalanceDelimitersDyck1 passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
