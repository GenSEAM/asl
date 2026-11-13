(module aslAgent/tests/opRowsTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m) (asl-json/json :a j)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref TRIAL-LEON-OPROWS :do "a scripted run of a read, a write outside :owns and an owned edit leaves exactly three (:op ...) journal rows in order: ok, err ERR_OWNS, ok; LEON-READLOOP: twenty successful read-only turns stop as readStreak cause readOnly at the cap, a run that alternates reads and gate runs does not")

; (:m :ref LEON-RECEIPT-READS :do "recordedOut! keeps the receipt main prints: the run goes through mainWithRoots with the roots mainCli takes, and the receipt is printed as main would")
fn ! recordedRun! tag: String replies: (List String) gates: String cfg: String -> rk/RecordedRun
  (pairFirst (recordedOut! tag replies gates cfg))

fn ! recordedOut! tag: String replies: (List String) gates: String cfg: String -> (Pair rk/RecordedRun String)
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "red\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") cfg)
        repo (gk/initGitRepo! root "opRows" "op-rows@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/o" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "o" tag) replies))
        form (str "(:agent :task \"fix subject\" :backend \"script/o" tag "\" :root \""
               (c/escapeAsn root) "\" :mode \"scout\" :owns (\"subject.txt\") :gates (" gates ") :budget 60 :contextTokens 8000)")
        repoRoot (resultOr (realPath ".") ".")
        rootDir (match (envGet "ASL_ROOT_DIR") ((some r) (if (stringEmpty? r) repoRoot r)) ((none) repoRoot))
        res (m/mainWithRoots (list form) repoRoot rootDir)
        printed (println res.stdout)
        code res.exitCode
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? journalName) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" journalName)) ""))
        cleaned (pathRemove root)]
    (pair (rk/RecordedRun :exitCode code :journal text :sentLines (list)) res.stdout))

fn opRows journal: String -> (List String)
  (filter (fn [l] (stringStartsWith? l "(:op :turn ")) (stringLines journal))

fn refusedReply -> String
  "(:step :op \"write\" :file \"other.txt\" :content \"x\")"

fn editReply -> String
  "(:step :op \"edit\" :file \"subject.txt\" :old \"red\" :new \"green\")"

fn cap4 -> String
  "(:aslConfig :agentLoop (:specCheck false :readOnlyTurnCap 4))"

fn readReply _i: Int64 -> String
  "(:step :op \"read\" :file \"subject.txt\")"

fn ! pureTests -> Bool
  (do
    (assert (= (m/opRowText 3 "write" "x.txt" "rejected" "ERR_OWNS") "(:op :turn 3 :name \"write\" :file \"x.txt\" :status err :error ERR_OWNS)") "an err row carries the error code")
    (assert (= (m/opRowText 1 "read" "a" "ok" "") "(:op :turn 1 :name \"read\" :file \"a\" :status ok)") "an ok row carries no error")
    (assert (= (m/readOnlyTurnCapIn "") 12) "readOnlyTurnCap defaults to 12 (LEON-READ-LOOP-CONTEXT-LOSS)")
    (assert (= (m/readOnlyTurnCapIn "(:aslConfig :agentLoop (:readOnlyTurnCap 5))") 5) "readOnlyTurnCap reads the :agentLoop row")
    true)

