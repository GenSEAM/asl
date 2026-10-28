(module asl/agentLoop/tests/poolOpsTest
  :x [runTests]
  :i [(asl/agentLoop/pool :a pl) (asl/agentLoop/poolOps :a po) (asl/agentLoop/core :a c) (asl/agentLoop/main :a m)])

; (:m :ref LEON-POOL-ASK-OP :do "two fake workers run Leon's reply-op path in a pool: each scripted reply goes through c/parseReply, and every op poolOp? claims runs through poolOpReceipt!; task 0 replies (:ask :to 1 :body (...)) and its op receipt carries task 1's answer through the reactor; task 1 polls servePending! between turns, reads the asker from the (:poolAsks ...) observation and replies (:answer :to <from> :body (...))")

fn agentForm t: pl/PoolTask -> String
  (str "(:agent :task \"t\" :poolChan \"" t.chan "\" :poolIdx " (stringFromInt64 t.idx) " :root \"/tmp/x\")")

fn ! turn! self: (Option po/PoolSelf) reply: String -> String
  (stringJoin (map (fn [(op (List (Pair String c/KvVal)))] -> String (po/poolOpReceipt! self op))
                   (filter po/poolOp? (c/parseReply reply))) " ")

fn ! serveTurns! self: (Option po/PoolSelf) deadline: Int64 -> String
  (let [(obs (po/servePending! self))]
    (cond
      ((not (stringEmpty? obs)) (str obs " -> " (turn! self (str "(:answer :to " (po/formField obs "from") " :body (:a 42 :seen \"(\"))"))))
      ((> (monotonicNs) deadline) "no ask came")
      (else (do (sleepMs 20) (serveTurns! self deadline)))))

fn ! runner! repoRoot: String t: pl/PoolTask -> m/MainResult
  (let [(self (po/poolSelfOf (agentForm t)))]
    (m/MainResult :exitCode 0
      :stdout (if (= t.idx 0)
                (str "(:agentReceipt :status :ok :turn1 " (turn! self "(:ask :to 1 :body (:q \"x?\" :to 9))") " :turn2 " (turn! self "(:done)") ")")
                (str "(:agentReceipt :status :ok :turns " (serveTurns! self (+ (monotonicNs) 20000000000)) ")"))))

fn form root: String -> String
  (str "(:agent :task \"t\" :backend \"script/none\" :root \"" root "\" :owns (\"x\"))")

fn slotAt summary: String idx: Int64 -> String
  (optionOr (listHead (filter (fn [(s String)] -> Bool (stringStartsWith? s (str ":idx " (stringFromInt64 idx) " "))) (stringSplit summary "(:slot "))) "")

fn ! runTests -> Bool
  (let [(res (pl/poolMainWith! (list (form "/tmp/poolOpsA") (form "/tmp/poolOpsB")) "/" "/" (pl/defaultLimits) runner!))
        (s0 (slotAt res.stdout 0)) (s1 (slotAt res.stdout 1))
        (outside (turn! none "(:ask :to 1 :body (:q 1))"))
        (noAsk (turn! (po/poolSelf "/tmp/poolOpsNone" 0) "(:answer :to 1 :body (:a 1))"))]
    (do
      (assert (stringContains? s0 ":turn1 (:ask :to 1 :status :ok :answer (:a 42 :seen \\\"(\\\")) ") (str "task 0's (:ask) op receipt is task 1's answer, routed by the reactor: " s0))
      (assert (stringContains? s0 ":turn2 )") (str "(:done) is not a pool op: " s0))
      (assert (stringContains? s1 ":from 0 :body (:q \\\"x?\\\" :to 9))") (str "task 1 saw the ask as a (:poolAsks) observation naming its asker and body: " s1))
      (assert (stringContains? s1 " -> (:answer :id \\\"0x") (str "task 1's (:answer) op names the ask it answered: " s1))
      (assert (stringContains? s1 " :to 0 :status :ok)") (str "and went back to task 0, not to the :to inside the ask body: " s1))
      (assert (= outside "(:ask :to 1 :status :rejected :error ERR_NOT_IN_POOL)") (str "outside a pool an (:ask) op is refused: " outside))
      (assert (= noAsk "(:answer :to 1 :status :rejected :error ERR_ANSWER_NO_ASK)") (str "an (:answer) with no served ask from that task is refused: " noAsk))
      (assert (= (po/formBody "(:ask :to 1 :body (:q \"a)\" (:n 1)) :x 2)") (some "(:q \"a)\" (:n 1))")) "the body is the balanced form after :body, a ) inside a string included")
      (assert (none? (po/poolSelfOf "(:agent :task \"t\")")) "an (:agent) form without :poolChan is not in a pool")
      (assert (= res.exitCode 0) (str "the pool ends ok: " res.stdout))
      true))
