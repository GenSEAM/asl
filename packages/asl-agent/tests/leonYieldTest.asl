(module aslAgent/tests/leonYieldTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-YIELD :do "F2 refused writes do not extend readStreak past the cap, F3 a model (:escalate) is the stop modelEscalated with its reason, F4 identical read steps in one reply run once; each assertion is driven through main with a scripted provider and a red gate, so the stop signal in the journal is the claim")

fn opOf name: String file: String -> (List (Pair String c/KvVal))
  (list (pair "op" (c/kvStr name)) (pair "file" (c/kvStr file)))

fn ! recordedRun! tag: String replies: (List String) -> rk/RecordedRun
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "red\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))")
        repo (gk/initGitRepo! root "leonYield" "leon-yield@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/y" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "y" tag) replies))
        form (str "(:agent :task \"fix subject\" :backend \"script/y" tag "\" :root \""
               (c/escapeAsn root) "\" :mode \"scout\" :owns (\"subject.txt\") :gates (\"exit 1\") :budget 40 :contextTokens 8000)")
        code (m/main (list form))
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? journalName) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" journalName)) ""))
        lines (stringSplit text "\n")
        sent (filter (fn [l] (and (>= (rk/sentLineTurn l) 0) (stringContains? l ":sent \""))) lines)
        cleaned (pathRemove root)]
    (rk/RecordedRun :exitCode code :journal text :sentLines sent))

; (:m :ref LEON-YIELD :do "the first reply persists an owned write so the declared gate runs once and reads red; only then does a read streak count against a red gate")
fn primeReply -> String
  "(:step :op \"write\" :file \"subject.txt\" :content \"v1\\n\")"

fn idRead id: String -> String
  (str "(:step :op \"read\" :id \"" id "\" :file \"subject.txt\")")

fn readReply _i: Int64 -> String
  "(:step :op \"read\" :file \"subject.txt\")"

fn refusedWriteReply i: Int64 -> String
  (str "(:step :op \"write\" :file \"other" (stringFromInt64 i) ".txt\" :content \"x" (stringFromInt64 i) "\")")

fn ! pureTests -> Bool
  (let [r1 (opOf "read" "a")
        r2 (opOf "read" "b")
        w1 (opOf "write" "a")
        r1id (list (pair "op" (c/kvStr "read")) (pair "id" (c/kvStr "x")) (pair "file" (c/kvStr "a")))
        deduped (m/dedupeReadOps (list r1 r1id r2 r1 r2) (list) (list) 0)
        afterWrite (m/dedupeReadOps (list r1 w1 r1 r1) (list) (list) 0)
        form "(:escalate :reason \"stuck on parser\" :seen \"s\" :tried \"t\")"
        formOp (list (pair "type" (c/kvStr "escalate")) (pair "form" (c/kvStr form)))
        stepOp (list (pair "op" (c/kvStr "escalate")) (pair "reason" (c/kvStr "via step")))]
    (do
      (assert (and (= (listLength (pairFirst deduped)) 2) (= (pairSecond deduped) 3)) "identical reads in one reply collapse to the distinct ones in order")
      (assert (and (= (listLength (pairFirst afterWrite)) 3) (= (pairSecond afterWrite) 1)) "a write between two identical reads makes the second one count again")
      (assert (= (m/modelEscalationReason (list r1 formOp)) (some "stuck on parser")) "escalate form reason is read")
      (assert (= (m/modelEscalationReason (list stepOp)) (some "via step")) "escalate step reason is read")
      (assert (= (m/modelEscalationReason (list r1)) none) "no escalate op gives none")
      (assert (= (m/modelEscalationReceipt (list formOp)) (some "(:escalate :reason \"stuck on parser\" :seen \"s\" :tried \"t\")")) "receipt keeps reason, seen and tried")
      (assert (and (m/writeAttempt? (list r1 w1)) (not (m/writeAttempt? (list r1)))) "write attempt detection")
      (assert (= (m/nextReadStreakOf false true 3 5) 5) "a stalled turn past the cap holds the streak")
      (assert (= (m/nextReadStreakOf false true 1 5) 6) "a stalled turn within the cap extends it")
      (assert (= (m/nextReadStreakOf false false 9 5) 6) "a plain read extends it")
      (assert (= (m/nextReadStreakOf false true 2 5) 6) "boundary: a stalled streak equal to the cap still extends")
      (assert (= (m/nextReadStreakOf false true 3 5) 5) "boundary: one past the cap holds")
      (assert (and (= (m/stalledTurnCapIn "") 12) (= (m/stalledTurnCapIn "(:aslConfig :agentLoop (:stalledTurnCap 3))") 3)) "stalledTurnCap defaults to 12 and reads the :agentLoop row")
      (assert (= (m/nextReadStreakOf true false 0 5) 0) "a persisted write resets it")
      true))

fn ! runTests -> Bool
  (let [pure (pureTests)
        reads (recordedRun! "reads" (cons (primeReply) (map readReply (range 0 16))))
        refused (recordedRun! "refused" (cons (primeReply) (map refusedWriteReply (range 0 16))))
        escalated (recordedRun! "esc" (list (primeReply) (readReply 0) "(:escalate :reason \"cannot see the cause\" :seen \"gate red\" :tried \"two reads\")" (readReply 1) (readReply 2)))
        dup (recordedRun! "dup" (list (stringJoin (list (idRead "a") (idRead "b") (idRead "c") (idRead "d")) "\n") "(:done)"))]
    (do
      (assert pure "pure helpers")
      (assert (stringContains? reads.journal ":signal :readStreak") "control: sixteen pure-read turns with a red gate still stop as readStreak")
      (assert (not (stringContains? refused.journal ":signal :readStreak :reason")) "refused writes do not end as the plain readStreak stop")
      (assert (stringContains? refused.journal ":signal :readStreak :cause :refusedWrites") "twelve stalled turns after a persisted write stop as readStreak with cause refusedWrites")
      (assert (and (stringContains? refused.journal "other11.txt") (not (stringContains? refused.journal "other12.txt"))) "the stop lands on the twelfth stalled turn")
      (assert (stringContains? escalated.journal ":signal :modelEscalated :reason \"cannot see the cause\"") "a model escalate stops the run as modelEscalated with its reason")
      (assert (not (stringContains? escalated.journal ":signal :readStreak")) "a model escalate is not recorded as readStreak")
      (assert (not (stringContains? escalated.journal "(:turn 4 :reply")) "the run ends at the escalate turn")
      (assert (listAny? (fn [l] (and (stringContains? l "(:turn 2 ") (stringContains? l ":duplicateOps :dropped 3"))) dup.sentLines) "four reads that differ only in :id run once and the reply says three were dropped")
      true))
