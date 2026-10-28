(module asl/agentLoop/tests/poolDeadlineTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (asl/agentLoop/pool :a pl) (asl/agentLoop/core :a c) (asl/agentLoop/tests/gitInitKit :a gk) (asl-tools/fleet/run :a fr)])

; (:m :ref LEON-POOL-BOUND :do "three lanes: lane 0 hangs past its task deadline (:wallBudget 3 plus 1 s grace), lane 2 hangs past the 30 s lane deadline with a second task queued behind it, lane 1 is an ordinary task; the pool ends near the lane deadline with the hung slots :timeout, the queued one never started and the hung run steps killed, while lane 1 reports ok; without the deadlines the hung steps run their full 117 s and end ok")

fn ! initRepo! root: String -> Bool
  (and (ok? (fileWrite (str root "/subject.txt") "before\n"))
    (gk/initGitRepo! root "poolDeadlineTest" "pool-deadline-test@example.invalid"))

fn ! fixture! root: String id: String cmd: String -> Bool
  (and (ok? (dirCreate (str root "/tests/fixtures/agentLoop/mvp")))
    (ok? (fileWrite (str root "/tests/fixtures/agentLoop/mvp/" id ".asn")
                    (rk/scriptFixtureTextFromReplies! id (list (str "(:step :op \"run\" :cmd \"" cmd "\")\n(:done)"))))))

fn form root: String id: String owns: String extra: String -> String
  (str "(:agent :task \"Run the step, then finish.\" :backend \"script/" id "\" :root \"" (c/escapeAsn root)
       "\" :owns (\"" owns "\") :mode \"scout\" :budget 3 :contextTokens 8000" extra ")")

fn slotAt summary: String idx: Int64 -> String
  (optionOr (listHead (filter (fn [(s String)] -> Bool (stringStartsWith? s (str ":idx " (stringFromInt64 idx) " ")))
                              (stringSplit summary "(:slot ")))
            "")

fn ! exists?! path: String -> Bool
  (match (fileStat path) ((ok st) st.isFile) ((err _) false))

fn ! hungLeft! -> Bool
  (stringContains? (fr/runOneLimited (fr/job (list "ps" "-A" "-o" "command=") "/" (fr/childEnv (list))) (fr/limits 10 8)).out "sleep 117")

fn ! runTests -> Bool
  (let [(repoRoot (resultOr (realPath ".") "."))
        (a (rk/freshRecorderRoot! "poolDeadlineA"))
        (b (rk/freshRecorderRoot! "poolDeadlineB"))
        (d (rk/freshRecorderRoot! "poolDeadlineC"))
        (ready (and (and (initRepo! a) (and (initRepo! b) (initRepo! d)))
                    (and (fixture! a "poolHang" "sleep 117; echo late > late.txt")
                         (and (fixture! b "poolQuick" "sleep 1; echo done > out.txt")
                              (and (fixture! d "poolHang" "sleep 117; echo late > late.txt") (fixture! d "poolQuick" "sleep 1; echo done > out.txt"))))))
        (res (pl/poolMainWith! (list (form a "poolHang" "late.txt" " :wallBudget 3") (form b "poolQuick" "out.txt" "")
                                     (form d "poolHang" "late.txt" "") (form d "poolQuick" "out.txt" ""))
                               repoRoot repoRoot (pl/PoolLimits :slots 0 :laneMs 30000 :graceMs 1000 :maxDesc 64 :onOverlap "wait") pl/runTask!))
        (s0 (slotAt res.stdout 0)) (s1 (slotAt res.stdout 1)) (s2 (slotAt res.stdout 2)) (s3 (slotAt res.stdout 3))
        (wall (optionOr (stringToInt64 (optionOr (listHead (stringSplit (optionOr (listGet (stringSplit res.stdout ":wallMs ") 1) "") " ")) "")) -1))
        (quickWrote (exists?! (str b "/out.txt")))
        (left (hungLeft!))
        (late (or (exists?! (str a "/late.txt")) (exists?! (str d "/late.txt"))))
        (cleaned (and (ok? (pathRemove a)) (and (ok? (pathRemove b)) (ok? (pathRemove d)))))]
    (do
      (println (str "pool deadline wallMs " wall))
      (assert ready "three fixture repos written")
      (assert (stringContains? s0 ":status :timeout :deadline :task :exit -1") (str "the lane 0 task is killed at its own deadline: " s0))
      (assert (stringContains? s2 ":status :timeout :deadline :lane :exit -1") (str "the lane 2 task is killed at the lane deadline: " s2))
      (assert (stringContains? s3 ":status :timeout :deadline :lane :started false") (str "the task queued behind it never starts: " s3))
      (assert (stringContains? s1 ":status :ok :exit 0") (str "the ordinary lane completes ok: " s1))
      (assert quickWrote "the ordinary task wrote its file")
      (assert (not left) "no hung run step survives the pool")
      (assert (not late) "no hung run step got to write its late file")
      (assert (and (> wall 0) (< wall 60000)) "the pool ends near the 30 s lane deadline, far below the 117 s hang")
      (assert (= res.exitCode 1) "timeouts make the pool exit 1")
      (assert cleaned "fixture roots removed")
      true))
