(module asl-gates/tests/landedClipTest
  :x [runTests]
  :i [(asl-gates/auditLanded :a al)])

; (:m :ref UTF8-CLIP-SWEEP :do "a commit subject cut at 100 bytes inside a 3-byte CJK character (U+6F22) after 99 ASCII bytes keeps the ASCII bytes and drops the whole character")
fn ! runTests -> Bool
  (do (assert (= (al/subjectOf (str (stringRepeat "a" 99) "漢zz\nbody line")) (stringRepeat "a" 99)) "subjectOf: the cut lands on the character start")
      (assert (= (al/subjectOf "fix 漢\nbody") "fix 漢") "subjectOf: a short subject is kept whole")
      true)
