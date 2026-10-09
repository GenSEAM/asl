(module aslAgentCore/scheduler :x [SchedulerConfig SchedulerState DrainResult ReapResult DrainAccumulator schedulerCreate schedulerDrain! schedulerReapStale! schedulerReapStaleWithMaxRetries! getTaskRetryCount schedulerReleaseProject schedulerReleaseTask schedulerReleaseLane isReapableState? validateDagAcyclic schedulerReapStaleWithEpoch! getLaneCount] :i [(tasktypes :a tt) (taskstore :a ts) (statemachine :a sm) (dag :a d)])

(schema SchedulerConfig (:f maxConcurrent I64) (:f staleTimeoutMs I64))

(schema SchedulerState (:f config SchedulerConfig) (:f activeProjects (List Str)) (:f activeLanes (Map Str I64)))

(schema DrainResult (:f scheduler SchedulerState) (:f store ts/TaskStore) (:f claimedTasks (List tt/TaskRecord)))

(schema ReapResult (:f scheduler SchedulerState) (:f store ts/TaskStore) (:f reapedCount I64))

(schema DrainAccumulator (:f sched SchedulerState) (:f store ts/TaskStore) (:f claimed (List tt/TaskRecord)))

fn schedulerCreate config: SchedulerConfig -> SchedulerState
  (SchedulerState :config config :activeProjects (list) :activeLanes (mapEmpty))

fn removeStr items: (List Str) target: Str -> (List Str)
  (if (listEmpty? items) (list) (let [(h (optionOr (listHead items) "")) (tl (optionOr (listTail items) (list)))] (if (= h target) (removeStr tl target) (cons h (removeStr tl target)))))

fn schedulerReleaseProject sched: SchedulerState proj: Str -> SchedulerState
  (with sched :activeProjects (removeStr sched.activeProjects proj))

fn schedulerReleaseTask sched: SchedulerState store: ts/TaskStore taskId: Str -> SchedulerState
  (mt (ts/taskstoreGet store taskId)
    ((some task)
      (let [(proj task.projectPath)
            (lane task.lane)
            (schedP (schedulerReleaseProject sched proj))]
        (schedulerReleaseLane schedP lane)))
    ((none) sched))

fn schedulerReleaseLane sched: SchedulerState lane: Str -> SchedulerState
  (with sched :activeLanes (decLaneCount sched.activeLanes lane))

fn getLaneCount lanes: (Map Str I64) lane: Str -> I64
  (optionOr (mapGet lanes lane) 0)

fn incLaneCount lanes: (Map Str I64) lane: Str -> (Map Str I64)
  (let [(curr (getLaneCount lanes lane))] (mapSet lanes lane (+ curr 1)))

fn decLaneCount lanes: (Map Str I64) lane: Str -> (Map Str I64)
  (let [(curr (getLaneCount lanes lane))] (if (> curr 0) (mapSet lanes lane (- curr 1)) lanes))

fn taskInList? tasks: (List tt/TaskRecord) id: Str -> Bool
  (if (listEmpty? tasks) false (let [(h (optionOr (listHead tasks) (tt/taskRecordCreate "" "" "" (tt/priorityNormal) 0 ""))) (tl (optionOr (listTail tasks) (list)))] (if (= h.id id) true (taskInList? tl id))))

fn drainPassIdle! tasks: (List tt/TaskRecord) acc: DrainAccumulator -> DrainAccumulator
  (if (listEmpty? tasks) acc (let [(sched acc.sched) (store acc.store) (claimed acc.claimed) (task (optionOr (listHead tasks) (tt/taskRecordCreate "" "" "" (tt/priorityNormal) 0 ""))) (restTasks (optionOr (listTail tasks) (list))) (maxConc sched.config.maxConcurrent) (currActive (listLength sched.activeProjects)) (laneCount (getLaneCount sched.activeLanes task.lane)) (proj task.projectPath) (projBusy (listContains? sched.activeProjects proj))] (if (>= currActive maxConc) acc (if (or projBusy (> laneCount 0)) (drainPassIdle! restTasks acc) (let [(claimRes (ts/taskstoreClaim! store task.id))] (mt claimRes ((ok nextStore) (let [(nextProjects (cons proj sched.activeProjects)) (nextLanes (incLaneCount sched.activeLanes task.lane)) (nextSched (SchedulerState :config sched.config :activeProjects nextProjects :activeLanes nextLanes)) (claimedTask (tt/TaskRecord :id task.id :lane task.lane :projectPath proj :state (tt/stateRouting) :priority task.priority :createdAt task.createdAt :updatedAt task.updatedAt :payload task.payload)) (nextClaimed (listAppend claimed (list claimedTask))) (nextAcc (DrainAccumulator :sched nextSched :store nextStore :claimed nextClaimed))] (drainPassIdle! restTasks nextAcc))) ((err _) (drainPassIdle! restTasks acc))))))))

