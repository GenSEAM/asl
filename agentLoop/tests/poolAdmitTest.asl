(module asl/agentLoop/tests/poolAdmitTest
  :x [runTests]
  :i [(asl/agentLoop/pool :a pl)])

; (:m :ref LEON-POOL-20261026 :do "admission and lane grouping without running a task: a claim covers its path and everything under it, a glob widens to its directory, an empty :owns claims the whole root, and tasks whose roots nest share a lane")

fn task idx: Int64 root: String owns: (List String) -> pl/PoolTask
  (pl/PoolTask :idx idx :form "" :root root :owns owns :wallMs 1000 :waitsFor (list) :chan ""
               :claims (if (listEmpty? owns) (list root) (map (fn [(o String)] -> String (pl/claimOf root o)) owns)))

fn idxs ts: (List pl/PoolTask) -> (List Int64)
  (map (fn [(t pl/PoolTask)] -> Int64 t.idx) ts)

fn ! runTests -> Bool
  (let [(adm (pl/admit (list (task 0 "/r" (list "a/b.txt")) (task 1 "/r" (list "a")) (task 2 "/r" (list "c.txt")) (task 3 "/s" (list)))))
        (lanes (pl/lanesOf (list (task 0 "/r/x" (list)) (task 1 "/s" (list)) (task 2 "/r/y" (list)) (task 3 "/r" (list "z")))))]
    (do
      (assert (= (pl/claimOf "/r" "a/./b/../c.txt") "/r/a/c.txt") "a claim is normalised under its root")
      (assert (= (pl/claimOf "/r" "src/*.asl") "/r/src") "a glob claims the directory before its wildcard")
      (assert (= (pl/claimOf "/r" "/abs/f") "/abs/f") "an absolute :owns entry is kept as is")
      (assert (pl/claimsOverlap? (list "/r/a") (list "/r/a/b.txt")) "a directory claim covers a file under it")
      (assert (not (pl/claimsOverlap? (list "/r/ab") (list "/r/a"))) "a shared name prefix is not an overlap")
      (assert (not (pl/claimsOverlap? (list "/r/a.txt") (list "/r/b.txt"))) "two files of one root are disjoint")
      (assert (= (idxs adm.admitted) (list 2 3)) "the disjoint file and the other root are admitted")
      (assert (= (map (fn [(r pl/Refusal)] -> (List Int64) r.with) adm.refused) (list (list 1) (list 0))) "both members of the overlapping pair are refused, each naming the other")
      (assert (= (map (fn [(r pl/Refusal)] -> String r.error) adm.refused) (list "ERR_OWNS_OVERLAP" "ERR_OWNS_OVERLAP")) "the refusal carries ERR_OWNS_OVERLAP")
      (assert (= (map idxs lanes) (list (list 0 2 3) (list 1))) "roots nesting under /r join one lane, ordered by task, and /s keeps its own")
      (assert (= (pl/receiptStatus "(:agentReceipt :status :escalated :phases ())") "escalated") "a receipt's status is read")
      (assert (= (pl/receiptStatus "garbage") "failed") "a receipt without a status counts as failed")
      (assert (= (pl/receiptJournal "(:agentReceipt :status :ok :journal \".asl/run/agentLoop/s1.journal\" :unbacked 0)") ".asl/run/agentLoop/s1.journal") "a receipt's journal is read")
      (assert (= (pl/poolExit (list) (list (pl/Refusal :idx 0 :error "ERR_OWNS_OVERLAP" :with (list 1) :message ""))) 2) "a refusal makes the pool exit 2")
      true))
