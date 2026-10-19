(module asl-checker/unifyTest :x [testUnify runTests RunTests] :i [(types :a ty) (unify :a u)])

fn intType -> ty/Type
  (ty/tyCon "Int64" (list) (none) (none))

fn int32Type -> ty/Type
  (ty/tyCon "Int32" (list) (none) (none))

fn mapType k: ty/Type v: ty/Type -> ty/Type
  (ty/tyCon "Map" (list k v) (none) (none))

fn preludeMapType k: ty/Type v: ty/Type -> ty/Type
  (ty/tyCon "PreludeMap" (list k v) (none) (none))

; (:m :ref CHKFIX :do "Map/PreludeMap and Int32/Int64 unify as a narrow, named equivalence (prelude.asl's own Map functions and int32ToInt64/int64ToInt32 construct through the other representation), never as a blanket numeric-mismatch suppression: testFloat64StillMismatches guards that Int64/Float64, a genuinely different representation, still errs the same as before")
fn testMapPreludeMapAlias s0: (Map Int64 ty/Type) -> Bool
  (mt (u/unify (mapType (intType) (intType)) (preludeMapType (intType) (intType)) s0 "prelude") ((u/uOk _) true) ((u/uErr _ _) false))

fn testInt32Int64Alias s0: (Map Int64 ty/Type) -> Bool
  (and (mt (u/unify (intType) (int32Type) s0 "prelude") ((u/uOk _) true) ((u/uErr _ _) false))
       (mt (u/unify (int32Type) (intType) s0 "prelude") ((u/uOk _) true) ((u/uErr _ _) false)))

; (:m :ref HLFIXB :do "representationAlias? must be scoped to the prelude's own int32ToInt64/int64ToInt32 and Map/PreludeMap bodies, not every module: a user module unifying Int32 against Int64, or Map against PreludeMap, still gets ERR_TYPE_MISMATCH")
fn testAliasOnlyInPrelude s0: (Map Int64 ty/Type) -> Bool
  (and (mt (u/unify (intType) (int32Type) s0 "userMod") ((u/uOk _) false) ((u/uErr _ _) true))
       (mt (u/unify (mapType (intType) (intType)) (preludeMapType (intType) (intType)) s0 "userMod") ((u/uOk _) false) ((u/uErr _ _) true)))

fn testFloat64StillMismatches s0: (Map Int64 ty/Type) -> Bool
  (and (mt (u/unify (intType) (ty/tyCon "Float64" (list) (none) (none)) s0 "prelude") ((u/uOk _) false) ((u/uErr _ _) true))
       (mt (u/unify (mapType (intType) (intType)) (ty/tyCon "String" (list) (none) (none)) s0 "prelude") ((u/uOk _) false) ((u/uErr _ _) true)))

fn checkUnifyEqual t1: ty/Type t2: ty/Type s0: (Map Int64 ty/Type) v: ty/Type expected: ty/Type -> Bool
  (mt (u/unify t1 t2 s0 "testMod") ((u/uErr _ _) false) ((u/uOk s1) (u/typeEqual? (u/applySubst s1 v) expected)))

fn testBind s0: (Map Int64 ty/Type) -> Bool
  (let [(v1 (ty/tyVar 1 "any")) (cI64 (intType))] (checkUnifyEqual v1 cI64 s0 v1 cI64))

fn testOccurs s0: (Map Int64 ty/Type) -> Bool
  (let [(v1 (ty/tyVar 1 "any")) (listV1 (ty/tyCon "List" (list v1) (none) (none)))] (refute (mt (u/unify v1 listV1 s0 "testMod") ((u/uOk _) true) ((u/uErr _ _) false)) "Metavariable must not unify with containing list") (mt (u/unify v1 listV1 s0 "testMod") ((u/uOk _) false) ((u/uErr _ _) true)))

fn testNarrowAnyNum -> Bool
  (let [(res (u/kindNarrow "any" "num"))] (do (assert (mt res ((none) false) ((some k) (= k "num"))) "narrow any num is num") (refute (none? res) "narrow any num is not none") true))

fn testNarrowNumInt -> Bool
  (let [(res (u/kindNarrow "num" "int"))] (do (assert (mt res ((none) false) ((some k) (= k "int"))) "narrow num int is int") (refute (none? res) "narrow num int is not none") true))

fn testNumMismatchTrue s0: (Map Int64 ty/Type) -> Bool
  (let [(cI64 (intType)) (c-f64 (ty/tyCon "Float64" (list) (none) (none)))] (mt (u/unify cI64 c-f64 s0 "testMod") ((u/uOk _) false) ((u/uErr _ num) num)))

fn testNumMismatchFalse s0: (Map Int64 ty/Type) -> Bool
  (let [(cI64 (intType)) (cStr (ty/tyCon "String" (list) (none) (none)))] (mt (u/unify cI64 cStr s0 "testMod") ((u/uOk _) false) ((u/uErr _ num) (not num))))

fn testHof s0: (Map Int64 ty/Type) -> Bool
  (let [(v1 (ty/tyVar 1 "any")) (cI64 (intType)) (fnV1 (ty/tyFun (list v1) v1)) (fnI64 (ty/tyFun (list cI64) cI64))] (checkUnifyEqual fnV1 fnI64 s0 v1 cI64))

fn testRejectFn s0: (Map Int64 ty/Type) -> Bool
  (let [(vNum (ty/tyVar 3 "num")) (cI64 (intType)) (fnI64 (ty/tyFun (list cI64) cI64))] (refute (mt (u/unify vNum fnI64 s0 "testMod") ((u/uOk _) true) ((u/uErr _ _) false)) "Numeric metavar must not unify with function") (mt (u/unify vNum fnI64 s0 "testMod") ((u/uOk _) false) ((u/uErr _ _) true)))

fn testUnify -> Bool
  (let [(s0 (mapEmpty))] (assert (testBind s0) "fail bind metavar") (assert (testOccurs s0) "fail occurs check") (assert (testNarrowAnyNum) "fail kind narrow any num") (assert (testNarrowNumInt) "fail kind narrow num int") (assert (testNumMismatchTrue s0) "fail numeric mismatch flag true") (assert (testNumMismatchFalse s0) "fail numeric mismatch flag false") (assert (testHof s0) "fail hof unification") (assert (testRejectFn s0) "fail reject fn for num metavar") (assert (testMapPreludeMapAlias s0) "Map and PreludeMap must unify") (assert (testInt32Int64Alias s0) "Int32 and Int64 must unify either direction") (assert (testAliasOnlyInPrelude s0) "representationAlias? must not hold outside the prelude module") (assert (testFloat64StillMismatches s0) "Float64 is not aliased to Int64, nor Map to a wholly different type") (refute (u/typeEqual? (intType) (ty/tyCon "String" (list) (none) (none))) "Int64 must not equal String") (refute (some? (u/kindNarrow "int" "unknown")) "Unknown kind narrowing must fail") true)

fn runTests -> Bool
  (do (assert (testUnify) "test-unify must pass") true)

fn RunTests -> Bool
  (runTests)
