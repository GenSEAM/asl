(module asl/packages/asl-agent-core/tests/schedulerTest :x [runTests testIsReapableState testReapStaleIntermediateStates!] :i [(tasktypes :a tt) (taskstore :a ts) (statemachine :a sm) (scheduler :a sc) (dag :a d)])

fn testIsReapableState -> Bool
  (do (assert (sc/isReapableState? (tt/stateRouting)) "state-routing must be reapable") (assert (sc/isReapableState? (tt/stateClarification)) "state-clarification must be reapable") (assert (sc/isReapableState? (tt/stateReady)) "state-ready must be reapable") (assert (sc/isReapableState? (tt/stateExecuting)) "state-executing must be reapable") (assert (sc/isReapableState? (tt/stateVerifying)) "state-verifying must be reapable") (assert (not (sc/isReapableState? (tt/stateQueued))) "state-queued must not be reapable") (assert (not (sc/isReapableState? (tt/stateDone))) "state-done must not be reapable") (assert (not (sc/isReapableState? (tt/stateFailed))) "state-failed must not be reapable") (assert (not (sc/isReapableState? (tt/stateCancelled))) "state-cancelled must not be reapable") true)

fn testReapStaleIntermediateStates! -> Bool
  (let [(cfg (sc/SchedulerConfig :maxConcurrent 4 :staleTimeoutMs 3000)) (store0 (ts/taskstoreCreate "/tmp/stale-tests")) (tC (tt/taskRecordCreate "t-c" "l-c" "/ws/p-c" (tt/priorityNormal) 1000 "c")) (s1 (resultOr (ts/taskstorePut! store0 tC) store0)) (s2 (resultOr (ts/taskstoreClaim! s1 "t-c") s1)) (s3 (resultOr (ts/taskstoreTransition! s2 "t-c" (tt/stateClarification) 1000) s2)) (schedC (sc/SchedulerState :config cfg :activeProjects (list "/ws/p-c") :activeLanes (mapSet (mapEmpty) "l-c" 1))) (reapC (resultOr (sc/schedulerReapStale! schedC s3 5000) (sc/ReapResult :scheduler schedC :store s3 :reapedCount 0)))] (assert (= reapC.reapedCount 1) "Stale clarification task must be reaped") (let [(recC (optionOr (ts/taskstoreGet reapC.store "t-c") tC))] (assert (= recC.state (tt/stateQueued)) "Reaped task must return to state-queued") (assert (not (listContains? reapC.scheduler.activeProjects "/ws/p-c")) "Project lock must be released") true))

fn testSchedulerReleaseTask! -> Bool
  (let [(cfg (sc/SchedulerConfig :maxConcurrent 4 :staleTimeoutMs 3000))
        (store0 (ts/taskstoreCreate "/tmp/rel-tests"))
        (task1 (tt/taskRecordCreate "task-1" "lane-alpha" "/ws/proj-alpha" (tt/priorityNormal) 1000 "payload"))
        (s1 (resultOr (ts/taskstorePut! store0 task1) store0))
        (schedInit (sc/SchedulerState :config cfg :activeProjects (list "/ws/proj-alpha") :activeLanes (mapSet (mapEmpty) "lane-alpha" 1)))
        (schedAfter (sc/schedulerReleaseTask schedInit s1 "task-1"))]
    (assert (not (listContains? schedAfter.activeProjects "/ws/proj-alpha")) "schedulerReleaseTask releases active project")
    (assert (= (sc/getLaneCount schedAfter.activeLanes "lane-alpha") 0) "schedulerReleaseTask decrements lane count to 0")
    true)

fn testDeadLetterPoisonPillReaping! -> Bool
  (let [(cfg (sc/SchedulerConfig :maxConcurrent 4 :staleTimeoutMs 3000))
        (store0 (ts/taskstoreCreate "/tmp/poison-tests"))
        (taskPoison (tt/taskRecordCreate "t-poison" "lane-p" "/ws/proj-p" (tt/priorityNormal) 1000 "poison-payload :retry :retry :retry"))
        (s1 (resultOr (ts/taskstorePut! store0 taskPoison) store0))
        (s2 (resultOr (ts/taskstoreClaim! s1 "t-poison") s1))
        (s3 (resultOr (ts/taskstoreTransition! s2 "t-poison" (tt/stateExecuting) 1000) s2))
        (schedP (sc/SchedulerState :config cfg :activeProjects (list "/ws/proj-p") :activeLanes (mapSet (mapEmpty) "lane-p" 1)))
        (retryCountInitial (sc/getTaskRetryCount taskPoison.payload))
        (reapRes (resultOr (sc/schedulerReapStale! schedP s3 5000) (sc/ReapResult :scheduler schedP :store s3 :reapedCount 0)))
        (recPoison (optionOr (ts/taskstoreGet reapRes.store "t-poison") taskPoison))
        (finalState recPoison.state)]
    (assert (= retryCountInitial 3) "Initial poison task has 3 retries")
    (assert (= reapRes.reapedCount 1) "Poison task was reaped")
    (assert (mt finalState ((stateFailed) true) (_ false)) "Poison task exceeding maxRetries transitioned to stateFailed dead-letter")
    (refute (mt finalState ((stateQueued) true) (_ false)) "Refutation: Dead-lettered poison task must not return to stateQueued")
    (assert (not (listContains? reapRes.scheduler.activeProjects "/ws/proj-p")) "Project lock released on dead-letter")
    (assert (= (sc/getLaneCount reapRes.scheduler.activeLanes "lane-p") 0) "Lane count decremented to 0 on dead-letter")
    true)

