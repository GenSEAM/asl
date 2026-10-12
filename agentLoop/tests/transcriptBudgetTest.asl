(module asl/agentLoop/tests/transcriptBudgetTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk)])

; (:m :ref SPECCASE-DYNAMIC-PROBE :do "regression for the unbounded-transcript defect: liveBody! used to store each turn's full rendered prompt (task plus the whole prior transcript) as that turn's own history entry, and renderWindow always rendered the newest entry whole; together a later turn's whole 'last' re-embedded its predecessor's already-embedded predecessor, compounding every turn (measured 35 -> 223627 chars over 9 turns on the real spec case, >13GB resident by turn 33, not safe to keep reproducing at that size). This suite reproduces the same shape at a safely bounded size: budget is contextTokens*4 (runLoop.asl stateFor), overhead is a generous fixed margin for the Task prefix, the per-turn ASN wrapper and an elided-line marker -- not a byte-exact receipt-format accounting, which the defect's own order-of-magnitude overshoot does not need")

fn fillerFile n: Int64 tag: String -> String
  (stringJoin (map (fn [i] (str tag " padding line " (stringFromInt64 i) " 0123456789012345678901234567890123456789\n")) (range 0 n)) "")

fn ! runTests -> Bool
  (let [root (rk/freshRecorderRoot! "transcriptBudget")
        names (map (fn [i] (str "pad" (stringFromInt64 i) ".txt")) (range 0 70))
        written (listAll? (fn [name] (ok? (fileWrite (str root "/" name) (fillerFile 400 name)))) names)
        contextTokens 8000
        budget (* contextTokens 4)
        overhead 4000
        run (rk/runRecordedAgentLoop! root "transcriptBudget" names "read every padding file" 75 contextTokens)
        n (listLength run.sentLines)
        earlyLines (optionOr (listSlice run.sentLines 0 12) (list))
        tooLong (filter (fn [l] (> (stringLength l) (+ budget overhead))) run.sentLines)
        elided (filter (fn [l] (stringContains? l "(:elided")) run.sentLines)
        earlyElided (filter (fn [l] (stringContains? l "(:elided")) earlyLines)
        cleaned (ok? (pathRemove root))]
    (do
      (assert written "padding fixture files are written")
      (assert (= run.exitCode 0) "the recorded run completes")
      (assert (>= n 12) "at least 12 turns were journaled")
      (assert (listEmpty? tooLong) (str (stringFromInt64 (listLength tooLong)) " of " (stringFromInt64 n) " turns exceeded budget+overhead"))
      (assert (listEmpty? earlyElided) "no elision is needed yet while the first 12 turns still fit the budget")
      (assert (> (listLength elided) 0) "an elided marker appears once later history exceeds the budget")
      (assert cleaned "the fixture root is removed")
      true))
