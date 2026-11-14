(module asl-intel/tests/padLeftCoverTest
  :x [runTests]
  :i [(asl-intel/text :a tx)])

; (:m :ref COVRATCHET :do "padLeft pads on the left up to a width and leaves longer strings alone")
fn runTests -> Bool
  (do
    (assert (= (tx/padLeft "ab" 4) "  ab") "pads a short string on the left")
    (assert (= (tx/padLeft "abcd" 2) "abcd") "a string past the width is unchanged")
    (assert (= (tx/padLeft "abcd" 4) "abcd") "a string at the width is unchanged")
    (assert (= (tx/padLeft "" 3) "   ") "empty string pads to the width")
    (assert (= (tx/padLeft "x" 0) "x") "zero width is unchanged")
    true)
