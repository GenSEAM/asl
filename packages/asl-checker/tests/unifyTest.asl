(module asl-checker/unifyTest
  :d "Unit tests for asl-checker/unify"
  :x [testUnify runTests]
  :i [(types :a ty) (unify :a u)])

(df intType [] -> ty/Type
  (ty/tyCon "Int64" (list) (none) (none)))

(df checkUnifyEqual [(t1 ty/Type) (t2 ty/Type) (s0 (Map Int64 ty/Type)) (v ty/Type) (expected ty/Type)] -> Bool
  (mt (u/unify t1 t2 s0)
    ((u/uErr _ _) false)
    ((u/uOk s1) (u/typeEqual? (u/applySubst s1 v) expected))))

(df testBind [(s0 (Map Int64 ty/Type))] -> Bool
  (let [(v1 (ty/tyVar 1 "any"))
        (cI64 (intType))]
    (checkUnifyEqual v1 cI64 s0 v1 cI64)))

(df testOccurs [(s0 (Map Int64 ty/Type))] -> Bool
  (let [(v1 (ty/tyVar 1 "any"))
        (listV1 (ty/tyCon "List" (list v1) (none) (none)))]
    (refute (mt (u/unify v1 listV1 s0) ((u/uOk _) true) ((u/uErr _ _) false)) "Metavariable must not unify with containing list")
    (mt (u/unify v1 listV1 s0)
      ((u/uOk _) false)
      ((u/uErr _ _) true))))

(df testNarrowAnyNum [] -> Bool
  (let [(res (u/kindNarrow "any" "num"))]
    (do
      (assert (mt res ((none) false) ((some k) (= k "num"))) "narrow any num is num")
      (refute (option-none? res) "narrow any num is not none")
      true)))

(df testNarrowNumInt [] -> Bool
  (let [(res (u/kindNarrow "num" "int"))]
    (do
      (assert (mt res ((none) false) ((some k) (= k "int"))) "narrow num int is int")
      (refute (option-none? res) "narrow num int is not none")
      true)))

(df testNumMismatchTrue [(s0 (Map Int64 ty/Type))] -> Bool
  (let [(cI64 (intType))
        (c-f64 (ty/tyCon "Float64" (list) (none) (none)))]
    (mt (u/unify cI64 c-f64 s0)
      ((u/uOk _) false)
      ((u/uErr _ num) num))))

(df testNumMismatchFalse [(s0 (Map Int64 ty/Type))] -> Bool
  (let [(cI64 (intType))
        (cStr (ty/tyCon "String" (list) (none) (none)))]
    (mt (u/unify cI64 cStr s0)
      ((u/uOk _) false)
      ((u/uErr _ num) (not num)))))

(df testHof [(s0 (Map Int64 ty/Type))] -> Bool
  (let [(v1 (ty/tyVar 1 "any"))
        (cI64 (intType))
        (fnV1 (ty/tyFun (list v1) v1))
        (fnI64 (ty/tyFun (list cI64) cI64))]
    (checkUnifyEqual fnV1 fnI64 s0 v1 cI64)))

(df testRejectFn [(s0 (Map Int64 ty/Type))] -> Bool
  (let [(vNum (ty/tyVar 3 "num"))
        (cI64 (intType))
        (fnI64 (ty/tyFun (list cI64) cI64))]
    (refute (mt (u/unify vNum fnI64 s0) ((u/uOk _) true) ((u/uErr _ _) false)) "Numeric metavar must not unify with function")
    (mt (u/unify vNum fnI64 s0)
      ((u/uOk _) false)
      ((u/uErr _ _) true))))

(df testUnify [] -> Bool
  :d "Unit tests for unify"
  (let [(s0 (map-empty))]
    (assert (testBind s0) "fail bind metavar")
    (assert (testOccurs s0) "fail occurs check")
    (assert (testNarrowAnyNum) "fail kind narrow any num")
    (assert (testNarrowNumInt) "fail kind narrow num int")
    (assert (testNumMismatchTrue s0) "fail numeric mismatch flag true")
    (assert (testNumMismatchFalse s0) "fail numeric mismatch flag false")
    (assert (testHof s0) "fail hof unification")
    (assert (testRejectFn s0) "fail reject fn for num metavar")
    (refute (u/typeEqual? (intType) (ty/tyCon "String" (list) (none) (none))) "Int64 must not equal String")
    (refute (is-some? (u/kindNarrow "int" "unknown")) "Unknown kind narrowing must fail")
    true))

(df runTests [] -> Bool
  :d "Runs unify test suite"
  (do
    (assert (testUnify) "test-unify must pass")
    true))
