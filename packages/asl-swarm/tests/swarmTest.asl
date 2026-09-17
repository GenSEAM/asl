(module asl-swarm/tests/swarmTest
  :d "Unit test suite for autonomous agent swarm coordination and Merkle OCC"
  :x [RunTests runTests]
  :i [(asl-swarm/coord :a coord)
      (asl-swarm/occ :a occ)])

(df testCoordinationAndScheduling [] -> Bool
  :d "Verifies swarm claim creation, disjointness check, and task partitioning"
  (let [(c1 (coord/makeSwarmClaim "t1" "w1" 100 (list "a.asl") (list "a.asl") "root0"))
        (c2 (coord/makeSwarmClaim "t2" "w2" 200 (list "b.asl") (list "b.asl") "root0"))
        (c3 (coord/makeSwarmClaim "t3" "w3" 300 (list "a.asl") (list "a.asl") "root0"))
        (disj (coord/areClaimsDisjoint c1 c2))
        (ovlp (coord/areClaimsDisjoint c1 c3))
        (parts (coord/scheduleDisjointTasks (list c1 c2 c3)))]
    (assert disj "Disjoint claims return true")
    (assert (not ovlp) "Overlapping claims return false")
    (assert (> (list-length parts) 0) "Partitions are non-empty")
    (refute (not disj) "Refutation: Disjoint claims must not overlap")
    (refute ovlp "Refutation: Overlapping claims must be detected")
    true))

(df testOccValidationAndArbitration [] -> Bool
  :d "Verifies OCC commit validation, conflict reports, and lease arbitration"
  (let [(c (coord/makeSwarmClaim "t1" "w1" 100 (list "a.asl") (list "a.asl") "root0"))
        (stMatch (occ/makeOccState "root0" (map-empty)))
        (stMismatch (occ/makeOccState "root1" (map-empty)))
        (resOk (occ/validateMerkleCommit c stMatch "root0-next"))
        (resErr (occ/validateMerkleCommit c stMismatch "root1-next"))
        (repOk (occ/getCommitConflictReport resOk))
        (repErr (occ/getCommitConflictReport resErr))
        (cEarlier (coord/makeSwarmClaim "t1" "wEarly" 50 (list "a.asl") (list "a.asl") "root0"))
        (cLater (coord/makeSwarmClaim "t1" "wLate" 150 (list "a.asl") (list "a.asl") "root0"))
        (arb (occ/resolveLeaseConflict cEarlier cLater))
        (canRetry (occ/canRetryOccCommit 2))
        (cannotRetry (occ/canRetryOccCommit 3))
        (discarded (occ/discardStagingBuffer "w1"))]
    (assert (is-ok? resOk) "Matching root commit succeeds")
    (assert (is-err? resErr) "Diverged root commit fails")
    (assert (= (.-status repOk) "ok") "Report status is ok")
    (assert (= (.-status repErr) "conflict") "Report status is conflict")
    (assert (= (.-workerId arb) "wEarly") "Earlier lease wins arbitration")
    (assert canRetry "Attempt 2 is allowed")
    (assert (not cannotRetry) "Attempt 3 is denied")
    (assert discarded "Staging buffer discarded cleanly")
    (refute (is-err? resOk) "Refutation: Matching root must not error")
    (refute (is-ok? resErr) "Refutation: Mismatched root must not succeed")
    true))

(df runTests [] -> Bool
  :d "Runs all asl-swarm unit test suites"
  (let [(okCoord (testCoordinationAndScheduling))
        (okOcc (testOccValidationAndArbitration))]
    (and okCoord okOcc)))

(df RunTests [] -> Bool
  :d "Export alias for runTests"
  (runTests))
