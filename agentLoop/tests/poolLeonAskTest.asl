(module asl/agentLoop/tests/poolLeonAskTest
  :x [runTests]
  :i [(asl/agentLoop/pool :a pl) (aslHarness/tests/agentLoopRecorderKit :a rk) (asl/agentLoop/core :a c) (asl/agentLoop/tests/gitInitKit :a gk)])

; (:m :ref LEON-POOL-ASK-OP :do "end to end through Leon's loop: two pool tasks run mainWithRoots against script fixtures (the fake worker); task 0 replies (:ask :to 1 :body (...)), task 1 runs a slow step, sees the ask as a (:poolAsks ...) observation after that turn, and replies (:answer :to 0 :body (...)); task 0's journal holds the (:ask) op receipt carrying task 1's answer")

fn ! repo! tag: String replies: (List String) -> String
  (let [(root (rk/freshRecorderRoot! tag))
        (seeded (and (ok? (fileWrite (str root "/subject.txt") "before\n")) (and (gk/initGitRepo! root "poolLeonAskTest" "pool-leon-ask@example.invalid")
                     (and (ok? (dirCreate (str root "/tests/fixtures/agentLoop/mvp")))
                          (ok? (fileWrite (str root "/tests/fixtures/agentLoop/mvp/" tag ".asn") (rk/scriptFixtureTextFromReplies! tag replies)))))))]
    (if seeded root ""))

fn task tag: String root: String -> String
  (str "(:agent :task \"Talk to the other pool task.\" :backend \"script/" tag "\" :root \"" (c/escapeAsn root)
       "\" :owns (\"out.txt\") :mode \"implement\" :budget 4 :contextTokens 8000)")

fn slotAt summary: String idx: Int64 -> String
  (optionOr (listHead (filter (fn [(x String)] -> Bool (stringStartsWith? x (str ":idx " (stringFromInt64 idx) " "))) (stringSplit summary "(:slot "))) "")

fn journalOf slot: String -> String
  (match (stringIndexOf slot ":journal \"")
    ((none) "")
    ((some i) (let [(rest (c/sliceOf slot (+ i 10) (stringLength slot)))]
                (c/sliceOf rest 0 (optionOr (stringIndexOf rest "\"") 0)))))

fn ! journalText! root: String slot: String -> String
  (let [(j (journalOf slot))]
    (if (stringEmpty? j) "" (resultOr (fileReadString (if (stringStartsWith? j "/") j (str root "/" j))) "")))

fn ! runTests -> Bool
  (let [(here (resultOr (realPath ".") "."))
        (a (repo! "poolLeonAskA" (list "(:ask :to 1 :body (:q \"x?\"))" "(:done)")))
        (b (repo! "poolLeonAskB" (list "(:step :op \"run\" :cmd \"sleep 3\")" "(:answer :to 0 :body (:a 42))" "(:done)")))
        (res (pl/poolMainWith! (list (task "poolLeonAskA" a) (task "poolLeonAskB" b)) here here (pl/defaultLimits) pl/runTask!))
        (ja (journalText! a (slotAt res.stdout 0)))
        (jb (journalText! b (slotAt res.stdout 1)))
        (cleaned (and (ok? (pathRemove a)) (ok? (pathRemove b))))]
    (do
      (assert (stringContains? ja "(:ask :to 1 :status :ok :answer (:a 42))") (str "task 0's (:ask) op receipt in its journal carries task 1's answer: " res.stdout " JOURNAL " ja))
      (assert (stringContains? jb "(:poolAsks ((:ask :id ") (str "task 1 got the ask as a (:poolAsks) observation between turns: " res.stdout " JOURNAL " jb))
      (assert (stringContains? jb " :to 0 :status :ok)") (str "task 1's (:answer) op receipt shows it went back to task 0: " jb))
      (assert cleaned "fixture roots removed")
      true))
