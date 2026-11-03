(module aslAgent/tests/poolHoldTest
  :x [runTests]
  :i [(aslAgent/pool :a pl) (aslAgent/poolChannel :a ch) (aslAgent/main :a m)])

; (:m :ref LEON-POOL-WAIT-DEADLOCK :do "tasks 1 and 2 share a root, so they form one lane and task 2 waits for task 1; task 0 runs in its own lane and asks task 2 while it is still queued: the router holds the ask until task 2 starts and serves it; task 1 asks task 2, queued behind it in its own lane, and is refused with ERR_PEER_QUEUED_BEHIND at once instead of waiting out its timeout")

fn ! errOf r: (Result String String) -> String
  (match r ((ok b) (str "ok:" b)) ((err e) e))

fn ! serve! dir: String idx: Int64 deadline: Int64 -> Int64
  (let [(qs (ch/asks! dir idx))]
    (cond
      ((not (listEmpty? qs)) (fold (fn [(n Int64) (q ch/PoolMsg)] -> Int64 (if (ok? (ch/answer! dir idx q (str "(:a 7 :to " (stringFromInt64 q.from) ")"))) (+ n 1) n)) 0 qs))
      ((> (monotonicNs) deadline) 0)
      (else (do (sleepMs 20) (serve! dir idx deadline)))))

fn ! behind! dir: String -> String
  (let [(t0 (monotonicNs))
        (r (errOf (ch/ask! dir 1 2 "(:q 2)" 20000)))
        (quick (< (- (monotonicNs) t0) 10000000000))
        (_ (sleepMs 1500))]
    (str r (if quick " :quick true" " :quick false")))

fn ! runner! repoRoot: String t: pl/PoolTask -> m/MainResult
  (m/MainResult :exitCode 0
    :stdout (cond
              ((= t.idx 0) (str "(:agentReceipt :status :ok :held " (errOf (ch/ask! t.chan 0 2 "(:q 0)" 30000)) ")"))
              ((= t.idx 1) (str "(:agentReceipt :status :ok :behind " (behind! t.chan) ")"))
              (else (str "(:agentReceipt :status :ok :served " (stringFromInt64 (serve! t.chan 2 (+ (monotonicNs) 20000000000))) ")"))))

fn form root: String -> String
  (str "(:agent :task \"t\" :backend \"script/none\" :root \"" root "\" :owns (\"x\"))")

fn slotAt summary: String idx: Int64 -> String
  (optionOr (listHead (filter (fn [(s String)] -> Bool (stringStartsWith? s (str ":idx " (stringFromInt64 idx) " "))) (stringSplit summary "(:slot "))) "")

fn ! runTests -> Bool
  (let [(res (pl/poolMainWith! (list (form "/tmp/poolHoldA") (form "/tmp/poolHoldB") (form "/tmp/poolHoldB")) "/" "/" (pl/defaultLimits) runner!))
        (s0 (slotAt res.stdout 0)) (s1 (slotAt res.stdout 1)) (s2 (slotAt res.stdout 2))]
    (do
      (assert (stringContains? s0 ":held ok:(:a 7 :to 0)") (str "task 0's ask to the queued task 2 is held until task 2 starts and answers it: " s0))
      (assert (stringContains? s2 ":served 1)") (str "task 2 served the held ask once it started: " s2))
      (assert (stringContains? s1 ":behind ERR_PEER_QUEUED_BEHIND :quick true") (str "an ask to a task queued behind the asker in its own lane is refused at once: " s1))
      (assert (= res.exitCode 0) (str "the pool ends ok: " res.stdout))
      true))
