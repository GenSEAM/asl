(module aslAgent/tests/readNudgeTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-READ-NUDGE :do "a read-only streak is nudged once halfway to :readOnlyTurnCap, in the prompt the model sees next, before the cap stops the run")

fn ! runTests -> Bool
  (let [root (rk/freshRecorderRoot! "readNudge")
        wroteS (fileWrite (str root "/subject.txt") "green\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false :readOnlyTurnCap 6))")
        repo (gk/initGitRepo! root "readNudge" "read-nudge@example.invalid")
        replies (map (fn [i] (str "(:step :op \"read\" :file \"subject.txt\" :start " (stringFromInt64 (+ i 1)) " :end 1)")) (range 0 10))
        run (rk/runRecordedAgentLoopWithReplies! root "readNudge" replies (list "subject.txt") "fix subject" 20 8000)
        lines (stringSplit run.journal "\n")
        nudges (filter (fn [l] (stringContains? l ":signal :readNudge")) lines)
        sentAfter (filter (fn [l] (stringContains? l "(:nudge :readOnly 3 :cap 6")) run.sentLines)
        cleaned (pathRemove root)]
    (do
      (assert (= (listLength nudges) 1) (str "one readNudge signal in the streak, got " (stringFromInt64 (listLength nudges))))
      (assert (stringContains? run.journal "(:turn 3 :signal :readNudge :readOnly 3 :cap 6)") "the nudge fires at half the cap of 6")
      (assert (not (listEmpty? sentAfter)) "the nudge text reaches a prompt the model is sent")
      (assert (stringContains? run.journal ":signal :readStreak :cause :readOnly") "the cap still stops the run")
      true))
