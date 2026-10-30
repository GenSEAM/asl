(module asl/agentLoop/tests/poolAskTest
  :x [runTests]
  :i [(asl/agentLoop/pool :a pl) (asl/agentLoop/poolChannel :a ch) (asl/agentLoop/main :a m)])

; (:m :ref LEON-POOL-WIRE :do "three tasks under a fake runner: task 0 asks task 1 an ASN question and gets its ASN answer back through the pool's router, and is told ERR_PEER_NOT_RUNNING for itself and an absent peer and ERR_ASK_NOT_ASN for plain text; task 1 serves one ask; task 2 asks an absent peer until the router answers ERR_ASK_LIMIT; with the router off the ask times out")

fn ! errOf r: (Result String String) -> String
  (match r ((ok b) (str "ok:" b)) ((err e) e))

fn ! serve! dir: String idx: Int64 deadline: Int64 -> Int64
  (let [(qs (ch/asks! dir idx))]
    (cond
      ((not (listEmpty? qs)) (fold (fn [(n Int64) (q ch/PoolMsg)] -> Int64 (if (ok? (ch/answer! dir idx q (str "(:a 42 :to " (stringFromInt64 q.from) " :q " q.body ")"))) (+ n 1) n)) 0 qs))
      ((> (monotonicNs) deadline) 0)
      (else (do (sleepMs 20) (serve! dir idx deadline)))))

fn ! askMany! dir: String n: Int64 last: String -> String
  (if (= n 0) last (askMany! dir (- n 1) (errOf (ch/ask! dir 2 7 "(:q 1)" 2000))))

fn ! runner! repoRoot: String t: pl/PoolTask -> m/MainResult
  (m/MainResult :exitCode 0
    :stdout (cond
              ((= t.idx 0) (str "(:agentReceipt :status :ok :answer " (errOf (ch/ask! t.chan 0 1 "(:q \"x?\")" 20000))
                                " :self " (errOf (ch/ask! t.chan 0 0 "(:q 1)" 2000))
                                " :absent " (errOf (ch/ask! t.chan 0 9 "(:q 1)" 2000))
                                " :plain " (errOf (ch/ask! t.chan 0 1 "hello" 2000)) ")"))
              ((= t.idx 1) (str "(:agentReceipt :status :ok :served " (stringFromInt64 (serve! t.chan 1 (+ (monotonicNs) 20000000000))) ")"))
              (else (str "(:agentReceipt :status :ok :last " (askMany! t.chan (+ (ch/maxAsks) 1) "") ")"))))

fn form root: String -> String
  (str "(:agent :task \"t\" :backend \"script/none\" :root \"" root "\" :owns (\"x\"))")

fn slotAt summary: String idx: Int64 -> String
  (optionOr (listHead (filter (fn [(s String)] -> Bool (stringStartsWith? s (str ":idx " (stringFromInt64 idx) " "))) (stringSplit summary "(:slot "))) "")

fn ! runTests -> Bool
  (let [(res (pl/poolMainWith! (list (form "/tmp/poolAskA") (form "/tmp/poolAskB") (form "/tmp/poolAskC")) "/" "/" (pl/defaultLimits) runner!))
        (s0 (slotAt res.stdout 0)) (s1 (slotAt res.stdout 1)) (s2 (slotAt res.stdout 2))]
    (do
      (assert (ch/asnForm? "(:q \"a (b\" :n 1)") "a form with a ( inside a string is one ASN form")
      (assert (not (ch/asnForm? "(:q 1) (:r 2)")) "two forms are not one")
      (assert (not (ch/asnForm? "(:q\n1)")) "a multi-line form is not a wire frame")
      (assert (match (ch/parseMsg (ch/msgLine (ch/PoolMsg :kind "ask" :id "0x5" :from 0 :to 1 :error "" :body "(:q \" :body \")")))
                ((some m) (and (= m.body "(:q \" :body \")") (and (= m.from 0) (= m.to 1)))) ((none) false))
        "a message line round-trips, a :body inside the body included")
      (assert (= res.exitCode 0) (str "the pool ends ok: " res.stdout))
      (assert (stringContains? s0 ":answer ok:(:a 42 :to 0 :q (:q \\\"x?\\\")) ") (str "task 0 gets task 1's ASN answer to its question: " s0))
      (assert (stringContains? s1 ":served 1)") "task 1 served exactly one ask")
      (assert (stringContains? s0 ":self ERR_PEER_NOT_RUNNING ") "an ask to oneself is refused by the router")
      (assert (stringContains? s0 ":absent ERR_PEER_NOT_RUNNING ") "an ask to a task that is not running is refused by the router")
      (assert (stringContains? s0 ":plain ERR_ASK_NOT_ASN)") "a plain-text body never leaves the task")
      (assert (stringContains? s2 ":last ERR_ASK_LIMIT)") "the ask past maxAsks is refused with ERR_ASK_LIMIT")
      true))
