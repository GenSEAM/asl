(module asl-text/tests/stringClipTest :x [runTests] :i [(string :a s)])

; (:m :ref UTF8-CLIP-SWEEP :do "a 1-, 2-, 3- and 4-byte character after one ASCII byte: e acute U+00E9, CJK U+6F22, U+1F600; byte offsets are the cut points")
fn two -> String "aé"
fn three -> String "a漢"
fn four -> String "a\u{1F600}"

fn ! testAscii -> Bool
  (do (assert (= (s/stringClipUtf8 "abcdef" 3) "abc") "ascii cuts at n bytes")
      (assert (= (s/stringClipUtf8 "abcdef" 6) "abcdef") "n = length returns s")
      (assert (= (s/stringClipUtf8 "abcdef" 99) "abcdef") "n > length returns s")
      (assert (= (s/stringClipUtf8 "abcdef" 0) "") "n = 0 is empty")
      (assert (= (s/stringClipUtf8 "abcdef" -5) "") "n < 0 is empty")
      (assert (= (s/stringClipUtf8 "" 4) "") "empty stays empty")
      true)

fn ! cutsBack name: String text: String bytes: Int64 -> Bool
  (do (assert (= (stringLength text) (+ 1 bytes)) (str name ": the fixture is one ASCII byte and one " bytes "-byte character"))
      (fold (fn [(acc Bool) (n Int64)] -> Bool
              (do (assert (= (s/stringClipUtf8 text n) "a") (str name ": a cut at byte " n " inside the character moves back to its start"))
                  acc))
            true (range 1 (+ bytes 1)))
      (assert (= (s/stringClipUtf8 text (+ bytes 1)) text) (str name ": a cut at the character's end keeps it"))
      (assert (= (stringLength (s/stringClipUtf8 (str text text) (+ bytes 2))) (+ bytes 2)) (str name ": a cut right after the next ASCII byte keeps it"))
      true)

fn ! testMultiByte -> Bool
  (do (assert (cutsBack "2-byte" (two) 2) "2-byte character")
      (assert (cutsBack "3-byte" (three) 3) "3-byte character")
      (assert (cutsBack "4-byte" (four) 4) "4-byte character")
      (assert (= (s/stringClipUtf8 "漢字" 2) "") "a cut inside a leading character is empty")
      (assert (= (s/stringClipUtf8 "漢字" 4) "漢") "a cut inside the second character keeps the first")
      true)

fn ! runTests -> Bool
  (do (assert (testAscii) "ascii and bounds")
      (assert (testMultiByte) "multi-byte boundaries")
      true)
