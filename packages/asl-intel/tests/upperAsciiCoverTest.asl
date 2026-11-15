(module asl-intel/tests/upperAsciiCoverTest
  :x [runTests]
  :i [(asl-intel/text :a tx)])

; (:m :ref COVRATCHET :do "upperAscii maps a-z to A-Z and leaves digits and existing capitals alone; the empty string stays empty")
fn runTests -> Bool
  (do
    (assert (= (tx/upperAscii "aB1z") "AB1Z") "mixed case with a digit")
    (assert (= (tx/upperAscii "") "") "empty string stays empty")
    true)
