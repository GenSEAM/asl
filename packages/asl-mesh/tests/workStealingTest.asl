(module asl-mesh/tests/workStealingTest
  :x [RunTests runTests]
  :i [(asl-mesh/coord :a coord)])

fn testWorkStealingDisjointness -> Bool
  (let [(pBusy (coord/makeWorkerPartition "wBusy" (list "t1" "t2") (list "pkgA/foo.asl" "pkgB/bar.asl")))
        (pIdle (coord/makeWorkerPartition "wIdle" (list) (list)))
        (claimDisjoint (coord/makeSwarmClaim "t2" "wBusy" 1000 (list "pkgB/bar.asl") (list) "root0"))
        (claimOverlap (coord/makeSwarmClaim "t3" "wBusy" 1000 (list "pkgA/foo.asl") (list) "root0"))
        (canStealDisj (coord/canStealTask? pIdle claimDisjoint))
        (canStealOvlp (coord/canStealTask? pBusy claimOverlap))
        (stealRes (coord/stealDisjointTask pBusy pIdle "t2" (list "pkgB/bar.asl")))]
    (assert canStealDisj "Idle worker can steal disjoint task")
    (assert (not canStealOvlp) "Worker with overlapping writeSet cannot steal task")
    (assert (= (listLength stealRes.thief.taskIds) 1) "Thief partition received stolen task")
    (assert (= (listLength stealRes.victim.taskIds) 1) "Victim partition yielded stolen task")
    (refute (not canStealDisj) "Refutation: Disjoint steal must be permitted")
    (refute canStealOvlp "Refutation: Overlapping steal must be rejected")
    true)

fn testWorkStealingEpoch -> Bool
  (let [(pBusy (coord/makeWorkerPartition "wBusy" (list "taskA") (list "src/foo.asl")))
        (pIdle (coord/makeWorkerPartition "wThief" (list) (list)))
        (claim (coord/makeSwarmClaimWithEpoch "taskA" "wBusy" 2000 500 1 (list "src/foo.asl") (list) "merkle1"))
        (mismatchCanSteal (coord/canStealClaim? pIdle claim 2))
        (mismatchStealResult (coord/stealDisjointTaskWithEpoch pBusy pIdle "taskA" (list "src/foo.asl") 1 2))
        (mismatchClaimOpt (coord/stealDisjointClaim pBusy pIdle claim 2))
        (matchCanSteal (coord/canStealClaim? pIdle claim 1))
        (matchClaimOpt (coord/stealDisjointClaim pBusy pIdle claim 1))]
    (assert (not mismatchCanSteal) "Mismatch epoch prevents claim stealing")
    (refute mismatchCanSteal "Refutation: Mismatch epoch cannot be stolen")
    (assert (not mismatchStealResult.success) "Mismatch epoch steal returns failure")
    (refute mismatchStealResult.success "Refutation: Mismatch epoch steal cannot succeed")
    (assert (none? mismatchClaimOpt) "Mismatch claim returns none")
    (refute (some? mismatchClaimOpt) "Refutation: Mismatch claim cannot return some")
    (assert matchCanSteal "Matching epoch allows claim stealing")
    (assert (some? matchClaimOpt) "Matching claim returns some")
    (refute (none? matchClaimOpt) "Refutation: Matching claim cannot return none")
    (mt matchClaimOpt ((some claimPair) (let [(sRes (pairFirst claimPair))
          (newClaim (pairSecond claimPair))]
      (assert sRes.success "Steal result is success")
      (assert (= newClaim.claimEpoch 2) "New claim has incremented epoch 2")
      (refute (!= newClaim.claimEpoch 2) "Refutation: Epoch must be exactly 2")
      (assert (= newClaim.workerId "wThief") "New claim is owned by thief")
      (refute (!= newClaim.workerId "wThief") "Refutation: WorkerId must be thief")
      (assert (= (listLength sRes.thief.taskIds) 1) "Thief partition has 1 task")
      (assert (= (listLength sRes.victim.taskIds) 0) "Victim partition has 0 tasks")
      true)) (none false)))

fn runTests -> Bool
  (do
    (assert (testWorkStealingDisjointness) "testWorkStealingDisjointness passed")
    (assert (testWorkStealingEpoch) "testWorkStealingEpoch passed")
    true)

fn RunTests -> Bool
  (runTests)
