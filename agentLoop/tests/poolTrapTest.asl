(module asl/agentLoop/tests/poolTrapTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (asl/agentLoop/pool :a pl) (asl/agentLoop/main :a m) (asl/agentLoop/core :a c) (asl/agentLoop/tests/gitInitKit :a gk)])

; (:m :ref LEON-POOL-TRAP :do "three lanes, the runner traps (Int64 overflow) on the task whose form names TRAPME: that task's child dies alone and its slot reads :failed :trap true, while the two real script tasks report ok; with the trap boundary gone the trap ends the whole pool and no summary is printed")

fn ! initRepo! root: String -> Bool
  (and (ok? (fileWrite (str root "/subject.txt") "before\n"))
    (gk/initGitRepo! root "poolTrapTest" "pool-trap-test@example.invalid"))

fn ! fixture! root: String id: String reply: String -> Bool
  (and (ok? (dirCreate (str root "/tests/fixtures/agentLoop/mvp")))
    (ok? (fileWrite (str root "/tests/fixtures/agentLoop/mvp/" id ".asn") (rk/scriptFixtureTextFromReplies! id (list reply)))))

fn form root: String id: String task: String -> String
  (str "(:agent :task \"" task "\" :backend \"script/" id "\" :root \"" (c/escapeAsn root)
       "\" :owns (\"out.txt\") :mode \"scout\" :budget 3 :contextTokens 8000)")

fn ! trapping! repoRoot: String t: pl/PoolTask -> m/MainResult
  (if (stringContains? t.form "TRAPME")
    (m/MainResult :stdout (str "never " (+ (stringLength t.form) 9223372036854775807)) :exitCode 0)
    (m/mainWithRoots (list t.form) repoRoot t.root))

fn ! exists?! path: String -> Bool
  (match (fileStat path) ((ok st) st.isFile) ((err _) false))

fn slotAt summary: String idx: Int64 -> String
  (optionOr (listHead (filter (fn [(s String)] -> Bool (stringStartsWith? s (str ":idx " (stringFromInt64 idx) " ")))
                              (stringSplit summary "(:slot ")))
            "")

fn ! runTests -> Bool
  (let [(repoRoot (resultOr (realPath ".") "."))
        (roots (map (fn [(i Int64)] -> String (rk/freshRecorderRoot! (str "poolTrap" (stringFromInt64 i)))) (range 0 3)))
        (reply "(:step :op \"run\" :cmd \"sleep 1; echo done > out.txt\")\n(:done)")
        (ready (listAll? (fn [(r String)] -> Bool (and (initRepo! r) (fixture! r "poolTrap" reply))) roots))
        (tasks (map (fn [(p (Pair Int64 String))] -> String
                      (form (pairSecond p) "poolTrap" (if (= (pairFirst p) 1) "TRAPME then finish." "Run the step, then finish.")))
                    (zip (range 0 3) roots)))
        (res (pl/poolMainWith! tasks repoRoot repoRoot (pl/defaultLimits) trapping!))
        (s0 (slotAt res.stdout 0)) (s1 (slotAt res.stdout 1)) (s2 (slotAt res.stdout 2))
        (written (and (exists?! (str (optionOr (listGet roots 0) "") "/out.txt")) (exists?! (str (optionOr (listGet roots 2) "") "/out.txt"))))
        (cleaned (listAll? (fn [(r String)] -> Bool (ok? (pathRemove r))) roots))]
    (do
      (assert ready "three fixture repos written")
      (assert (stringStartsWith? res.stdout "(:poolReceipt :tasks 3 :admitted 3 :lanes 3 :ok 2 :failed 1 ") (str "the pool survives the trap and counts it as one failure: " res.stdout))
      (assert (stringContains? s1 ":status :failed :trap true :exit ") (str "the trapped slot reads :failed :trap true: " s1))
      (assert (stringContains? s1 "ERR_TRAP") "the trapped slot's receipt names ERR_TRAP")
      (assert (stringContains? s1 "ERR_INT_OVERFLOW") "the trapped slot's receipt carries the trap's last log line")
      (assert (and (stringContains? s0 ":status :ok :exit 0") (stringContains? s2 ":status :ok :exit 0")) "the other two lanes report ok slots")
      (assert written "the other two tasks wrote their files")
      (assert (= res.exitCode 1) "a trapped task makes the pool exit 1")
      (assert cleaned "fixture roots removed")
      true))
