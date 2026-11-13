(module aslAgent/tests/journalClipTest
  :x [runTests]
  :i [(aslAgent/journal :a jn) (aslAgent/main :a mn)])

; (:m :ref UTF8-CLIP-SWEEP :do "the fallback row's reason is cut at 120 bytes; a cut inside a 3-byte CJK character (U+6F22) after 119 ASCII bytes drops the whole character, so the journal row stays valid UTF-8")
fn ! runTests -> Bool
  (let [(reason (str (stringRepeat "a" 119) "漢" "tail"))
        (row (jn/fallbackRowText "m" 400 reason))]
    (do (assert (= row (str "(:fallback :noTools true :model \"m\" :status 400 :reason \"" (stringRepeat "a" 119) "\")\n")) (str "the reason keeps the 119 ASCII bytes and no partial character: " row))
        (assert (stringContains? (jn/fallbackRowText "m" 400 "bad 漢") ":reason \"bad 漢\"") "a short reason is kept whole")
        (assert (= (mn/focusTail "focus" (str (stringRepeat "a" 399) "\u6f22zz") (list) false) (str "\n\n(:focus :goal \"" (stringRepeat "a" 399) "\" :gate \"\" :next (:step :op \"read\"|\"edit\"|\"write\" ...))")) "focusTail: the goal cut at 400 bytes keeps the 399 ASCII bytes")
        true))
