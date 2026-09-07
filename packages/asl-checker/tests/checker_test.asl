(module asl-checker/checker-test
  :d "Comprehensive falsifiable test suite for Hindley-Milner type inference and checker."
  :x [check-source
      check-file!
      test-corpus-smoke
      run-tests]
  :i [(types :a ty) (resolve :a r) (check :a c) (unify :a u)])

(df check-source [(src String) (deps (Map String r/ModuleSummary)) (path String)] -> (List ty/Diagnostic)
  :d "Check source string"
  (c/check-source src deps path))

(df ! check-file! [(path String) (roots (List String))] -> (Result (List ty/Diagnostic) IoError)
  :d "Check file on disk"
  (c/check-file! path roots))

(df test-corpus-smoke [] -> String
  :d "Smoke test"
  (let [(res (c/check-source "(module m :d \"d\" :x [f]) (df f [] -> Int64 42)" (map-empty) "m.asl"))]
    (if (list-empty? res)
      "ok"
      "fail smoke")))

(df test-unification [] -> Bool
  :d "Verifies Hindley-Milner type unification and metavariable substitution."
  (let [(i64 (ty/ty-con "Int64" (list) (none) (none)))
        (str-ty (ty/ty-con "String" (list) (none) (none)))
        (v1 (ty/ty-var 1 "any"))
        (fn1 (ty/ty-fun (list v1) v1))
        (fn2 (ty/ty-fun (list i64) i64))]
    (assert (u/type-equal? i64 i64) "Concrete type equality")
    (assert (not (u/type-equal? i64 str-ty)) "Distinct primitive inequality")
    (mt (u/unify v1 i64 (map-empty))
      ((u/u-ok s1)
       (assert (u/type-equal? (u/apply-subst s1 v1) i64) "Metavariable substituted to concrete type"))
      ((u/u-err _ _)
       (assert false "Metavariable unification should succeed")))
    (mt (u/unify fn1 fn2 (map-empty))
      ((u/u-ok s2)
       (assert (u/type-equal? (u/apply-subst s2 v1) i64) "HOF parameter type inferred"))
      ((u/u-err _ _)
       (assert false "HOF unification should succeed")))
    (mt (u/unify i64 str-ty (map-empty))
      ((u/u-ok _)
       (assert false "Unifying Int64 and String must fail"))
      ((u/u-err msg _)
       (assert (string-contains? msg "expected") "Type error message contains expected")))
    true))

(df test-occurs [] -> Bool
  :d "Verifies occurs-check rejection of recursive and self-referential types."
  (let [(v1 (ty/ty-var 1 "any"))
        (i64 (ty/ty-con "Int64" (list) (none) (none)))
        (list-v1 (ty/ty-con "List" (list v1) (none) (none)))
        (fn-v1 (ty/ty-fun (list v1) i64))]
    (assert (u/occurs-in? 1 list-v1 (map-empty)) "Metavariable occurs in constructed list")
    (assert (not (u/occurs-in? 1 i64 (map-empty))) "Metavariable does not occur in primitive Int64")
    (mt (u/unify v1 list-v1 (map-empty))
      ((u/u-ok _)
       (assert false "Occurs check must reject v1 = List[v1]"))
      ((u/u-err msg _)
       (assert (string-contains? msg "occurs check") "Error message reports occurs check failure")))
    (mt (u/unify v1 fn-v1 (map-empty))
      ((u/u-ok _)
       (assert false "Occurs check must reject v1 = (fn [v1] -> Int64)"))
      ((u/u-err msg _)
       (assert (string-contains? msg "occurs check") "Function occurs check failure reported")))
    true))

(df test-check-source [] -> Bool
  :d "Verifies full pipeline source checking on well-typed and ill-typed ASL modules."
  (let [(well-typed "(module m :d \"d\" :x [id f]) (df id [(x Int64)] -> Int64 x) (df f [] -> Int64 (id 42))")
        (d-ok (c/check-source well-typed (map-empty) "m.asl"))
        (ill-typed "(module m :d \"d\" :x [helper g]) (df helper [] -> String \"mismatch\") (df g [] -> Int64 (helper))")
        (d-err (c/check-source ill-typed (map-empty) "m.asl"))
        (lit-err "(module m :d \"d\" :x [f]) (df f [] -> Int64 \"bad\")")
        (d-lit (c/check-source lit-err (map-empty) "m.asl"))]
    (assert (list-empty? d-ok) "Well-typed source produces zero diagnostics")
    (assert (not (list-empty? d-err)) "Call return mismatch produces diagnostics")
    (assert (> (list-length d-err) 0) "Diagnostic count >= 1 for mismatch")
    (assert (not (list-empty? d-lit)) "Literal type mismatch produces diagnostics")
    true))

(df run-tests [] -> Bool
  :d "Verifies Hindley-Milner type inference, unification, occurs-check, and source checking."
  (assert (= (test-corpus-smoke) "ok") "Smoke test passes")
  (assert (test-unification) "HM unification tests pass")
  (assert (test-occurs) "Occurs-check tests pass")
  (assert (test-check-source) "Source checking tests pass")
  true)
