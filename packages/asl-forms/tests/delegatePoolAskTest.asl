(module asl-forms/tests/delegatePoolAskTest
  :x [runTests]
  :i [(asl-forms/delegate :a d) (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/core :a c) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-POOL-ASK-WIRE :do "end to end through (:agent :pool ...): runDelegate starts the pool binary, which forks two Leon tasks against script fixtures (no model); the tasks name no mode and no gates; task 0's only reply is (:ask :to 1 :body (...)), so the run goes on to execute it instead of ending on it as ad-hoc findings (LEON-POOL-ASK-SCOUT); task 1 runs a slow step, gets the ask as a (:poolAsks ...) observation and replies (:answer :to 0 :body (...)); task 0's journal holds the ask receipt carrying that answer")

fn ! repo! tag: String replies: (List String) -> String
  (let [(root (rk/freshRecorderRoot! tag))
        (seeded (and (ok? (fileWrite (str root "/subject.txt") "before\n"))
                     (and (gk/initGitRepo! root "delegatePoolAskTest" "delegate-pool-ask@example.invalid")
                          (and (ok? (dirCreate (str root "/tests/fixtures/agentLoop/mvp")))
                               (ok? (fileWrite (str root "/tests/fixtures/agentLoop/mvp/" tag ".asn") (rk/scriptFixtureTextFromReplies! tag replies)))))))]
    (if seeded root ""))

fn task tag: String root: String -> String
  (str "(:task \"Talk to the other pool task.\" :backend \"script/" tag "\" :root \"" (c/escapeAsn root)
       "\" :owns (\"out.txt\") :budget 4 :contextTokens 8000)")

; (:m :do "the slot's :journal path, quoted plain or escaped depending on how deep the receipt is nested")
fn journalOf line: String marker: String -> String
  (match (stringIndexOf line marker)
    ((none) "")
    ((some i)
      (let [(rest (c/sliceOf line (+ i (stringLength marker)) (stringLength line)))
            (j (match (stringIndexOf rest ":journal ") ((some k) (c/sliceOf rest (+ k 9) (stringLength rest))) ((none) "")))
            (bare (stringReplace (c/sliceOf j 0 (optionOr (stringIndexOf j " ") 0)) "\\" ""))]
        (stringReplace bare "\"" ""))))

fn ! journalText! root: String rel: String -> String
  (if (stringEmpty? rel) "" (resultOr (fileReadString (str root "/" rel)) ""))

fn ! runTests -> Bool
  (let [(here (resultOr (realPath ".") "."))
        (a (repo! "poolAskA" (list "(:ask :to 1 :body (:q \"x?\"))" "(:done)")))
        (b (repo! "poolAskB" (list "(:step :op \"run\" :cmd \"sleep 3\")" "(:answer :to 0 :body (:a 42))" "(:done)")))
        (step (str "(:agent :pool (" (task "poolAskA" a) " " (task "poolAskB" b) "))"))
        (out (d/runDelegate (d/DelegateCtx :rootDir here :binDir (str here "/bin") :wsDir here) 7 "agent" (mapEmpty) (list) step))
        (ja (journalText! a (journalOf out.line ":idx 0 ")))
        (jb (journalText! b (journalOf out.line ":idx 1 ")))
        (cleaned (and (ok? (pathRemove a)) (ok? (pathRemove b))))]
    (do
      (assert (stringContains? out.line "(:poolReceipt :tasks 2 :admitted 2 :lanes 2 ") (str "the (:agent :pool ...) step ran both tasks in the pool: " out.line))
      (assert (stringContains? ja "(:ask :to 1 :status :ok :answer (:a 42))") (str "task 0's (:ask) op receipt in its journal carries task 1's answer: " out.line " JOURNAL " ja))
      (assert (not (stringContains? (str out.line ja) "(:findings (:ask")) (str "an (:ask) op is not taken as an ad-hoc finding: " out.line))
      (assert (stringContains? jb "(:poolAsks ((:ask :id ") (str "task 1 got the ask as a (:poolAsks) observation between turns: " jb))
      (assert (stringContains? jb " :to 0 :status :ok)") (str "task 1's (:answer) op receipt shows it went back to task 0: " jb))
      (assert cleaned "fixture roots removed")
      true))
