(module aslAgentCore/tests/workerSupervisorTest
  :x [testWorkerPoolLifecycle testSlidingIdleTimeout testWorkerReap runTests]
  :i [(asl/packages/asl-agent-core/src/workerSupervisor :a ws)])

fn testWorkerPoolLifecycle -> Bool
  (let [(cfg (ws/SupervisorLimitsConfig :slidingIdleMs 10000 :maxWallClockMs 900000 :maxMemMb 1024))
        (pool (ws/workerPoolCreate cfg))
        (s1 (ws/workerSpawn pool (ws/sandboxWorkspaceWrite) (list "src/compiler.asl" "tests/compilerTest.asl") 12345 1000))
        (p1 (pairFirst s1))
        (wId1 (pairSecond s1))]
    (assert (= (mapSize p1.workers) 1) "Worker pool has 1 worker")
    (assert (= wId1 "worker-1") "Worker ID is worker-1")
    (mt (mapGet p1.workers wId1)
      ((some rec)
        (do
          (assert (= rec.pid 12345) "Worker PID matches 12345")
          (assert (= (listLength rec.owns) 2) "Worker owns 2 paths")
          true))
      ((none) false)))

fn testSlidingIdleTimeout -> Bool
  (let [(cfg (ws/SupervisorLimitsConfig :slidingIdleMs 10000 :maxWallClockMs 900000 :maxMemMb 1024))
        (pool (ws/workerPoolCreate cfg))
        (s1 (ws/workerSpawn pool (ws/sandboxWorkspaceWrite) (list "src/target.asl") 23456 1000))
        (p1 (pairFirst s1))
        (wId1 (pairSecond s1))]
    (assert (= (mapSize p1.workers) 1) (str "p1 size: " (stringFromInt64 (mapSize p1.workers)) ", wId1=" wId1))
    (let [(p2 (ws/workerHeartbeat p1 wId1 5000 64))
          (check1 (ws/workerCheckLimits p2 8000))
          (stalled1 (pairSecond check1))
          (check2 (ws/workerCheckLimits p2 20000))
          (stalled2 (pairSecond check2))]
      (assert (= (listLength stalled1) 0) "Active worker is not stalled at 8000ms")
      (assert (= (mapSize p2.workers) 1) "p2 size is 1")
      (assert (= (listLength stalled2) 1) "Inactive worker is stalled at 20000ms")
      (assert (= (optionOr (listHead stalled2) "") wId1) "Stalled worker ID is wId1")
      true))

fn testWorkerReap -> Bool
  (let [(cfg (ws/SupervisorLimitsConfig :slidingIdleMs 10000 :maxWallClockMs 900000 :maxMemMb 1024))
        (pool (ws/workerPoolCreate cfg))
        (s1 (ws/workerSpawn pool (ws/sandboxReadOnly) (list) 34567 1000))
        (p1 (pairFirst s1))
        (wId1 (pairSecond s1))
        (p2 (ws/workerReap p1 wId1))]
    (assert (= (mapSize p2.workers) 0) "Worker pool is empty after reap")
    true)

fn runTests -> Bool
  (do
    (assert (testWorkerPoolLifecycle) "Worker pool lifecycle test must pass")
    (assert (testSlidingIdleTimeout) "Sliding idle timeout test must pass")
    (assert (testWorkerReap) "Worker reap test must pass")
    true)
