(module aslHarness/selfOrgToolkitTest :x [testTodoLedgerLifecycle testLimitCycleTripping testWorkingMemoryOperations testSnapshotRollback testProbeExecution testLensEvaluation testTerminationProofValidation testDualPolarityRefutations runTests] :i [(selfOrgToolkit :a sot)])

fn testTodoLedgerLifecycle -> Bool
  (let [(emptyL (sot/makeEmptyLedger))
        (l1 (sot/addTodoItem emptyL "T1" "Inspect policy.yaml" "S1"))
        (l2 (sot/addTodoItem l1 "T2" "Implement CSV generator" "S2"))
        (lFakeDone (sot/markTodoDone l2 "T1" ""))
        (l3 (sot/markTodoDone l2 "T1" "probe_policy"))]
    (assert (= l1.pendingCount 1) "pending count is 1 after add")
    (assert (= l2.pendingCount 2) "pending count is 2 after second add")
    (assert (= lFakeDone.completedCount 0) "marking done without verifying probe fails (anti-vacuity)")
    (assert (= l3.pendingCount 1) "pending count decrements on verified done")
    (assert (= l3.completedCount 1) "completed count increments on verified done")
    (assert (not l3.trippedLimitCycle) "limit cycle not tripped under normal ops")
    true)

fn testLimitCycleTripping -> Bool
  (let [(emptyL (sot/makeEmptyLedger))
        (l1 (sot/addTodoItem emptyL "T1" "Inspect policy.yaml" "S1"))
        (f1 (sot/markTodoBlocked l1 "T1" "SyntaxError in parser"))
        (f2 (sot/markTodoBlocked f1 "T1" "SyntaxError in parser"))
        (f3 (sot/markTodoBlocked f2 "T1" "SyntaxError in parser"))]
    (assert (not f1.trippedLimitCycle) "first failure does not trip limit cycle")
    (assert (not f2.trippedLimitCycle) "second failure does not trip limit cycle")
    (assert f3.trippedLimitCycle "third consecutive failure trips limit cycle circuit breaker")
    true)

fn testWorkingMemoryOperations -> Bool
  (let [(mem (sot/makeWorkingMemory))
        (m1 (sot/recordNote mem "yamlSchema" "version: 2.0" "policy.yaml" 1789881000))
        (m2 (sot/recordNote m1 "limits" "memory: 64MB" "runtime.conf" 1789881010))
        (val1 (sot/lookupNote m2 "yamlSchema"))
        (val2 (sot/lookupNote m2 "limits"))
        (valMissing (sot/lookupNote m2 "unknownKey"))]
    (assert (= m2.entryCount 2) "two notes registered")
    (assert (= val1 "version: 2.0") "yamlSchema note retrieved cleanly")
    (assert (= val2 "memory: 64MB") "limits note retrieved cleanly")
    (assert (= valMissing "") "unknown key returns empty string")
    true)

fn testSnapshotRollback -> Bool
  (let [(snap (sot/createSnapshot "chk1" "/app" "hash-abc-123" 1789881020))
        (pairResMatch (sot/restoreSnapshot snap "hash-abc-123"))
        (pairResMismatch (sot/restoreSnapshot snap "corrupted-hash"))]
    (assert snap.active "snapshot created active")
    (assert (pairSecond pairResMatch) "restore of snapshot with valid hash succeeds")
    (assert (not (pairSecond pairResMismatch)) "restore with mismatched hash fails")
    true)

fn testProbeExecution -> Bool
  (let [(pPass (sot/evaluateProbe "test_filter" "S1" 0 5 120 true true))
        (pFailExit (sot/evaluateProbe "test_failing" "S1" 1 5 110 true true))
        (pFailZeroAssert (sot/evaluateProbe "test_vacuous" "S1" 0 0 100 true true))
        (pFailInvert (sot/evaluateProbe "test_unreachable" "S1" 0 4 105 false true))
        (pFailBaseline (sot/evaluateProbe "test_no_baseline" "S1" 0 4 105 true false))]
    (assert pPass.passed "clean probe with assertCount > 0, invert, and baseline pass")
    (assert (not pFailExit.passed) "non-zero exit fails probe")
    (assert (not pFailZeroAssert.passed) "zero assertions fails probe (anti-vacuity)")
    (assert (not pFailInvert.passed) "failed inversion check fails probe")
    (assert (not pFailBaseline.passed) "missing baseline failure fails probe (causality invariant)")
    true)

fn testLensEvaluation -> Bool
  (let [(lAllGood (sot/evaluateLenses true true true 0 3))
        (lBadIntent (sot/evaluateLenses false true true 0 3))
        (lTrippedCycle (sot/evaluateLenses true true true 3 3))]
    (assert (= lAllGood.healthScore 1.0) "all clear gives 1.0 health score")
    (assert lAllGood.thresholdsPassed "thresholds passed for clear health and low error")
    (assert (= lBadIntent.healthScore 0.0) "bad intent drops health score")
    (assert (not lTrippedCycle.thresholdsPassed) "tripped error cycle fails thresholds")
    true)

fn testTerminationProofValidation -> Bool
  (let [(ledger (sot/addTodoItem (sot/makeEmptyLedger) "T1" "Task 1" "S1"))
        (doneLedger (sot/markTodoDone ledger "T1" "p1"))
        (trippedL (sot/markTodoBlocked (sot/markTodoBlocked (sot/markTodoBlocked ledger "T1" "err") "T1" "err") "T1" "err"))
        (proofPending (sot/validateTerminationProof "Done" true false true ledger))
        (proofUnbound (sot/validateTerminationProof "Done" true false false doneLedger))
        (proofTripped (sot/validateTerminationProof "Done" true false true trippedL))
        (proofPassProbe (sot/validateTerminationProof "Verified" true false true doneLedger))
        (proofPassExternal (sot/validateTerminationProof "External pass" false true true (sot/makeEmptyLedger)))]
    (assert (not proofPending.taskClosed) "unresolved todos block task closure")
    (assert (not proofUnbound.taskClosed) "unbound external intent blocks task closure (anti-vacuity)")
    (assert (not proofTripped.taskClosed) "tripped limit cycle blocks task closure")
    (assert proofPassProbe.taskClosed "resolved todos, intent bound, and verified probes allow closure")
    (assert proofPassExternal.taskClosed "voluntary affordance: external suite verified on empty ledger allows closure")
    true)

fn testDualPolarityRefutations -> Bool
  (let [(emptyLedger (sot/makeEmptyLedger))
        (ledgerWithPending (sot/addTodoItem emptyLedger "item" "desc" "S1"))
        (unverifiedProof (sot/validateTerminationProof "Proof" false false true emptyLedger))
        (unboundProof (sot/validateTerminationProof "Proof" true false false emptyLedger))]
    (refute (> emptyLedger.pendingCount 0) "empty ledger must not have pending items")
    (refute (= ledgerWithPending.pendingCount 0) "ledger with added item must not have zero pending")
    (refute unverifiedProof.taskClosed "unverified probe proof must not allow task closure")
    (refute unboundProof.taskClosed "unbound intent proof must not allow task closure")
    true)

fn runTests -> Bool
  (do
    (testTodoLedgerLifecycle)
    (testLimitCycleTripping)
    (testWorkingMemoryOperations)
    (testSnapshotRollback)
    (testProbeExecution)
    (testLensEvaluation)
    (testTerminationProofValidation)
    (testDualPolarityRefutations)
    true)