fn testDagAcyclicValidation -> Bool
  (let [(d0 (d/dagCreate))
        (nA (d/TaskNode :id "nA" :title "Task A" :state (d/taskPending) :dependencies (list) :premises (list)))
        (nB (d/TaskNode :id "nB" :title "Task B" :state (d/taskPending) :dependencies (list "nA") :premises (list)))
        (nC (d/TaskNode :id "nC" :title "Task C" :state (d/taskPending) :dependencies (list "nB") :premises (list)))
        (dagAcyclic (d/dagAddNode (d/dagAddNode (d/dagAddNode d0 nA) nB) nC))
        (isAcyclicValid (sc/validateDagAcyclic dagAcyclic))
        (c1 (d/TaskNode :id "c1" :title "Cycle 1" :state (d/taskPending) :dependencies (list "c2") :premises (list)))
        (c2 (d/TaskNode :id "c2" :title "Cycle 2" :state (d/taskPending) :dependencies (list "c1") :premises (list)))
        (dagCyclic (d/dagAddNode (d/dagAddNode d0 c1) c2))
        (isCyclicValid (sc/validateDagAcyclic dagCyclic))
        (sLoop (d/TaskNode :id "sLoop" :title "Self Loop" :state (d/taskPending) :dependencies (list "sLoop") :premises (list)))
        (dagSelfLoop (d/dagAddNode d0 sLoop))
        (isSelfLoopValid (sc/validateDagAcyclic dagSelfLoop))]
    (do
      (assert isAcyclicValid "Acyclic linear DAG passes validation")
      (refute isCyclicValid "Refutation: Circular 2-node dependency DAG must fail validation")
      (refute isSelfLoopValid "Refutation: Self-referential loop DAG must fail validation")
      true))

fn testWorkerLeaseEpochFencing! -> Bool
  (let [(cfg (sc/SchedulerConfig :maxConcurrent 4 :staleTimeoutMs 3000))
        (store0 (ts/taskstoreCreate "/tmp/epoch-tests"))
        (codePayload "(assert (stringContains? code \":retry\"))")
        (taskCode (tt/taskRecordCreate "t-code" "lane-code" "/ws/proj-code" (tt/priorityNormal) 1000 codePayload))
        (countInitial (sc/getTaskRetryCount taskCode.payload))
        (s1 (resultOr (ts/taskstorePut! store0 taskCode) store0))
        (s2 (resultOr (ts/taskstoreClaim! s1 "t-code") s1))
        (s3 (resultOr (ts/taskstoreTransition! s2 "t-code" (tt/stateExecuting) 1000) s2))
        (schedInit (sc/SchedulerState :config cfg :activeProjects (list "/ws/proj-code") :activeLanes (mapSet (mapEmpty) "lane-code" 1)))
        (reapRes (resultOr (sc/schedulerReapStaleWithEpoch! schedInit s3 5000 3 1) (sc/ReapResult :scheduler schedInit :store s3 :reapedCount 0)))
        (recAfterReap (optionOr (ts/taskstoreGet reapRes.store "t-code") taskCode))
        (retryCountAfter1 (sc/getTaskRetryCount recAfterReap.payload))]
    (do
      (assert (= countInitial 0) "Code containing literal :retry does not false-positive as retry")
      (assert (= reapRes.reapedCount 1) "Stale task with epoch 1 was reaped")
      (assert (= recAfterReap.state (tt/stateQueued)) "Reaped task returned to queued state")
      (assert (= retryCountAfter1 1) "Task retry count incremented to 1 after epoch reap")
      (refute (> countInitial 0) "Refutation: Payload with code containing :retry must not start with >0 retries")
      true))

fn ! runTests -> Bool
  (and (and (and (and (testIsReapableState) (testReapStaleIntermediateStates!)) (testSchedulerReleaseTask!)) (testDeadLetterPoisonPillReaping!)) (and (testDagAcyclicValidation) (testWorkerLeaseEpochFencing!)))
