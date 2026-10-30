(module asl/agentLoop/tests/transcriptBudgetTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (asl/agentLoop/context :a ctx)])

; (:m :ref SPECCASE-DYNAMIC-PROBE :do "regression for the unbounded-transcript defect: liveBody! used to store each turn's full rendered prompt (task plus the whole prior transcript) as that turn's own history entry, and renderWindow always rendered the newest entry whole; together a later turn's whole 'last' re-embedded its predecessor's already-embedded predecessor, compounding every turn (measured 35 -> 223627 chars over 9 turns on the real spec case, >13GB resident by turn 33, not safe to keep reproducing at that size)")
; (:m :ref LEON-CONTEXT-RESEND-20261017 :do "renderWindow's byte-budget cut/drop (the mechanism this suite originally exercised) never actually bounded a real bench run -- its budget was the model's whole context window, so a 20-40 turn run never got near it. renderTranscriptBounded replaced it at the call site with a turn-count bound: this suite now checks the new marker ((:turnSummary) instead of (:elided)), the new early-window boundary (contextKeepTurns, not a hardcoded 12), and a ceiling that holds even though every one of 70 turns reads a ~24KB padding file -- the old budget-based ceiling (contextTokens*4 + overhead) still happens to hold too, so this keeps checking the same numeric ceiling in addition to the new marker")
; (:m :ref LEONFAIL :do "the newest turn's output is the observation the model just asked for; clipping it at contextToolCapBytes (1500) left free-lane runs re-reading the first 1500 bytes of a file for 80-270 turns until the wall budget, with zero writes")

fn fillerFile n: Int64 tag: String -> String
  (stringJoin (map (fn [i] (str tag " padding line " (stringFromInt64 i) " 0123456789012345678901234567890123456789\n")) (range 0 n)) "")

fn ! runTests -> Bool
  (let [root (rk/freshRecorderRoot! "transcriptBudget")
        names (map (fn [i] (str "pad" (stringFromInt64 i) ".txt")) (range 0 70))
        written (listAll? (fn [name] (ok? (fileWrite (str root "/" name) (fillerFile 400 name)))) names)
        contextTokens 8000
        budget (* contextTokens 4)
        overhead 4000
        keepTurns (ctx/contextKeepTurns)
        run (rk/runRecordedAgentLoop! root "transcriptBudget" names "read every padding file" 75 contextTokens)
        n (listLength run.sentLines)
        earlyLines (optionOr (listSlice run.sentLines 0 keepTurns) (list))
        tooLong (filter (fn [l] (> (stringLength l) (+ budget overhead))) run.sentLines)
        summarized (filter (fn [l] (stringContains? l "(:turnSummary")) run.sentLines)
        earlySummarized (filter (fn [l] (stringContains? l "(:turnSummary")) earlyLines)
        latestWhole (filter (fn [l] (stringContains? l " padding line 60 ")) run.sentLines)
        cleaned (ok? (pathRemove root))]
    (do
      (assert written "padding fixture files are written")
      (assert (= run.exitCode 0) "the recorded run completes")
      (assert (>= n 12) "at least 12 turns were journaled")
      (assert (listEmpty? tooLong) (str (stringFromInt64 (listLength tooLong)) " of " (stringFromInt64 n) " turns exceeded budget+overhead"))
      (assert (listEmpty? earlySummarized) (str "no turn is summarized yet while the run is still within the first " (stringFromInt64 keepTurns) " turns (contextKeepTurns)"))
      (assert (> (listLength summarized) 0) "a turnSummary marker appears once the run runs past contextKeepTurns turns")
      (assert (>= (* 2 (listLength latestWhole)) n)
        (str "the newest turn's read reaches the model past contextToolCapBytes (line 60 of a padding file is ~4 KB in), seen in " (stringFromInt64 (listLength latestWhole)) " of " (stringFromInt64 n) " turns"))
      (assert cleaned "the fixture root is removed")
      true))
