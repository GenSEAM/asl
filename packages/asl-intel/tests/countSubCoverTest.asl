(module asl-intel/tests/countSubCoverTest
  :x [runTests]
  :i [(asl-intel/text :a tx)])

fn runTests -> Bool
  (let [(r1 (tx/countSub "banana" "an"))
        (r2 (tx/countSub "abc" ""))]
    (let [(a1 (assert (= r1 2) "countSub banana an is 2"))
          (a2 (assert (= r2 4) "countSub abc empty is 4"))]
      true))
