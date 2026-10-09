(module aslMem/tests/taskModularTest :x [runTests testTaskClaimAndState testTaskSettle testProcStatus testProcList] :i [(tasks :a task) (asl-proc/process :a proc) (asl-proc/apm :a apm)])

fn testTaskClaimAndState -> Bool
  (let [(t0 (task/makeTask "t1" "p1" "Test Task" "main" "planned" "normal" 1000 (list "src/a.asl") (list) "asl check" "why1")) (initialState (task/state t0)) (t1 (task/claim t0 2000)) (claimedState (task/state t1))] (assert (= initialState "planned") "Initial task state must be planned") (assert (= claimedState "claimed") "task/claim must transition task state to claimed") (assert (= t1.updatedAt 2000) "Claimed task updated-at must reflect claim epoch") (assert (= t1.id "t1") "Task id must be preserved across claim") true)

fn testTaskSettle -> Bool
  (let [(t0 (task/makeTask "t2" "p1" "Task Settle" "main" "planned" "normal" 1000 (list "src/b.asl") (list) "asl test" "why2")) (t1 (task/claim t0 2000)) (receipt "(:receipt :exit-code 0 :asserts 10)") (t2 (task/settle t1 receipt 3000)) (settledState (task/state t2))] (assert (= settledState "completed") "task/settle must transition task to completed state") (assert (= t2.completedAt 3000) "task/settle completed-at must match completion epoch") (assert (= (listLength t2.receipts) 1) "Settled task must have exactly 1 attached receipt") (assert (= (optionOr (listGet t2.receipts 0) "") receipt) "Attached receipt must match settled payload") true)

fn testProcStatus -> Bool
  (let [(vOk (proc/status 50 1000 "build-step")) (vTimeout (proc/status 15000 10000 "hanging-step"))] (assert (= vOk.status ":ok") "Step within deadline must have :ok status") (assert (= vOk.exitCode 0) "Step within deadline must have exit-code 0") (assert (not vOk.workerRecycled) "Step within deadline must not recycle worker") (assert (= vTimeout.status ":recycled") "Exceeded deadline must have :recycled status") (assert (= vTimeout.exitCode 124) "Exceeded deadline must emit exit code 124") (assert vTimeout.workerRecycled "Exceeded deadline must flag worker as recycled") true)

fn testProcList -> Bool
  (let [(e1 (apm/makeDaemonEntry "d-abc12" 4510 128 ":active" "step-eval")) (emptyTbl (proc/list (list))) (popTbl (proc/list (list e1)))] (assert (stringContains? emptyTbl "DAEMON ID") "Empty process list table must render header") (assert (stringContains? popTbl "DAEMON ID") "Populated table must contain header") (assert (stringContains? popTbl "d-abc12") "Populated table must contain daemon identifier") (assert (stringContains? popTbl "4510") "Populated table must contain pid") (assert (stringContains? popTbl ":active") "Populated table must contain daemon status") true)

fn runTests -> Bool
  (and (testTaskClaimAndState) (and (testTaskSettle) (and (testProcStatus) (testProcList))))
