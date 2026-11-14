(module asl-pack/tests/versionCompareCoverTest
  :x [runTests]
  :i [(pkgIndex :a ix)])

; (:m :ref VERSIONCOMPARE-COVER :do "versionCompare is exported from pkgIndex but had no suite: these three cases pin the lexicographic compare and the trailing-zero equality (1.0 = 1)")

fn testLess -> Bool
  (do (assert (= (ix/versionCompare (list 1 2) (list 1 3)) -1) "1.2 vs 1.3 must be -1") true)

fn testGreater -> Bool
  (do (assert (= (ix/versionCompare (list 2) (list 1 9)) 1) "2 vs 1.9 must be 1") true)

fn testTrailingZero -> Bool
  (do (assert (= (ix/versionCompare (list 1 0) (list 1)) 0) "1.0 vs 1 must be 0") true)

fn runTests -> Bool
  (do
    (assert (testLess) "testLess must pass")
    (assert (testGreater) "testGreater must pass")
    (assert (testTrailingZero) "testTrailingZero must pass")
    true)
