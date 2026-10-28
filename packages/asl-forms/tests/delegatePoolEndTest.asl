(module asl-forms/tests/delegatePoolEndTest
  :x [runTests]
  :i [(asl-forms/delegate :a d) (aslHarness/tests/agentLoopRecorderKit :a rk) (asl/agentLoop/core :a c) (asl/agentLoop/tests/gitInitKit :a gk)])

; (:m :ref LEON-POOL-WIRE :do "end to end: runDelegate on an (:agent :pool ...) step builds and starts the asl/agentLoop/pool binary through fleet/run runGuarded, the pool forks its two task children through forkLimited!, and each child runs Leon's loop against a script/<id> fixture (the fake worker: no gateway, no model); the step comes back with one (:poolReceipt ...) and both tasks' files are on disk")

fn ! repo! tag: String -> String
  (let [(root (rk/freshRecorderRoot! tag))
        (seeded (and (ok? (fileWrite (str root "/subject.txt") "before\n"))
                     (and (gk/initGitRepo! root "delegatePoolEndTest" "delegate-pool-end@example.invalid")
                          (and (ok? (dirCreate (str root "/tests/fixtures/agentLoop/mvp")))
                               (ok? (fileWrite (str root "/tests/fixtures/agentLoop/mvp/poolEnd.asn")
                                               (rk/scriptFixtureTextFromReplies! "poolEnd" (list "(:step :op \"run\" :cmd \"echo done > out.txt\")\n(:done)"))))))))]
    (if seeded root ""))

fn task root: String -> String
  (str "(:task \"Run the step, then finish.\" :backend \"script/poolEnd\" :root \"" (c/escapeAsn root)
       "\" :owns (\"out.txt\") :mode \"scout\" :budget 3 :contextTokens 8000)")

fn ! exists?! path: String -> Bool
  (match (fileStat path) ((ok st) st.isFile) ((err _) false))

fn ! runTests -> Bool
  (let [(here (resultOr (realPath ".") "."))
        (a (repo! "poolEndA"))
        (b (repo! "poolEndB"))
        (step (str "(:agent :pool (" (task a) " " (task b) "))"))
        (out (d/runDelegate (d/DelegateCtx :rootDir here :binDir (str here "/bin") :wsDir here) 7 "agent" (mapEmpty) (list) step))
        (wroteA (exists?! (str a "/out.txt")))
        (wroteB (exists?! (str b "/out.txt")))
        (cleaned (and (ok? (pathRemove a)) (ok? (pathRemove b))))]
    (do
      (assert (and (not (stringEmpty? a)) (not (stringEmpty? b))) "two fixture repos with script fixtures")
      (assert (stringContains? out.line "(:step :id 7 :op \"agent\" :status \"ok\" :pool true :receipt (:poolReceipt :tasks 2 :admitted 2 :lanes 2 :ok 2 :failed 0 :refused 0 ")
        (str "the pool step returns one pool receipt with two ok tasks: " out.line))
      (assert (= (listLength (stringSplit out.line "(:slot ")) 3) "the receipt carries two slots")
      (assert (stringContains? out.line "(:agentReceipt :status :ok") "the slots carry the tasks' own Leon receipts")
      (assert (and wroteA wroteB) "each task's run step wrote its file in its own root")
      (assert (= out.errCount 0) "an all-ok pool step counts no error")
      (assert cleaned "fixture roots removed")
      true))
