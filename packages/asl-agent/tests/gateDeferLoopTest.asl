(module aslAgent/tests/gateDeferLoopTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref PERF-VACUOUS-GATES-AT-DONE :do "a loop with a unit gate and a whole-tree gate (its command names build.sh): the write turn runs only the unit gate and does not end the run on that green subset, the done turn runs the whole-tree gate, and a red whole-tree gate there keeps the run from ending ok")

fn ! recordedRun! tag: String wholeGate: String -> rk/RecordedRun
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "green\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))")
        repo (gk/initGitRepo! root tag "gate-defer@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        replies (list "(:step :op \"write\" :file \"subject.txt\" :content \"red\\n\")" "(:done)" "(:done)")
        fixture (fileWrite (str fixtureDir "/gd" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "gd" tag) replies))
        form (str "(:agent :task \"fix subject\" :backend \"script/gd" tag "\" :root \""
               (c/escapeAsn root) "\" :mode \"scout\" :owns (\"subject.txt\") :gates (\"true\" \"" (c/escapeAsn wholeGate) "\") :budget 6 :contextTokens 8000)")
        code (m/main (list form))
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? journalName) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" journalName)) ""))
        cleaned (pathRemove root)]
    (rk/RecordedRun :exitCode code :journal text :sentLines (list)))

fn before text: String marker: String -> String
  (match (stringIndexOf text marker) ((some i) (optionOr (stringSlice text 0 i) "")) ((none) text))

fn ! runTests -> Bool
  (let [green (recordedRun! "green" "echo build.sh")
        red (recordedRun! "red" "echo build.sh; grep -q green subject.txt")
        turn1Green (before green.journal "(:turnTime :turn 1 ")
        turn1Red (before red.journal "(:turnTime :turn 1 ")]
    (do
      (assert (stringContains? turn1Green "(:gate :cmd \"true\" :exit 0)") "the write turn runs the unit gate")
      (assert (not (stringContains? turn1Green ":cmd \"echo build.sh")) "the write turn defers the whole-tree gate")
      (assert (stringContains? green.journal "(:gatesDeferred :turn 1 :gates (\"echo build.sh\"))") "the write turn names the deferred whole-tree gate")
      (assert (not (stringContains? green.journal "(:gatesDeferred :turn 2 ")) "the done turn defers nothing")
      (assert (stringContains? green.journal "(:gate :cmd \"echo build.sh\" :exit 0)") "the done turn runs the whole-tree gate")
      (assert (stringContains? green.journal "(:gateIntegrity") "with every gate green on the done turn the run reaches its terminal check")
      (assert (not (stringContains? (before green.journal "(:turn 2 :sent") "(:gateIntegrity")) "the green unit subset of the write turn is not terminal")
      (assert (not (stringContains? turn1Red ":cmd \"echo build.sh")) "the red case defers the whole-tree gate too")
      (assert (stringContains? red.journal ":cmd \"echo build.sh; grep -q green subject.txt\" :exit 1") "the done turn runs the red whole-tree gate")
      (assert (not (stringContains? red.journal "(:gateIntegrity")) "a red whole-tree gate at done keeps the run from its terminal check, so it never ends ok")
      (assert (!= red.exitCode 0) "the red run does not exit 0")
      true))
