(module asl-utils/tests/bitsetTest
  :x [runTests]
  :i [(asl-utils/bitset :a b)])

fn testSetClear -> Bool
  (let [(s (b/bsNew 16))]
    (do (assert (not (b/bsTest s 3)) "fresh bit is clear")
        (assert (= (b/bsCount s) 0) "fresh set counts zero bits")
        (b/bsSet s 3)
        (assert (b/bsTest s 3) "set bit tests true")
        (assert (= (b/bsCount s) 1) "one bit set")
        (b/bsSet s 0)
        (b/bsSet s 15)
        (assert (= (b/bsCount s) 3) "three bits set")
        (b/bsClear s 3)
        (assert (not (b/bsTest s 3)) "cleared bit tests false")
        (assert (= (b/bsCount s) 2) "two bits remain")
        (assert (b/bsTest s 15) "top bit stays set")
        true))

fn testUnion -> Bool
  (let [(a (b/bsNew 8)) (c (b/bsNew 8))]
    (do (b/bsSet a 1)
        (b/bsSet c 2)
        (let [(u (b/bsUnion a c))]
          (do (assert (b/bsTest u 1) "union keeps a-only bit")
              (assert (b/bsTest u 2) "union keeps c-only bit")
              (assert (= (b/bsCount u) 2) "union counts both bits")
              true))))

fn testIntersect -> Bool
  (let [(a (b/bsNew 8)) (c (b/bsNew 8))]
    (do (b/bsSet a 1)
        (b/bsSet a 2)
        (b/bsSet c 2)
        (b/bsSet c 3)
        (let [(u (b/bsIntersect a c))]
          (do (assert (b/bsTest u 2) "intersect keeps common bit")
              (assert (not (b/bsTest u 1)) "intersect drops a-only bit")
              (assert (= (b/bsCount u) 1) "intersect counts one bit")
              true))))

fn testDifference -> Bool
  (let [(a (b/bsNew 8)) (c (b/bsNew 8))]
    (do (b/bsSet a 1)
        (b/bsSet a 2)
        (b/bsSet c 2)
        (let [(u (b/bsDifference a c))]
          (do (assert (b/bsTest u 1) "difference keeps a-only bit")
              (assert (not (b/bsTest u 2)) "difference drops shared bit")
              (assert (= (b/bsCount u) 1) "difference counts one bit")
              true))))

fn testIterate -> Bool
  (let [(s (b/bsNew 16))]
    (do (b/bsSet s 0)
        (b/bsSet s 3)
        (b/bsSet s 9)
        (let [(xs (b/bsToList s))]
          (do (assert (= (listLength xs) 3) "three set bits iterated")
              (assert (= (listGet xs 0) (some 0)) "first index is 0")
              (assert (= (listGet xs 1) (some 3)) "second index is 3")
              (assert (= (listGet xs 2) (some 9)) "third index is 9")
              (b/bsClear s 3)
              (let [(ys (b/bsToList s))]
                (do (assert (= (listLength ys) 2) "iteration follows clears")
                    (assert (= (listGet ys 0) (some 0)) "first surviving index is 0")
                    (assert (= (listGet ys 1) (some 9)) "second surviving index is 9")
                    true))))))

fn runTests -> Bool
  (and (testSetClear) (testUnion) (testIntersect) (testDifference) (testIterate))
