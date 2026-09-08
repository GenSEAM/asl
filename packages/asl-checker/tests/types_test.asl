(module asl-checker/types-test
  :d "Unit tests for asl-checker/types"
  :x [test-types run-tests]
  :i [(types :a ty)])

(df check-bounds [(res (Option (Pair Int64 Int64)))] -> Bool
  (mt res
    ((none) false)
    ((some b) (and (= (.-first b) -2147483648) (= (.-second b) 2147483647)))))

(df check-sig-plus [(res (Option (Pair (List String) (Pair Bool String))))] -> Bool
  (mt res
    ((none) false)
    ((some sig)
     (let [(args (.-first sig))
           (variadic (.-first (.-second sig)))
           (ret (.-second (.-second sig)))]
       (and (not variadic) (and (= ret "N") (= (list-length args) 2)))))))

(df check-sig-str [(res (Option (Pair (List String) (Pair Bool String))))] -> Bool
  (mt res
    ((none) false)
    ((some sig)
     (let [(variadic (.-first (.-second sig)))]
       variadic))))

(df test-types [] -> Bool
  :d "Unit tests for types"
  (let [(t1 (ty/parse-type-str "Int" (list)))
        (t2 (ty/parse-type-str "(List Int)" (list)))
        (t3 (ty/parse-type-str "(fn [Int64] -> Bool)" (list)))
        (t4 (ty/parse-type-str "(Result A String)" (list "A")))]
    (assert (= (ty/show-type t1) "Int64") "t1 alias")
    (assert (= (ty/show-type t2) "(List Int64)") "t2 list")
    (assert (= (ty/show-type t3) "(fn [Int64] -> Bool)") "t3 fn")
    (assert (ty/unordered-type? "Float64") "unordered float")
    (assert (ty/unordered-type? "IoError") "unordered io")
    (assert (not (ty/unordered-type? "Int64")) "ordered int")
    (assert (check-bounds (ty/int-range-bounds "Int32")) "int32 bounds")
    (assert (= (ty/prelude-union-cases "some") (some "Option")) "some union")
    (assert (= (ty/prelude-union-cases "not-found") (some "IoError")) "not-found union")
    (assert (check-sig-plus (ty/builtin-sig "+")) "builtin + sig")
    (assert (check-sig-str (ty/builtin-sig "str")) "builtin str sig")
    (assert (= (ty/show-type (ty/ty-var 1 "any")) "_") "show var any")
    (assert (= (ty/show-type (ty/ty-var 1 "num")) "a number") "show var num")
    (assert (= (ty/show-type (ty/ty-var 1 "int")) "an integer") "show var int")
    true))

(df run-tests [] -> Bool
  :d "Runs types test suite"
  (do
    (assert (test-types) "test-types must pass")
    true))
