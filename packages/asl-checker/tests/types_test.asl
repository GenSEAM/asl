(module asl-checker/typesTest
  :d "Unit tests for asl-checker/types"
  :x [testTypes runTests RunTests]
  :i [(types :a ty)])

(df checkBounds [(res (Option (Pair Int64 Int64)))] -> Bool
  (mt res
    ((none) false)
    ((some b) (and (= (.-first b) -2147483648) (= (.-second b) 2147483647)))))

(df checkSigPlus [(res (Option (Pair (List String) (Pair Bool String))))] -> Bool
  (mt res
    ((none) false)
    ((some sig)
     (let [(args (.-first sig))
           (variadic (.-first (.-second sig)))
           (ret (.-second (.-second sig)))]
       (and (not variadic) (and (= ret "N") (= (list-length args) 2)))))))

(df checkSigStr [(res (Option (Pair (List String) (Pair Bool String))))] -> Bool
  (mt res
    ((none) false)
    ((some sig)
     (let [(variadic (.-first (.-second sig)))]
       variadic))))

(df testTypes [] -> Bool
  :d "Unit tests for types"
  (let [(t1 (ty/parseTypeStr "Int" (list)))
        (t2 (ty/parseTypeStr "(List Int)" (list)))
        (t3 (ty/parseTypeStr "(fn [Int64] -> Bool)" (list)))
        (t4 (ty/parseTypeStr "(Result A String)" (list "A")))]
    (assert (= (ty/showType t1) "Int64") "t1 alias")
    (refute (= (ty/showType t1) "String") "t1 is not String")
    (assert (= (ty/showType t2) "(List Int64)") "t2 list")
    (assert (= (ty/showType t3) "(fn [Int64] -> Bool)") "t3 fn")
    (assert (ty/unorderedType? "Float64") "unordered float")
    (assert (ty/unorderedType? "IoError") "unordered io")
    (refute (ty/unorderedType? "Int64") "Int64 is not unordered")
    (refute (ty/unorderedType? "String") "String is not unordered")
    (assert (checkBounds (ty/intRangeBounds "Int32")) "int32 bounds")
    (refute (is-none? (ty/intRangeBounds "Int32")) "Int32 bounds must exist")
    (refute (is-some? (ty/intRangeBounds "UnknownInt")) "UnknownInt must not have bounds")
    (assert (= (ty/preludeUnionCases "some") (some "Option")) "some union")
    (assert (= (ty/preludeUnionCases "not-found") (some "IoError")) "not-found union")
    (assert (checkSigPlus (ty/builtinSig "+")) "builtin + sig")
    (assert (checkSigStr (ty/builtinSig "str")) "builtin str sig")
    (assert (= (ty/showType (ty/tyVar 1 "any")) "_") "show var any")
    (assert (= (ty/showType (ty/tyVar 1 "num")) "a number") "show var num")
    (assert (= (ty/showType (ty/tyVar 1 "int")) "an integer") "show var int")
    true))

(df runTests [] -> Bool
  :d "Runs types test suite"
  (do
    (assert (testTypes) "test-types must pass")
    true))

(df RunTests [] -> Bool
  :d "Test runner entry for types test suite"
  (runTests))
