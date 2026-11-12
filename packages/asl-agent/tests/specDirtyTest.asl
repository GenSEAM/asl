(module aslAgent/tests/specDirtyTest
  :x [runTests]
  :i [(aslAgent/runLoop :a rl)])

; (:m :ref LEON-DONE-WITHOUT-WIRING :do "specTargets is the distinct union of the files this run wrote and the owned files that differ from HEAD, so a continuation run that writes nothing on top of a restored patch still grades the dirty tree; specCheckWanted? is the guard that runs the check only at an ok finish with at least one target")
fn runTests -> Bool
  (do
    (assert (= (rl/specTargets (list) (list "a.asl")) (list "a.asl"))
      "specTargets of empty written and dirty (a.asl) is (a.asl)")
    (assert (= (rl/specTargets (list "a.asl") (list "a.asl" "b.asl")) (list "a.asl" "b.asl"))
      "specTargets of (a.asl) and (a.asl b.asl) is both, no duplicates")
    (assert (listEmpty? (rl/specTargets (list) (list)))
      "specTargets of empty and empty is empty")
    (assert (and (rl/specCheckWanted? true "ok" (list "a.asl")) (not (rl/specCheckWanted? true "ok" (list))))
      "the spec-check guard is true for (true ok (a.asl)) and false for (true ok ())")
    true)
