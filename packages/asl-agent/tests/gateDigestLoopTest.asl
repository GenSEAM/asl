(module aslAgent/tests/gateDigestLoopTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

fn writeReply content: String -> String
  (str "(:step :op \"write\" :file \"subject.txt\" :content \"" content "\\n\")")

fn ! loopRun! tag: String replies: (List String) -> (List String)
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "green\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))")
        runsLog (str root ".gateRuns")
        wroteGate (fileWrite (str root ".gate.sh") (str "echo run >> " runsLog "\nif grep -q done " root "/subject.txt; then echo '1 assertion(s) executed (1 passed)'; else echo '1 assertion(s) executed (0 passed, 1 failed)'; exit 1; fi\n"))
        repo (gk/initGitRepo! root "gateDigest" "gate-digest@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/digest" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "digest" tag) replies))
        form (str "(:agent :task \"fix subject\" :backend \"script/digest" tag "\" :root \""
               (c/escapeAsn root) "\" :mode \"scout\" :owns (\"subject.txt\") :gates (\"sh " (c/escapeAsn root) ".gate.sh\") :budget 30 :contextTokens 8000)")
        code (m/main (list form))
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? journalName) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" journalName)) ""))
        runs (resultOr (fileReadString runsLog) "")
        cleaned (pathRemove root)]
    (list text runs))

fn runCount runs: String -> Int64
  (listLength (filter (fn [l] (= l "run")) (stringSplit runs "\n")))

fn ! runTests -> Bool
  (let [same (loopRun! "same" (list (writeReply "blue") (writeReply "blue") "(:step :op \"done\")"))
        sameJournal (optionOr (listGet same 0) "")
        sameRuns (runCount (optionOr (listGet same 1) ""))
        moved (loopRun! "moved" (list (writeReply "blue") (writeReply "teal") "(:step :op \"done\")"))
        movedJournal (optionOr (listGet moved 0) "")
        movedRuns (runCount (optionOr (listGet moved 1) ""))]
    (do
      (assert (stringContains? sameJournal ":gateReuse :digest") "a rewrite that leaves the owned tree unchanged logs :gateReuse")
      (assert (= sameRuns 2) (str "baseline plus turn 1 only: the unchanged second write and done reuse the result, gate ran " (stringFromInt64 sameRuns) " times"))
      (refute (stringContains? movedJournal "(:turn 2 :gateReuse") "turn 2 changed the owned tree, so it does not reuse")
      (assert (= movedRuns 3) (str "baseline plus both writes: a changed tree reruns the gate, gate ran " (stringFromInt64 movedRuns) " times"))
      true))
