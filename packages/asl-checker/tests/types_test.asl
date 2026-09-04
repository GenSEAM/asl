(module asl-checker/types-test
  :d "Unit tests for asl-checker/types"
  :x [test-types]
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

(df test-types [] -> String
  :d "Unit tests for types"
  (let [(t1 (ty/parse-type-str "Int" (list)))
        (t2 (ty/parse-type-str "(List Int)" (list)))
        (t3 (ty/parse-type-str "(fn [Int64] -> Bool)" (list)))
        (t4 (ty/parse-type-str "(Result A String)" (list "A")))]
    (cond
      ((not (= (ty/show-type t1) "Int64")) "fail t1 alias")
      ((not (= (ty/show-type t2) "(List Int64)")) "fail t2 list")
      ((not (= (ty/show-type t3) "(fn [Int64] -> Bool)")) "fail t3 fn")
      ((not (ty/unordered-type? "Float64")) "fail unordered float")
      ((not (ty/unordered-type? "IoError")) "fail unordered io")
      ((ty/unordered-type? "Int64") "fail ordered int")
      ((not (check-bounds (ty/int-range-bounds "Int32"))) "fail int32 bounds")
      ((not (= (ty/prelude-union-cases "some") (some "Option"))) "fail some union")
      ((not (= (ty/prelude-union-cases "not-found") (some "IoError"))) "fail not-found union")
      ((not (check-sig-plus (ty/builtin-sig "+"))) "fail builtin + sig")
      ((not (check-sig-str (ty/builtin-sig "str"))) "fail builtin str sig")
      ((not (= (ty/show-type (ty/ty-var 1 "any")) "_")) "fail show var any")
      ((not (= (ty/show-type (ty/ty-var 1 "num")) "a number")) "fail show var num")
      ((not (= (ty/show-type (ty/ty-var 1 "int")) "an integer")) "fail show var int")
      (:else "ok"))))
