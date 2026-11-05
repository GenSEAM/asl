(module aslAgent/tests/opRowsTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m) (asl-json/json :a j)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref TRIAL-LEON-OPROWS :do "a scripted run of a read, a write outside :owns and an owned edit leaves exactly three (:op ...) journal rows in order: ok, err ERR_OWNS, ok; LEON-READLOOP: twenty successful read-only turns stop as readStreak cause readOnly at the cap, a run that alternates reads and gate runs does not")

fn ! recordedRun! tag: String replies: (List String) gates: String cfg: String -> rk/RecordedRun
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "red\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") cfg)
        repo (gk/initGitRepo! root "opRows" "op-rows@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/o" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "o" tag) replies))
        form (str "(:agent :task \"fix subject\" :backend \"script/o" tag "\" :root \""
               (c/escapeAsn root) "\" :mode \"scout\" :owns (\"subject.txt\") :gates (" gates ") :budget 60 :contextTokens 8000)")
        code (m/main (list form))
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? journalName) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" journalName)) ""))
        cleaned (pathRemove root)]
    (rk/RecordedRun :exitCode code :journal text :sentLines (list)))

fn opRows journal: String -> (List String)
  (filter (fn [l] (stringStartsWith? l "(:op :turn ")) (stringLines journal))

fn readReply _i: Int64 -> String
  "(:step :op \"read\" :file \"subject.txt\")"

fn ! pureTests -> Bool
  (do
    (assert (= (m/opRowText 3 "write" "x.txt" "rejected" "ERR_OWNS") "(:op :turn 3 :name \"write\" :file \"x.txt\" :status err :error ERR_OWNS)") "an err row carries the error code")
    (assert (= (m/opRowText 1 "read" "a" "ok" "") "(:op :turn 1 :name \"read\" :file \"a\" :status ok)") "an ok row carries no error")
    (assert (= (m/readOnlyTurnCapIn "") 16) "readOnlyTurnCap defaults to 16")
    (assert (= (m/readOnlyTurnCapIn "(:aslConfig :agentLoop (:readOnlyTurnCap 5))") 5) "readOnlyTurnCap reads the :agentLoop row")
    true)

fn ! runTests -> Bool
  (let [pure (pureTests)
        rows (recordedRun! "rows" (list (readReply 0) "(:step :op \"write\" :file \"other.txt\" :content \"x\")" "(:step :op \"edit\" :file \"subject.txt\" :old \"red\" :new \"green\")" "(:done)") "" "(:aslConfig :agentLoop (:specCheck false))")
        loop (recordedRun! "loop" (map readReply (range 0 20)) "" "(:aslConfig :agentLoop (:specCheck false))")
        alt (recordedRun! "alt" (listAppend (map (fn [i] (if (= (- i (* 2 (/ i 2))) 0) (readReply i) (str "(:step :op \"gate\")"))) (range 0 20)) (list "(:done)")) "\"exit 1\"" "(:aslConfig :agentLoop (:specCheck false))")
        shortCap (recordedRun! "cap" (map readReply (range 0 8)) "" "(:aslConfig :agentLoop (:specCheck false :readOnlyTurnCap 4))")]
    (do
      (assert pure "pure helpers")
      (assert (= (listLength (opRows rows.journal)) 3) "three steps leave three op rows, the done leaves none")
      (assert (and (stringContains? (optionOr (listGet (opRows rows.journal) 0) "") ":name \"read\" :file \"subject.txt\" :status ok")
                (stringContains? (optionOr (listGet (opRows rows.journal) 1) "") ":name \"write\" :file \"other.txt\" :status err :error ERR_OWNS")) "rows are ok then err ERR_OWNS")
      (assert (stringContains? (optionOr (listGet (opRows rows.journal) 2) "") ":name \"edit\" :file \"subject.txt\" :status ok") "the owned edit row is ok")
      (assert (stringContains? loop.journal ":signal :readStreak :cause :readOnly") "twenty successful reads stop as readStreak cause readOnly")
      (assert (not (stringContains? loop.journal "(:turn 17 :reply")) "the stop lands on the sixteenth read, not later")
      (assert (stringContains? shortCap.journal ":signal :readStreak :cause :readOnly") "a configured cap of 4 stops eight reads")
      (assert (not (stringContains? alt.journal ":cause :readOnly")) "reads alternating with gate runs never stop as readOnly")
      true))
