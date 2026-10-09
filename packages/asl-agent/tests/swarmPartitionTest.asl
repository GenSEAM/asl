(module asl/packages/asl-agent/tests/swarmPartitionTest
  :x [runTests]
  :i [(aslAgent/swarmPartition :a sp)])

fn testDisjointPartitions -> Bool
  (let [(p1 (sp/makePartitionSet "worker-1" (list "asl/packages/asl-compiler" "asl/packages/asl-codegen")))
        (p2 (sp/makePartitionSet "worker-2" (list "agent-bus" "agent")))
        (pOverlapping (sp/makePartitionSet "worker-3" (list "asl/packages/asl-compiler/src")))]
    (do
      (refute (sp/detectCollision? p1 p2) "disjoint partitions must not collide")
      (assert (sp/detectCollision? p1 pOverlapping) "overlapping partition prefix must collide")
      (assert (sp/detectCollision? pOverlapping p1) "collision detection is symmetric")
      (assert (sp/validateScopeOwnership p1 (list "asl/packages/asl-compiler/src/macro.asl")) "subpath within partition is valid")
      (refute (sp/validateScopeOwnership p1 (list "asl/packages/asl-agent-bus/src/bus.asl")) "unowned path must be rejected")
      true))

fn testScopeLeaseManagement -> Bool
  (let [(p (sp/makePartitionSet "worker-1" (list "asl/packages/asl-runtime")))
        (reg0 (sp/emptyLeaseRegistry))
        (reg1Res (sp/claimScopeLease reg0 p 30000))
        (regConflictRes (sp/claimScopeLease (resultOr reg1Res reg0) (sp/makePartitionSet "worker-2" (list "asl/packages/asl-runtime/src")) 30000))]
    (do
      (assert (ok? reg1Res) "initial lease claim succeeds")
      (refute (ok? regConflictRes) "conflicting lease claim must fail")
      (mt reg1Res
        ((err _) (assert false "reg1 must be ok"))
        ((ok r1)
          (let [(reg2Res (sp/releaseScopeLease r1 "worker-1" (list "asl/packages/asl-runtime")))]
            (assert (ok? reg2Res) "release lease succeeds")
            (mt reg2Res
              ((err _) (assert false "release must be ok"))
              ((ok r2)
                (let [(regReclaimRes (sp/claimScopeLease r2 (sp/makePartitionSet "worker-2" (list "asl/packages/asl-runtime/src")) 30000))]
                  (assert (ok? regReclaimRes) "re-claiming released scope succeeds")
                  true))))))
      true))

fn runTests -> Bool
  (and (testDisjointPartitions)
       (testScopeLeaseManagement))
