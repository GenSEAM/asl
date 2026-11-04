(module aslAgent/tests/repeatRefusalTest
  :x [runTests]
  :i [(aslAgent/context :a ctx) (aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-IDENTICAL-2 :do "node2 2026-11-03: 11 of 18 repeatFailure stops resent a refused write byte-identical; the turn before the cap carries the refusal text and the instruction to change the content")

fn badReplies -> (List String)
  (map (fn [_] "(:step :op \"write\" :file \"elsewhere/x.txt\" :content \"x\\n\")") (range 0 5))

fn ! recordedRun! tag: String -> rk/RecordedRun
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "green\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))")
        repo (gk/initGitRepo! root "repeatRefusal" "repeat-refusal@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/rep" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "rep" tag) (badReplies)))
        form (str "(:agent :task \"fix subject\" :backend \"script/rep" tag "\" :root \""
               (c/escapeAsn root) "\" :mode \"scout\" :owns (\"subject.txt\") :budget 30 :contextTokens 8000)")
        code (m/main (list form))
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? journalName) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" journalName)) ""))
        cleaned (pathRemove root)]
    (rk/RecordedRun :exitCode code :journal text :sentLines (list)))

fn lineOf journal: String prefix: String -> String
  (optionOr (listHead (filter (fn [l] (stringStartsWith? l prefix)) (stringSplit journal "\n"))) "")

fn ! runTests -> Bool
  (let [run (recordedRun! "base")
        sent2 (lineOf run.journal "(:turn 2 :sent ")
        sent3 (lineOf run.journal "(:turn 3 :sent ")]
    (do
      (assert (stringContains? run.journal ":signal :repeatFailure") "three identical refused writes end with repeatFailure")
      (assert (not (stringContains? sent2 "do not resend")) "turn 2 has no repeat line after one failure")
      (assert (stringContains? sent3 "change the content, do not resend") "turn 3 carries the instruction to change the content")
      (assert (stringContains? sent3 ":repeated :times 2") "turn 3 names the repeat count")
      (assert (not (stringContains? sent3 ":refusal \\\"\\\"")) "turn 3 refusal text is not empty")
      (assert (stringContains? sent3 ":refusal") "turn 3 carries the refusal field")
      true))