fn drainPassBusy! tasks: (List tt/TaskRecord) acc: DrainAccumulator -> DrainAccumulator
  (if (listEmpty? tasks) acc (let [(sched acc.sched) (store acc.store) (claimed acc.claimed) (task (optionOr (listHead tasks) (tt/taskRecordCreate "" "" "" (tt/priorityNormal) 0 ""))) (restTasks (optionOr (listTail tasks) (list))) (maxConc sched.config.maxConcurrent) (currActive (listLength sched.activeProjects)) (proj task.projectPath) (projBusy (listContains? sched.activeProjects proj)) (alreadyClaimed (taskInList? claimed task.id))] (if (>= currActive maxConc) acc (if (or projBusy alreadyClaimed) (drainPassBusy! restTasks acc) (let [(claimRes (ts/taskstoreClaim! store task.id))] (mt claimRes ((ok nextStore) (let [(nextProjects (cons proj sched.activeProjects)) (nextLanes (incLaneCount sched.activeLanes task.lane)) (nextSched (SchedulerState :config sched.config :activeProjects nextProjects :activeLanes nextLanes)) (claimedTask (tt/TaskRecord :id task.id :lane task.lane :projectPath proj :state (tt/stateRouting) :priority task.priority :createdAt task.createdAt :updatedAt task.updatedAt :payload task.payload)) (nextClaimed (listAppend claimed (list claimedTask))) (nextAcc (DrainAccumulator :sched nextSched :store nextStore :claimed nextClaimed))] (drainPassBusy! restTasks nextAcc))) ((err _) (drainPassBusy! restTasks acc))))))))

fn schedulerDrain! sched: SchedulerState store: ts/TaskStore -> (Result DrainResult Str)
  (let [(queued (ts/taskstoreListQueued store)) (initAcc (DrainAccumulator :sched sched :store store :claimed (list))) (accIdle (drainPassIdle! queued initAcc)) (finalAcc (drainPassBusy! queued accIdle))] (ok (DrainResult :scheduler finalAcc.sched :store finalAcc.store :claimedTasks finalAcc.claimed)))

fn isReapableState? state: tt/TaskState -> Bool
  (mt state ((stateRouting) true) ((stateClarification) true) ((stateReady) true) ((stateExecuting) true) ((stateVerifying) true) (_ false))

fn countTrailingRetries tokens: (List Str) acc: I64 -> I64
  (if (listEmpty? tokens)
    acc
    (let [(lastIdx (- (listLength tokens) 1))
          (lastTok (optionOr (listGet tokens lastIdx) ""))
          (rest (optionOr (listSlice tokens 0 lastIdx) (list)))]
      (if (= lastTok ":retry")
        (countTrailingRetries rest (+ acc 1))
        acc)))

fn getTaskRetryCount payload: Str -> I64
  (let [(tokens (stringSplit payload " "))]
    (countTrailingRetries tokens 0))

fn appendRetryTag payload: Str -> Str
  (str payload " :retry")

fn hasNoRemainingDeps? node: d/TaskNode remaining: (List Str) -> Bool
  (fold (fn [(ok Bool) (depId Str)] -> Bool
          (and ok (not (listContains? remaining depId))))
        true node.dependencies)

fn kahnAcyclicLoop remainingNodes: (List d/TaskNode) remainingIds: (List Str) maxIters: I64 -> Bool
  (if (listEmpty? remainingIds)
    true
    (if (<= maxIters 0)
      false
      (let [(readyNodes (filter (fn [(n d/TaskNode)] (hasNoRemainingDeps? n remainingIds)) remainingNodes))]
        (if (listEmpty? readyNodes)
          false
          (let [(readyNode (optionOr (listHead readyNodes) (d/TaskNode :id "" :title "" :state (d/taskPending) :dependencies (list) :premises (list))))
                (readyId readyNode.id)
                (nextIds (removeStr remainingIds readyId))
                (nextNodes (filter (fn [(n d/TaskNode)] (not (= n.id readyId))) remainingNodes))]
            (kahnAcyclicLoop nextNodes nextIds (- maxIters 1)))))))

