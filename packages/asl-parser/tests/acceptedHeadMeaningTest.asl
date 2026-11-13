(module asl-parser/tests/acceptedHeadMeaningTest
  :x [runTests])

; (:m :ref MISS-ABSORB :do "what the accepted foreign heads mean, by execution: this file is read by the reader under test, so same and left run whatever (== a b) and (% a b) were read as; it is the one stored source that keeps the two heads, and storedSpellingTest names it as its only exception")
fn same a: Int64 b: Int64 -> Bool
  (== a b)

fn left a: Int64 b: Int64 -> Int64
  (% a b)

fn neg x: Int64 -> Int64
  (- 0 x)

fn ! runTests -> Bool
  (do
    (assert (same 2 2) "(== 2 2) is true")
    (assert (not (same 2 3)) "(== 2 3) is false")
    (assert (not (same 3 2)) "(== 3 2) is false: not an ordering")
    (assert (= (left 7 3) 1) (str "(% 7 3) is 1, got " (stringFromInt64 (left 7 3))))
    (assert (= (left 9 3) 0) (str "(% 9 3) is 0, got " (stringFromInt64 (left 9 3))))
    (assert (= (left (neg 7) 3) 2) (str "(% -7 3) floors like mod: 2, got " (stringFromInt64 (left (neg 7) 3))))
    (assert (= (left 7 (neg 3)) (neg 2)) (str "(% 7 -3) takes the sign of the divisor: -2, got " (stringFromInt64 (left 7 (neg 3)))))
    (assert (= (left (neg 7) (neg 3)) (neg 1)) (str "(% -7 -3) is -1, got " (stringFromInt64 (left (neg 7) (neg 3)))))
    (assert (= (left (neg 7) 3) (mod (neg 7) 3)) "% and mod agree on a negative dividend")
    true)
