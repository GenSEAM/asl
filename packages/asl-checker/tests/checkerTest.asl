(module asl-checker/checkerTest
  :d "Comprehensive falsifiable test suite for Hindley-Milner type inference and checker."
  :x [checkSource
      checkFile!
      testCorpusSmoke
      runTests
      RunTests]
  :i [(types :a ty) (resolve :a r) (check :a c) (unify :a u)])

(df checkSource [(src String) (deps (Map String r/ModuleSummary)) (path String)] -> (List ty/Diagnostic)
  :d "Runs type checking on source string and returns diagnostic list."
  (c/checkSource src deps path))

(df ! checkFile! [(path String) (roots (List String))] -> (Result (List ty/Diagnostic) IoError)
  :d "Runs type checking on a file path using search roots and returns diagnostic list."
  (c/checkFile! path roots))

(df testCorpusSmoke [] -> Bool
  :d "Smoke test verifying type checker on minimal well-typed and ill-typed module sources."
  (let [(dOk (c/checkSource "(module m :d \"d\" :x [f]) (df f [] -> Int64 :d \"doc\" 42)" (map-empty) "m.asl"))
        (d-bad (c/checkSource "(module m :d \"d\" :x [f]) (df f [] -> Int64 :d \"doc\" \"fail\")" (map-empty) "m.asl"))]
    (assert (list-empty? dOk) "Smoke test well-typed produces zero diagnostics")
    (refute (not (list-empty? dOk)) "Smoke test well-typed must not produce diagnostics")
    (refute (list-empty? d-bad) "Smoke test ill-typed produces diagnostics")
    (assert (not (list-empty? d-bad)) "Smoke test ill-typed must produce non-empty diagnostics")
    true))

(df testUnification [] -> Bool
  :d "Verifies Hindley-Milner type unification and metavariable substitution."
  (let [(i64 (ty/tyCon "Int64" (list) (none) (none)))
        (strTy (ty/tyCon "String" (list) (none) (none)))
        (v1 (ty/tyVar 1 "any"))
        (fn1 (ty/tyFun (list v1) v1))
        (fn2 (ty/tyFun (list i64) i64))]
    (assert (u/typeEqual? i64 i64) "Concrete type equality")
    (refute (u/typeEqual? i64 strTy) "Distinct primitive inequality")
    (refute (not (u/typeEqual? i64 i64)) "Identical concrete types must not be unequal")
    (mt (u/unify v1 i64 (map-empty))
      ((u/uOk s1)
       (assert (u/typeEqual? (u/applySubst s1 v1) i64) "Metavariable substituted to concrete type")
       (refute (u/typeEqual? (u/applySubst s1 v1) strTy) "Substituted variable must not equal distinct type"))
      ((u/uErr _ _)
       (assert false "Metavariable unification should succeed")))
    (mt (u/unify fn1 fn2 (map-empty))
      ((u/uOk s2)
       (assert (u/typeEqual? (u/applySubst s2 v1) i64) "HOF parameter type inferred")
       (refute (u/typeEqual? (u/applySubst s2 v1) strTy) "Inferred HOF parameter type must not equal String"))
      ((u/uErr _ _)
       (assert false "HOF unification should succeed")))
    (mt (u/unify i64 strTy (map-empty))
      ((u/uOk _)
       (assert false "Unifying Int64 and String must fail"))
      ((u/uErr msg _)
       (assert (string-contains? msg "expected") "Type error message contains expected")
       (refute (string-empty? msg) "Type error message must not be empty")))
    true))

(df testOccurs [] -> Bool
  :d "Verifies occurs-check rejection of recursive and self-referential types."
  (let [(v1 (ty/tyVar 1 "any"))
        (i64 (ty/tyCon "Int64" (list) (none) (none)))
        (listV1 (ty/tyCon "List" (list v1) (none) (none)))
        (fnV1 (ty/tyFun (list v1) i64))]
    (assert (u/occursIn? 1 listV1 (map-empty)) "Metavariable occurs in constructed list")
    (refute (not (u/occursIn? 1 listV1 (map-empty))) "Metavariable must occur in recursive list type")
    (refute (u/occursIn? 1 i64 (map-empty)) "Metavariable does not occur in primitive Int64")
    (assert (not (u/occursIn? 1 i64 (map-empty))) "Metavariable must not occur in non-recursive primitive")
    (mt (u/unify v1 listV1 (map-empty))
      ((u/uOk _)
       (assert false "Occurs check must reject v1 = List[v1]"))
      ((u/uErr msg _)
       (assert (string-contains? msg "occurs check") "Error message reports occurs check failure")
       (refute (string-empty? msg) "Occurs check error message must not be empty")))
    (mt (u/unify v1 fnV1 (map-empty))
      ((u/uOk _)
       (assert false "Occurs check must reject v1 = (fn [v1] -> Int64)"))
      ((u/uErr msg _)
       (assert (string-contains? msg "occurs check") "Function occurs check failure reported")
       (refute (string-empty? msg) "Function occurs check error message must not be empty")))
    true))

(df testCheckSource [] -> Bool
  :d "Verifies full pipeline source checking on well-typed and ill-typed ASL modules."
  (let [(wellTyped "(module m :d \"d\" :x [id f]) (df id [(x Int64)] -> Int64 :d \"id\" x) (df f [] -> Int64 :d \"f\" (id 42))")
        (dOk (c/checkSource wellTyped (map-empty) "m.asl"))
        (illTyped "(module m :d \"d\" :x [helper g]) (df helper [] -> String :d \"h\" \"mismatch\") (df g [] -> Int64 :d \"g\" (helper))")
        (dErr (c/checkSource illTyped (map-empty) "m.asl"))
        (litErr "(module m :d \"d\" :x [f]) (df f [] -> Int64 :d \"f\" \"bad\")")
        (dLit (c/checkSource litErr (map-empty) "m.asl"))
        (docErr (c/checkSource "(module m :d \"d\" :x [f]) (df f [] -> Int64 42)" (map-empty) "m.asl"))]
    (assert (list-empty? dOk) "Well-typed source produces zero diagnostics")
    (refute (not (list-empty? dOk)) "Well-typed source must not produce diagnostics")
    (refute (list-empty? dErr) "Call return mismatch produces diagnostics")
    (assert (> (list-length dErr) 0) "Diagnostic count >= 1 for mismatch")
    (refute (list-empty? dLit) "Literal type mismatch produces diagnostics")
    (assert (> (list-length dLit) 0) "Literal type mismatch diagnostic count >= 1")
    (refute (list-empty? docErr) "m.asl exported function without doc must produce diagnostics")
    (assert (> (list-length docErr) 0) "m.asl exported function without doc diagnostic count >= 1")
    true))

(df runTests [] -> Bool
  :d "Verifies Hindley-Milner type inference, unification, occurs-check, and source checking."
  (assert (testCorpusSmoke) "Smoke test passes")
  (refute (not (testCorpusSmoke)) "Smoke test must not fail")
  (assert (testUnification) "HM unification tests pass")
  (refute (not (testUnification)) "HM unification must not fail")
  (assert (testOccurs) "Occurs-check tests pass")
  (refute (not (testOccurs)) "Occurs-check must not fail")
  (assert (testCheckSource) "Source checking tests pass")
  (refute (not (testCheckSource)) "Source checking must not fail")
  true)

(df RunTests [] -> Bool
  :d "Executes all checker test suites under the test runner."
  (runTests))
