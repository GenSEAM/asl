(module asl-tools/coord/tests/claimHolderTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref COND-OWNS-HOLDER-GONE :do "a unit refused on :owns by a unit whose lease is live is freed once the holder is merged, closed, done or blocked, and stays waiting while the holder is writing or unknown")
fn mkHolder s: String -> cd/CUnit
  (pf/cuIn "HOLD" s "" "sh/HOLD")

fn ! isFreed leases: (List st/Lease) waiter: cd/CUnit s: String -> Bool
  (cd/claimFreed? waiter leases (nowNs) (list (mkHolder s)))

fn ! runTests -> Bool
  (let [(root (pf/scratch "claimHolder" "h"))
        (_ (pf/cleanup root))
        (store (str root "/store"))
        (_ (dirCreate (str store "/tasks")))
        (_ (st/put! store (pf/unitIn "HOLD" "g")))
        (_ (st/claim! store "HOLD" "claimHolderTest" 600000))
        (leases (match (st/readLeases! store) ((ok l) l) ((err _) (list))))
        (sig (str "waitedOut: (:refused :why owns :by " (st/q "HOLD") ")"))
        (waiter (with (pf/cuIn "W1" "blocked" "" "sh/W1") :sig sig))
        (_ (pf/cleanup root))]
    (do (assert (not (listEmpty? leases)) "fixture: a live lease of HOLD")
        (assert (not (isFreed leases waiter "writing")) "a writing holder keeps the unit waiting")
        (assert (and (isFreed leases waiter "blocked") (isFreed leases waiter "merged") (isFreed leases waiter "closed") (isFreed leases waiter "done")) "a blocked, merged, closed or done holder frees it")
        (assert (not (cd/claimFreed? waiter leases (nowNs) (list))) "an unknown holder keeps it waiting")
        (assert (cd/claimFreed? (with waiter :sig (str "waitedOut: (:refused :why owns :by " (st/q "X") ")")) (list) (nowNs) (list)) "a holder with no live lease frees it as before")
        true))