fn ! runTests -> Bool
  (let [pure (pureTests)
        rows (recordedRun! "rows" (list (readReply 0) "(:step :op \"write\" :file \"other.txt\" :content \"x\")" "(:step :op \"edit\" :file \"subject.txt\" :old \"red\" :new \"green\")" "(:done)") "" "(:aslConfig :agentLoop (:specCheck false))")
        loopOut (recordedOut! "loop" (map readReply (range 0 20)) "" "(:aslConfig :agentLoop (:specCheck false))")
        loop (pairFirst loopOut)
        receipt (pairSecond loopOut)
        sym (recordedRun! "sym" (list "(:step :op \"read\" :file \"subject.txt\" :symbol \"red\")" "(:step :op \"read\" :file \"subject.txt\" :start 1 :end 1)" "(:done)") "" "(:aslConfig :agentLoop (:specCheck false))")
        alt (recordedRun! "alt" (listAppend (map (fn [i] (if (= (- i (* 2 (/ i 2))) 0) (readReply i) (str "(:step :op \"gate\")"))) (range 0 20)) (list "(:done)")) "\"exit 1\"" "(:aslConfig :agentLoop (:specCheck false))")
        wroteMid (recordedRun! "wmid" (listAppend (map readReply (range 0 3)) (cons (editReply) (map readReply (range 0 3)))) "" (cap4))
        mixed (recordedRun! "mixed" (listAppend (map readReply (range 0 3)) (cons "(:step :op \"read\" :file \"subject.txt\")\n(:step :op \"run\" :argv \"ls\")" (list (readReply 0)))) "" (cap4))
        refusedAlt (recordedRun! "refalt" (map (fn [i] (if (= (- i (* 2 (/ i 2))) 0) (readReply i) (refusedReply))) (range 0 12)) "" (cap4))
        redAlt (recordedRun! "redalt" (cons "(:step :op \"gate\")" (map (fn [i] (if (= (- i (* 2 (/ i 2))) 0) (readReply i) (refusedReply))) (range 0 40))) "\"exit 1\"" "(:aslConfig :agentLoop (:specCheck false :readStreakNudge 3 :readStreakEscalate 6 :readOnlyTurnCap 100))")
        unnamed (recordedRun! "unnamed" (list "(:step :file \"subject.txt\")" "(:step :op 7 :file \"subject.txt\")") "" "(:aslConfig :agentLoop (:specCheck false))")
        shortCap (recordedRun! "cap" (map readReply (range 0 8)) "" "(:aslConfig :agentLoop (:specCheck false :readOnlyTurnCap 4))")]
    (do
      (assert pure "pure helpers")
      (assert (= (listLength (opRows rows.journal)) 3) "three steps leave three op rows, the done leaves none")
      (assert (and (stringContains? (optionOr (listGet (opRows rows.journal) 0) "") ":name \"read\" :file \"subject.txt\" :status ok")
                (stringContains? (optionOr (listGet (opRows rows.journal) 1) "") ":name \"write\" :file \"other.txt\" :status err :error ERR_OWNS")) "rows are ok then err ERR_OWNS")
      (assert (stringContains? (optionOr (listGet (opRows rows.journal) 2) "") ":name \"edit\" :file \"subject.txt\" :status ok") "the owned edit row is ok")
      (assert (stringContains? loop.journal ":signal :readStreak :cause :readOnly") "twenty successful reads stop as readStreak cause readOnly")
      (assert (not (stringContains? loop.journal "(:turn 13 :reply")) "the stop lands on the twelfth read, not later")
      (assert (stringContains? receipt " :streak 12 :reads (:n 12 :distinct 1 :top ((:at \"subject.txt\" :count 12 :last 12)))") (str "the live receipt of the stopped run carries :streak 12 and its twelve reads of one place (LEON-RECEIPT-READS): " receipt))
      (assert (listAny? (fn [l] (stringContains? l ":name \"read\" :file \"subject.txt\" :at \"#red\" :status ")) (opRows sym.journal)) (str "a live symbol read leaves an op row with :at \"#red\": " (stringJoin (opRows sym.journal) " | ")))
      (assert (listAny? (fn [l] (stringContains? l ":at \":1-1\" :status ")) (opRows sym.journal)) (str "a live range read leaves its :at too: " (stringJoin (opRows sym.journal) " | ")))
      (assert (stringContains? shortCap.journal ":signal :readStreak :cause :readOnly") "a configured cap of 4 stops eight reads")
      (assert (not (stringContains? wroteMid.journal ":cause :readOnly")) "a persisted edit between reads resets the read-only count")
      (assert (not (stringContains? mixed.journal ":cause :readOnly")) "a turn that mixes a read with a run step is not read-only")
      (assert (stringContains? refusedAlt.journal ":cause :readOnly") "reads alternating with refused writes stop at the cap, a refused write is no progress")
      (assert (stringContains? redAlt.journal ":signal :readStreak") "reads alternating with refused writes stop as readStreak while a gate is red")
      (assert (not (stringContains? redAlt.journal ":cause :readOnly")) "the red-gate stop is the gate readStreak, not the readOnly cap")
      (assert (stringContains? redAlt.journal "(:turn 6 :signal :readStreak") "the stop lands on turn 6, the configured escalate: reads and refused writes each count one turn toward the streak")
      (assert (not (stringContains? redAlt.journal "(:turn 8 :reply")) "no turn runs past the stop (a refused write holding the streak would stop later)")
      (assert (= (listLength (filter (fn [l] (stringContains? l ":name \"?\" ")) (opRows unnamed.journal))) 2) "a step without a usable :op still leaves a row named ?")
      (assert (and (listAny? (fn [l] (stringContains? l ":name \"?\" :file \"subject.txt\" :status err :error ERR_NO_OP")) (opRows unnamed.journal))
                (listAny? (fn [l] (stringContains? l ":name \"?\" :file \"subject.txt\" :status err :error ERR_EFFECT_UNDECLARED")) (opRows unnamed.journal))) "the unnamed rows carry the error code")
      (assert (not (stringContains? alt.journal ":cause :readOnly")) "reads alternating with gate runs never stop as readOnly")
      true))
