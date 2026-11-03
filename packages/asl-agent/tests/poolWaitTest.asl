(module aslAgent/tests/poolWaitTest
  :x [runTests]
  :i [(aslAgent/pool :a pl) (aslAgent/main :a m)])

; (:m :ref LEON-POOL-WIRE :do "a fake task runner sleeps 1 s in each task's child: tasks in different roots whose absolute :owns overlap wait for each other (the later starts after the earlier ends and names it in :waitedFor) while a disjoint task runs beside them; with a cap of 2, three disjoint tasks never all run at once")

fn ! sleeper! repoRoot: String t: pl/PoolTask -> m/MainResult
  (do (sleepMs 1000) (m/MainResult :stdout "(:agentReceipt :status :ok :phases () :unbacked 0)" :exitCode 0))

fn form root: String owns: String -> String
  (str "(:agent :task \"t\" :backend \"script/none\" :root \"" root "\" :owns (\"" owns "\"))")

fn field line: String key: String -> String
  (match (stringIndexOf line key)
    ((none) "")
    ((some i) (let [(rest (optionOr (stringSlice line (+ i (stringLength key)) (stringLength line)) ""))]
                (optionOr (stringSlice rest 0 (optionOr (stringIndexOf rest " ") (stringLength rest))) ""))))

fn slotAt summary: String idx: Int64 -> String
  (optionOr (listHead (filter (fn [(s String)] -> Bool (stringStartsWith? s (str ":idx " (stringFromInt64 idx) " "))) (stringSplit summary "(:slot "))) "")

fn stamp s: String key: String -> Int64
  (optionOr (stringToInt64 (field s key)) -1)

fn overlap? a: String b: String -> Bool
  (and (< (stamp a ":startNs ") (stamp b ":endNs ")) (< (stamp b ":startNs ") (stamp a ":endNs ")))

fn limits slots: Int64 -> pl/PoolLimits
  (pl/PoolLimits :slots slots :laneMs 0 :graceMs 30000 :maxDesc 64 :onOverlap "wait")

fn ! runTests -> Bool
  (let [(wait (pl/poolMainWith! (list (form "/tmp/poolWaitA" "/tmp/poolWaitShared/f.txt") (form "/tmp/poolWaitB" "/tmp/poolWaitShared")
                                      (form "/tmp/poolWaitC" "own.txt"))
                                "/" "/" (limits 0) sleeper!))
        (w0 (slotAt wait.stdout 0)) (w1 (slotAt wait.stdout 1)) (w2 (slotAt wait.stdout 2))
        (capped (pl/poolMainWith! (list (form "/tmp/poolCapA" "a") (form "/tmp/poolCapB" "b") (form "/tmp/poolCapC" "c"))
                                  "/" "/" (limits 2) sleeper!))
        (c0 (slotAt capped.stdout 0)) (c1 (slotAt capped.stdout 1)) (c2 (slotAt capped.stdout 2))]
    (do
      (assert (>= (stamp w1 ":startNs ") (stamp w0 ":endNs ")) "the task whose :owns overlaps a running task's starts only after that one ends")
      (assert (stringStartsWith? wait.stdout "(:poolReceipt :tasks 3 :admitted 3 :lanes 2 :ok 3 :failed 0 :refused 0 ") (str "an overlapping pair is admitted and queued, not refused: " wait.stdout))
      (assert (stringContains? w1 ":waitedFor (0) ") "the waiting slot names the task it waited for")
      (assert (not (stringContains? w0 ":waitedFor")) "the first task waited for nothing")
      (assert (and (overlap? w0 w2) (not (stringContains? w2 ":waitedFor"))) "the disjoint task runs beside the first without waiting")
      (assert (= capped.exitCode 0) "three disjoint tasks under a cap of 2 all end ok")
      (assert (overlap? c0 c1) "the first two disjoint tasks run at once")
      (assert (and (>= (stamp c2 ":startNs ") (min (stamp c0 ":endNs ") (stamp c1 ":endNs "))) (not (and (overlap? c0 c2) (overlap? c1 c2))))
        "the third starts only when a slot frees, so the cap is never exceeded")
      true))
