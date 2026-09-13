(module asl-codegen/exprTest
  :d "Unit tests for asl-codegen/expr"
  :x [testExpr runTests]
  :i [(expr :a ex) (reader :a rd)])

(df testExpr [] -> Bool
  :d "Verifies expression and special forms emission."
  (let [(aliases (map-empty))
        (e1 (ex/emitExpr (rd/sexprAtom "123") aliases))
        (e2 (ex/emitExpr (rd/sexprAtom "\"hello\"") aliases))
        (e3 (ex/emitExpr (rd/sexprList (list (rd/sexprAtom "+") (rd/sexprAtom "1") (rd/sexprAtom "2"))) aliases))
        (e4 (ex/emitExpr (rd/sexprList (list (rd/sexprAtom "if") (rd/sexprAtom "true") (rd/sexprAtom "1") (rd/sexprAtom "0"))) aliases))
        (bPair (rd/sexprVect (list (rd/sexprAtom "x") (rd/sexprAtom "10"))))
        (bindings (rd/sexprVect (list bPair)))
        (e5 (ex/emitExpr (rd/sexprList (list (rd/sexprAtom "let") bindings (rd/sexprAtom "x"))) aliases))
        (e6 (ex/emitExpr (rd/sexprList (list (rd/sexprAtom "try") (rd/sexprAtom "res"))) aliases))
        (e7 (ex/emitExpr (rd/sexprList (list (rd/sexprAtom ".-first") (rd/sexprAtom "p"))) aliases))]
    (assert (= e1 "123") "e1 atom")
    (assert (= e2 "\"hello\".to_string()") "e2 string")
    (assert (= e3 "rt::add(1, 2)") "e3 add")
    (assert (= e4 "if true { 1 } else { 0 }") "e4 if")
    (assert (= e5 "{ let x = 10; x }") "e5 let")
    (assert (= e6 "(res)?") "e6 try")
    (assert (= e7 "p.clone().0.clone()") "e7 .-first")
    true))

(df runTests [] -> Bool
  :d "Runs expr test suite"
  (do
    (assert (testExpr) "test-expr must pass")
    true))
