(module aslAgent/tests/writeNudgeTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk)])

; (:m :ref LEON-STALL :do "FREEBENCH's n=2x2 paired rerun of ccDeepseekFlash/ocDeepseekFlash on implement-constraints-from-spec found both routes stall the same way: deliver patch, the model rereads the same files turn after turn (read/tree/query/outline ops only, confirmed by grep across all 20 turns of a kept journal, never a write) until the generic noWrite escalation fires at turn 20 with zero in-context warning -- noWriteNudge/nowForm in retry.asl and context.asl were fully written and parity-tested but never called from main.asl#liveBody!, the only turn-building function the real (:agent ...) CLI path uses, so the warning they produce never reached a model; this reproduces the same shape with a scripted provider (no network) and checks the fix: a write-nudge now appears in the turn 11 prompt (ctx/noWriteNudgeTurns turns after deliver patch with nothing written) naming the owned file, is absent before that, and the run still authentically escalates at turn 20 same as the real stall")

fn readTurn -> String
  "(:step :op \"read\" :file \"stub.txt\")"

fn ! runTests -> Bool
  (let [root (rk/freshRecorderRoot! "writeNudge")
        cfg (ok? (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false :readStreakEscalate 100 :readOnlyTurnCap 200))\n"))
        written (ok? (fileWrite (str root "/stub.txt") "stub content, re-read every turn\n"))
        turn1 (str "(:intent :deliver patch :why \"implement impl.txt per the task\")\n" (readTurn))
        replies (listAppend (list turn1) (map (fn [_] (readTurn)) (range 0 19)))
        run (rk/runRecordedAgentLoopWithReplies! root "writeNudge" replies (list "impl.txt")
              "Implement impl.txt per the spec; do not stop reading until certain" 50 8000)
        sentAt (fn [n] (filter (fn [l] (= (rk/sentLineTurn l) n)) run.sentLines))
        turn10Sent (sentAt 10) turn11Sent (sentAt 11)
        nudgeMarker "turns and nothing written; the run stops at turn 20 without a write"
        ownsMarker "Write now to impl.txt"
        cleaned (ok? (pathRemove root))]
    (do
      (assert cfg "the fixture config lifts the read-streak stops so noWrite is the stop under test")
      (assert written "the stub file the scripted turns reread is written")
      (assert (= (listLength replies) 20) "20 scripted turns: 1 intent+read, 19 more reads, none a write")
      (assert (= (listLength turn10Sent) 1) "turn 10's prompt was journaled")
      (assert (= (listLength turn11Sent) 1) "turn 11's prompt was journaled")
      (assert (not (listAny? (fn [l] (stringContains? l nudgeMarker)) turn10Sent))
        "turn 10 (deliver patch, 9 turns with nothing written) is below noWriteNudgeTurns: no nudge yet")
      (assert (listAny? (fn [l] (stringContains? l nudgeMarker)) turn11Sent)
        "turn 11 (10 turns with nothing written, >= noWriteNudgeTurns) carries the write-nudge in its prompt")
      (assert (listAny? (fn [l] (stringContains? l ownsMarker)) turn11Sent)
        "the nudge names the owned file, not a generic warning")
      (assert (stringContains? run.journal "(:turn 20 :signal :noWrite :reason \"nothing written by turn 20 of 50\")")
        "the scripted stall still escalates for real at turn 20, same as the live ccDeepseekFlash stall")
      (assert cleaned "the fixture root is removed")
      true))
