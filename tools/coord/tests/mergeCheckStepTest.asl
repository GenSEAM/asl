(module asl-tools/coord/tests/mergeCheckStepTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd)])

fn runTests -> Bool
  (let [(a (assert (= (cd/mergeCheckStepS 1200) 900) "the adopted 1200 s budget gives one step 900 s"))
        (b (assert (> (cd/mergeCheckStepS 1200) 320) "a step outlasts the 320 s measured for the uncached consistency audit"))
        (c (assert (= (cd/mergeCheckStepS 400) 300) "a small budget keeps the 300 s floor"))]
    true)
