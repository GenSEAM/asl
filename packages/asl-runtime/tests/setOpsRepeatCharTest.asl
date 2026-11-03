(module asl-runtime/tests/setOpsRepeatCharTest :x [runTests] :i [(asl-runtime/collections :a c) (asl-runtime/strings :a st)])

; (:m :ref COVBATCH4 :do "setUnion, setIntersection, setDifference and repeatChar had no call path from any test")
fn sorted s: c/PureSet -> (List String)
  (listSort (c/setToList s))

fn runTests -> Bool
  (let [(s1 (c/setFromList (list "a" "b" "c")))
        (s2 (c/setFromList (list "b" "c" "d")))
        (none1 (c/setEmpty))]
    (do
      (assert (= (sorted (c/setUnion s1 s2)) (list "a" "b" "c" "d")) "union holds every element once")
      (assert (= (c/setSize (c/setUnion s1 s1)) 3) "union with itself changes nothing")
      (assert (= (sorted (c/setUnion s1 none1)) (list "a" "b" "c")) "union with empty")
      (assert (= (sorted (c/setUnion none1 s2)) (list "b" "c" "d")) "empty union a set")
      (assert (= (sorted (c/setIntersection s1 s2)) (list "b" "c")) "intersection keeps the shared elements")
      (assert (= (sorted (c/setIntersection s1 none1)) (list)) "intersection with empty is empty")
      (assert (= (sorted (c/setIntersection s1 (c/setFromList (list "x")))) (list)) "disjoint sets share nothing")
      (assert (= (sorted (c/setDifference s1 s2)) (list "a")) "difference removes the other's elements")
      (assert (= (sorted (c/setDifference s2 s1)) (list "d")) "difference is not symmetric")
      (assert (= (sorted (c/setDifference s1 s1)) (list)) "a set minus itself is empty")
      (assert (= (sorted (c/setDifference s1 none1)) (list "a" "b" "c")) "minus empty changes nothing")
      (assert (= (c/setSize (c/setFromList (list "a" "a" "b"))) 2) "duplicates collapse on creation")
      (assert (= (st/repeatChar "ab" 3 "") "ababab") "a repeated string")
      (assert (= (st/repeatChar "x" 2 ">") ">xx") "the accumulator is the prefix")
      (assert (= (st/repeatChar "x" 0 "k") "k") "count zero returns the accumulator")
      (assert (= (st/repeatChar "x" -3 "k") "k") "a negative count returns the accumulator")
      (assert (= (st/repeatChar "" 5 "") "") "repeating the empty string")
      true))
