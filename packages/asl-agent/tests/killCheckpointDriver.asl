(module aslAgent/tests/killCheckpointDriver
  :x [main]
  :i [(aslAgent/main :a m)
      (aslAgent/core :a c)
      (aslHarness/tests/agentLoopRecorderKit :a rk)
      (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-TIMEOUT-NO-RECEIPT :do "a scripted Leon run for killCheckpointTest to start under bounded.asl: turn 1 edits task.txt, turn 2 runs a long sleep, so an outer kill lands while the run is mid-turn with one persisted edit; argv is the fixture root, created by the test")
fn ! main args: (List String) -> (Result Int64 String)
  (let [root (optionOr (listHead args) "")
        _repo (and (ok? (fileWrite (str root "/task.txt") "before\n"))
                   (gk/initGitRepoWith! root "killCheckpoint" "kill-checkpoint@example.invalid" (list "task.txt")))
        edit "(:step :op \"edit\" :file \"task.txt\" :old \"before\" :new \"after\")"
        stall "(:step :op \"run\" :cmd \"sleep 90\")"
        _fix (dirCreate (str root "/tests/fixtures/agentLoop/mvp"))
        _fx (fileWrite (str root "/tests/fixtures/agentLoop/mvp/kc.asn") (rk/scriptFixtureTextFromReplies! "kc" (list edit stall "(:done)")))
        form (str "(:agent :task \"Edit task.txt, then run the slow check.\" :backend \"script/kc\" :root \"" (c/escapeAsn root)
                  "\" :mode \"scout\" :owns (\"task.txt\") :budget 6 :contextTokens 8000)")
        code (m/main (list form))]
    (ok code))
