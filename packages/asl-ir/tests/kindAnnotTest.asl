(module asl-ir/tests/kindAnnotTest
  :x [runTests]
  :i [(asl-ir/lowerLowLevel :a ll)
      (asl-target-llvm/lowLevelRoute :a hub)])

; (:m :do "the mirror table is compared with the hub's sized table, so no builtin name is copied by hand; the hub's sizedRt is empty at LL-ROUTE-HUB, so the test requires a non-empty mirror now and equality once the hub fills it")

fn mirrorNames -> (List String)
  (map (fn [(e (Pair String (Pair Int64 String)))] -> String (pairSecond (pairSecond e))) (ll/sizedBuiltins))

fn hubSizedNames -> (List String)
  (hub/routedBuiltins (list (hub/sizedFeature)))

fn kindPairs -> (List (Pair String Int64))
  (list (pair "U8" 1) (pair "I8" 2) (pair "U16" 3) (pair "I16" 4) (pair "U32" 5) (pair "I32" 6) (pair "U64" 7) (pair "I64" 0))

fn testKinds -> Bool
  (listAll? (fn [(p (Pair String Int64))] -> Bool (= (ll/kindOfAnnotation (pairFirst p)) (some (pairSecond p)))) (kindPairs))

fn testAliases -> Bool
  (and (= (ll/kindOfAnnotation "Int") (some 0)) (= (ll/kindOfAnnotation "Int64") (some 0)))

fn testInt32 -> Bool
  (= (ll/kindOfAnnotation "Int32") (some 6))

fn testFloat64 -> Bool
  (none? (ll/kindOfAnnotation "Float64"))

fn testSizedOps -> Bool
  (and (= (ll/sizedOpName "+" 1) (some "addU8"))
       (= (ll/sizedOpName ">>" 5) (some "shrU32")))

fn testNoSizedOp -> Bool
  (and (none? (ll/sizedOpName "foo" 1)) (none? (ll/sizedOpName "+" 99)))

fn testMirrorMatchesHub -> Bool
  (let [(hubNames (hubSizedNames))]
    (if (listEmpty? hubNames)
      (not (listEmpty? (mirrorNames)))
      (and (listAll? (fn [(n String)] -> Bool (listContains? (mirrorNames) n)) hubNames)
           (listAll? (fn [(n String)] -> Bool (listContains? hubNames n)) (mirrorNames)))))

fn runTests -> Bool
  (do
    (assert (testKinds) "every kind code round-trips")
    (assert (testAliases) "Int and Int64 are I64")
    (assert (testInt32) "Int32 maps to I32")
    (assert (testFloat64) "Float64 is none")
    (assert (testSizedOps) "(+ U8) and (>> U32) are routed")
    (assert (testNoSizedOp) "an op or kind with no sized builtin is none")
    (assert (testMirrorMatchesHub) "the mirror matches the hub's sized table")
    true)
