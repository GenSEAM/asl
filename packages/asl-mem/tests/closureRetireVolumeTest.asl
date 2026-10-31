(module asl-mem/tests/closureRetireVolumeTest :x [runTests] :i [(aslMem/records :a rec) (aslMem/amnesia :a am) (aslMem/viewLayer :a vl) (aslMem/contextScoring :a cs)])

; (:m :ref COVBATCH3 :do "isClosureEvaluable?, transitionToRetired, calculateActiveVolume, isVolumeBounded? had no call path from any test")
fn closure kind: String p: String obs: String ev: Bool -> rec/ClosureCondition
  (rec/makeClosureCondition kind p obs ev)

fn runTests -> Bool
  (let [(chunk (vl/makeMemoryChunk "c1" 5 0.9 "sum" (list "f") (list "d") (list "r")))
        (retired (am/transitionToRetired chunk "goal met" 99))
        (r1 (cs/makeContextRecord "a" true 1.0 2 3))
        (r2 (cs/makeContextRecord "b" false 1.0 0 3))]
    (do
      (assert (rec/isClosureEvaluable? (closure "k" "tests pass" "exit code" true)) "a complete evaluable condition passes")
      (assert (rec/isClosureEvaluable? (closure "k" "  tests pass  " " exit code " true)) "padding is ignored")
      (assert (not (rec/isClosureEvaluable? (closure "k" "tests pass" "exit code" false))) "evaluable false fails")
      (assert (not (rec/isClosureEvaluable? (closure "k" "" "exit code" true))) "an empty predicate fails")
      (assert (not (rec/isClosureEvaluable? (closure "k" "   " "exit code" true))) "a blank predicate fails")
      (assert (not (rec/isClosureEvaluable? (closure "k" "tests pass" "" true))) "an empty observable fails")
      (assert (not (rec/isClosureEvaluable? (closure "k" "unevaluable claim" "exit code" true))) "unevaluable in the predicate fails")
      (assert (not (rec/isClosureEvaluable? (closure "k" "tests pass" "an unevaluable thing" true))) "unevaluable in the observable fails")
      (assert (= retired.status "retired") "status is retired")
      (assert (= retired.closureCondition "goal met") "the closure condition is kept")
      (assert (= retired.retiredAt 99) "the retirement time is kept")
      (assert (= retired.chunk.id "c1") "the chunk is carried over")
      (assert (= (am/transitionToRetired chunk "" 0).retiredAt 0) "time zero is kept")
      (assert (= (cs/calculateActiveVolume (list)) 0) "no records, no volume")
      (assert (= (cs/calculateActiveVolume (list r1)) 1) "one record")
      (assert (= (cs/calculateActiveVolume (list r1 r2 r1)) 3) "volume counts records")
      (assert (cs/isVolumeBounded? 3 3) "volume at the ceiling is bounded")
      (assert (cs/isVolumeBounded? 0 0) "zero at zero is bounded")
      (assert (cs/isVolumeBounded? -1 0) "below the ceiling is bounded")
      (assert (not (cs/isVolumeBounded? 4 3)) "above the ceiling is not bounded")
      true))
