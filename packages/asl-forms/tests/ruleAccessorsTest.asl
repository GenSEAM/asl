(module asl-forms/tests/ruleAccessorsTest :x [runTests] :i [(asl-forms/rewrite :a rw)])

; (:m :ref COVBATCH2 :do "rulePattern and ruleReplacement return what makeRule was given, including empty and multi-line text")
fn runTests -> Bool
  (let [(r (rw/makeRule "(f ?x)" "(g ?x)"))
        (empty (rw/makeRule "" ""))
        (multi (rw/makeRule "a\nb" "c\nd"))]
    (do
      (assert (= (rw/rulePattern r) "(f ?x)") "pattern")
      (assert (= (rw/ruleReplacement r) "(g ?x)") "replacement")
      (assert (= (rw/rulePattern empty) "") "empty pattern")
      (assert (= (rw/ruleReplacement empty) "") "empty replacement")
      (assert (= (rw/rulePattern multi) "a\nb") "multi-line pattern")
      (assert (= (rw/ruleReplacement multi) "c\nd") "multi-line replacement")
      (assert (not (= (rw/rulePattern r) (rw/ruleReplacement r))) "the two accessors read different fields")
      true))