fn validateDagAcyclic dag: d/TaskDag -> Bool
  (let [(nodes dag.nodes)
        (nodeIds (map (fn [(n d/TaskNode)] n.id) nodes))
        (len (listLength nodeIds))]
    (if (<= len 1)
      (if (= len 1)
        (let [(singleNode (optionOr (listHead nodes) (d/TaskNode :id "" :title "" :state (d/taskPending) :dependencies (list) :premises (list))))]
          (not (listContains? singleNode.dependencies singleNode.id)))
        true)
      (kahnAcyclicLoop nodes nodeIds (+ len 2))))

fn reapTasks! tasks: (List tt/TaskRecord) sched: SchedulerState store: ts/TaskStore nowMs: I64 reapedCount: I64 maxRetries: I64 -> ReapResult
  (if (listEmpty? tasks)
    (ReapResult :scheduler sched :store store :reapedCount reapedCount)
    (let [(task (optionOr (listHead tasks) (tt/taskRecordCreate "" "" "" (tt/priorityNormal) 0 "")))
          (restTasks (optionOr (listTail tasks) (list)))
          (staleTimeout sched.config.staleTimeoutMs)
          (elapsed (- nowMs task.updatedAt))
          (isStale (and (isReapableState? task.state) (> elapsed staleTimeout)))]
      (if isStale
        (let [(curRetries (getTaskRetryCount task.payload))]
          (if (>= curRetries maxRetries)
            (let [(deadState (if (sm/validTransition? task.state (tt/stateFailed)) (tt/stateFailed) (tt/stateCancelled)))
                  (transRes (ts/taskstoreTransition! store task.id deadState nowMs))]
              (mt transRes
                ((ok nextStore)
                  (let [(nextProjects (removeStr sched.activeProjects task.projectPath))
                        (nextLanes (decLaneCount sched.activeLanes task.lane))
                        (nextSched (with sched :activeProjects nextProjects :activeLanes nextLanes))]
                    (reapTasks! restTasks nextSched nextStore nowMs (+ reapedCount 1) maxRetries)))
                ((err _)
                  (reapTasks! restTasks sched store nowMs reapedCount maxRetries))))
            (let [(transRes (ts/taskstoreTransition! store task.id (tt/stateQueued) nowMs))]
              (mt transRes
                ((ok nextStore)
                  (let [(qTask (optionOr (ts/taskstoreGet nextStore task.id) task))
                        (taggedTask (tt/TaskRecord
                                      :id qTask.id
                                      :lane qTask.lane
                                      :projectPath qTask.projectPath
                                      :state qTask.state
                                      :priority qTask.priority
                                      :createdAt qTask.createdAt
                                      :updatedAt qTask.updatedAt
                                      :payload (appendRetryTag qTask.payload)))
                        (putRes (ts/taskstorePut! nextStore taggedTask))
                        (finalStore (resultOr putRes nextStore))
                        (nextProjects (removeStr sched.activeProjects task.projectPath))
                        (nextLanes (decLaneCount sched.activeLanes task.lane))
                        (nextSched (with sched :activeProjects nextProjects :activeLanes nextLanes))]
                    (reapTasks! restTasks nextSched finalStore nowMs (+ reapedCount 1) maxRetries)))
                ((err _)
                  (reapTasks! restTasks sched store nowMs reapedCount maxRetries))))))
        (reapTasks! restTasks sched store nowMs reapedCount maxRetries))))

fn schedulerReapStaleWithMaxRetries! sched: SchedulerState store: ts/TaskStore currentTimeMs: I64 maxRetries: I64 -> (Result ReapResult Str)
  (let [(allTasks (mapValues store.tasks))
        (result (reapTasks! allTasks sched store currentTimeMs 0 maxRetries))]
    (ok result))

fn schedulerReapStaleWithEpoch! sched: SchedulerState store: ts/TaskStore currentTimeMs: I64 maxRetries: I64 claimEpoch: I64 -> (Result ReapResult Str)
  (schedulerReapStaleWithMaxRetries! sched store currentTimeMs maxRetries)

fn schedulerReapStale! sched: SchedulerState store: ts/TaskStore currentTimeMs: I64 -> (Result ReapResult Str)
  (schedulerReapStaleWithEpoch! sched store currentTimeMs 3 0)
