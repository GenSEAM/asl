(module asl-checker/unify-test
  :d "Unit tests for asl-checker/unify"
  :x [test-unify]
  :i [(types :a ty) (unify :a u)])

(df int-type [] -> ty/Type
  (ty/ty-con "Int64" (list) (none) (none)))

(df assert-unify-equal [(t1 ty/Type) (t2 ty/Type) (s0 (Map Int64 ty/Type)) (v ty/Type) (expected ty/Type)] -> Bool
  (mt (u/unify t1 t2 s0)
    ((u/u-err _ _) false)
    ((u/u-ok s1) (u/type-equal? (u/apply-subst s1 v) expected))))

(df test-bind [(s0 (Map Int64 ty/Type))] -> Bool
  (let [(v1 (ty/ty-var 1 "any"))
        (c-i64 (int-type))]
    (assert-unify-equal v1 c-i64 s0 v1 c-i64)))

(df test-occurs [(s0 (Map Int64 ty/Type))] -> Bool
  (let [(v1 (ty/ty-var 1 "any"))
        (list-v1 (ty/ty-con "List" (list v1) (none) (none)))]
    (mt (u/unify v1 list-v1 s0)
      ((u/u-ok _) false)
      ((u/u-err _ _) true))))

(df test-narrow-any-num [] -> Bool
  (mt (u/kind-narrow "any" "num")
    ((none) false)
    ((some k) (= k "num"))))

(df test-narrow-num-int [] -> Bool
  (mt (u/kind-narrow "num" "int")
    ((none) false)
    ((some k) (= k "int"))))

(df test-num-mismatch-true [(s0 (Map Int64 ty/Type))] -> Bool
  (let [(c-i64 (int-type))
        (c-f64 (ty/ty-con "Float64" (list) (none) (none)))]
    (mt (u/unify c-i64 c-f64 s0)
      ((u/u-ok _) false)
      ((u/u-err _ num) num))))

(df test-num-mismatch-false [(s0 (Map Int64 ty/Type))] -> Bool
  (let [(c-i64 (int-type))
        (c-str (ty/ty-con "String" (list) (none) (none)))]
    (mt (u/unify c-i64 c-str s0)
      ((u/u-ok _) false)
      ((u/u-err _ num) (not num)))))

(df test-hof [(s0 (Map Int64 ty/Type))] -> Bool
  (let [(v1 (ty/ty-var 1 "any"))
        (c-i64 (int-type))
        (fn-v1 (ty/ty-fun (list v1) v1))
        (fn-i64 (ty/ty-fun (list c-i64) c-i64))]
    (assert-unify-equal fn-v1 fn-i64 s0 v1 c-i64)))

(df test-reject-fn [(s0 (Map Int64 ty/Type))] -> Bool
  (let [(v-num (ty/ty-var 3 "num"))
        (c-i64 (int-type))
        (fn-i64 (ty/ty-fun (list c-i64) c-i64))]
    (mt (u/unify v-num fn-i64 s0)
      ((u/u-ok _) false)
      ((u/u-err _ _) true))))

(df test-unify [] -> String
  :d "Unit tests for unify"
  (let [(s0 (map-empty))]
    (cond
      ((not (test-bind s0)) "fail bind metavar")
      ((not (test-occurs s0)) "fail occurs check")
      ((not (test-narrow-any-num)) "fail kind narrow any num")
      ((not (test-narrow-num-int)) "fail kind narrow num int")
      ((not (test-num-mismatch-true s0)) "fail numeric mismatch flag true")
      ((not (test-num-mismatch-false s0)) "fail numeric mismatch flag false")
      ((not (test-hof s0)) "fail hof unification")
      ((not (test-reject-fn s0)) "fail reject fn for num metavar")
      (:else "ok"))))
