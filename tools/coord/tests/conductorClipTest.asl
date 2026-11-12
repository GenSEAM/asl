(module asl-tools/coord/tests/conductorClipTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd)])

; (:m :ref JOURNAL-UTF8-CUT :do "the conductor's journal clips cut at a character boundary: a verdict whose 400th byte falls inside a three-byte character keeps whole characters and stays valid UTF-8, a short text is unchanged, an ASCII text is cut at exactly the limit")
fn cjk n: Int64 acc: String -> String
  (if (<= n 0) acc (cjk (- n 1) (str acc "那")))

fn ! runTests -> Bool
  (let [(sig (str "xy" (cjk 200 "")))
        (cut (cd/verdictSig sig))
        (cutBytes (bytesLength (stringToBytes cut)))
        (ascii (cd/utf8Clip "abcdefghij" 4))
        (mid (cd/utf8Clip "ab那些" 4))]
    (do (assert (= (bytesLength (stringToBytes sig)) 602) "fixture: 2 ASCII bytes then 200 three-byte characters")
        (assert (= cutBytes 398) (str "the 400-byte verdict cut, which falls inside a character, backs off to its start: " cutBytes " bytes"))
        (assert (= cut (str "xy" (cjk 132 ""))) "the cut verdict is whole characters, valid UTF-8")
        (assert (= (listLength (stringChars cut)) 134) "every character of the cut verdict is complete")
        (assert (= ascii "abcd") "ASCII cuts at exactly the limit")
        (assert (= mid "ab") "a limit inside the first multibyte character drops it whole")
        (assert (= (cd/utf8Clip "ab那些" 5) "ab那") "a limit at a character end keeps it")
        (assert (= (cd/utf8Clip "short" 160) "short") "text under the limit is unchanged")
        true))
