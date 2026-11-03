(module asl/agentLoop/tests/malformedReplyTest
  :x [runTests]
  :i [(asl/agentLoop/context :a ctx) (asl/agentLoop/core :a c) (asl/agentLoop/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (asl/agentLoop/tests/gitInitKit :a gk)])

; (:m :ref LEON-MALFORMED-TOOLTEXT :do "node2 stalls.asn, 8 rows: replies of broken tool-call wrapper text like <:step<</arg_value>>>> held no step and the run looped; the first is answered with the expected shape, the second in a row ends the run with stop cause malformedReply")

fn doneReplies -> (List String)
  (map (fn [_] "<:step<</arg_value>>>>") (range 0 5))

fn ! recordedRun! tag: String config: String -> rk/RecordedRun
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "green\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") config)
        repo (gk/initGitRepo! root "doneNoWrite" "done-no-write@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/done" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "done" tag) (doneReplies)))
        form (str "(:agent :task \"fix subject\" :backend \"script/done" tag "\" :root \""
               (c/escapeAsn root) "\" :mode \"scout\" :owns (\"subject.txt\") :budget 30 :contextTokens 8000)")
        code (m/main (list form))
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? journalName) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" journalName)) ""))
        cleaned (pathRemove root)]
    (rk/RecordedRun :exitCode code :journal text :sentLines (list)))

fn replyCount journal: String -> Int64
  (listLength (filter (fn [l] (and (stringStartsWith? l "(:turn ") (stringContains? l " :reply \""))) (stringSplit journal "\n")))

fn ! runTests -> Bool
  (let [run (recordedRun! "base" "(:aslConfig :agentLoop (:specCheck false))")
        sent2 (optionOr (listHead (filter (fn [l] (stringStartsWith? l "(:turn 2 :sent ")) (stringSplit run.journal "\n"))) "")]
    (do
      (assert (stringContains? run.journal ":signal :malformedReply") "the second broken-wrapper reply in a row ends the run with malformedReply")
      (assert (stringContains? run.journal ":alias \"") "the signal row carries the alias field")
      (assert (= (replyCount run.journal) 2) (str "the run ends after two replies, got " (stringFromInt64 (replyCount run.journal))))
      (assert (stringContains? sent2 "ERR_NO_STEP") "the first broken reply is answered with the expected step shape")
      true))
