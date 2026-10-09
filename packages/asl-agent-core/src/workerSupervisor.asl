(module aslAgentCore/workerSupervisor
  :x [WorkerStatus WorkerSandboxMode workerSpawning workerIdle workerBusy workerStalled workerCrashed
      sandboxReadOnly sandboxWorkspaceWrite sandboxDangerFull
      SupervisorLimitsConfig WorkerRecord WorkerPool
      workerPoolCreate workerSpawn workerHeartbeat workerCheckLimits workerReap
      workerIsStalled? formatWorkerRecord]
  :i [])

(enum WorkerStatus
  (:c workerSpawning [] "Process fork initiated, awaiting initial handshake")
  (:c workerIdle [] "Worker healthy and awaiting task assignment")
  (:c workerBusy [] "Actively executing mutating build or test gate")
  (:c workerStalled [] "Exceeded 10s sliding idle threshold (trapped on STDIN)")
  (:c workerCrashed [] "Process terminated unexpectedly with non-zero signal/OOM"))

(enum WorkerSandboxMode
  (:c sandboxReadOnly [] "Read-only filesystem, network denied")
  (:c sandboxWorkspaceWrite [] "Write access strictly restricted to declared :owns paths")
  (:c sandboxDangerFull [] "Unrestricted host access (requires signed V0 confirmation)"))

(schema SupervisorLimitsConfig
  (:f slidingIdleMs I64)
  (:f maxWallClockMs I64)
  (:f maxMemMb I64))

(schema WorkerRecord
  (:f workerId Str)
  (:f pid I64)
  (:f sandboxMode WorkerSandboxMode)
  (:f owns (List Str))
  (:f status WorkerStatus)
  (:f startedAt I64)
  (:f lastActivityAt I64)
  (:f memUsageMb I64))

(schema WorkerPool
  (:f cfg SupervisorLimitsConfig)
  (:f workers (Map Str WorkerRecord))
  (:f idleWorkers (List Str)))

fn workerPoolCreate cfg: SupervisorLimitsConfig -> WorkerPool
  (WorkerPool
    :cfg cfg
    :workers (mapEmpty)
    :idleWorkers (list))

fn workerSpawn pool: WorkerPool mode: WorkerSandboxMode ownsPaths: (List Str) pid: I64 nowMs: I64 -> (Pair WorkerPool Str)
  (let [(wId (str "worker-" (stringFromInt64 (+ (mapSize pool.workers) 1))))
        (rec (WorkerRecord
               :workerId wId
               :pid pid
               :sandboxMode mode
               :owns ownsPaths
               :status (workerBusy)
               :startedAt nowMs
               :lastActivityAt nowMs
               :memUsageMb 32))
        (updatedWorkers (mapSet pool.workers wId rec))]
    (pair
      (with pool :workers updatedWorkers)
      wId))

fn workerHeartbeat pool: WorkerPool wId: Str nowMs: I64 memMb: I64 -> WorkerPool
  (mt (mapGet pool.workers wId)
    ((some rec)
      (let [(updatedRec (WorkerRecord
                          :workerId rec.workerId
                          :pid rec.pid
                          :sandboxMode rec.sandboxMode
                          :owns rec.owns
                          :status (workerBusy)
                          :startedAt rec.startedAt
                          :lastActivityAt nowMs
                          :memUsageMb memMb))
            (updatedWorkers (mapSet pool.workers wId updatedRec))]
        (with pool :workers updatedWorkers)))
    ((none) pool))

fn workerIsStalled? rec: WorkerRecord slidingIdleLimitMs: I64 nowMs: I64 -> Bool
  (let [(lastAct rec.lastActivityAt)
        (elapsed (- nowMs lastAct))]
    (> elapsed slidingIdleLimitMs))

fn workerCheckLimits pool: WorkerPool nowMs: I64 -> (Pair WorkerPool (List Str))
  (let [(cfg pool.cfg)
        (slidingLimit cfg.slidingIdleMs)
        (stalledIds
          (fold (fn [(acc (List Str)) (wId Str)] -> (List Str)
                  (mt (mapGet pool.workers wId)
                    ((some rec)
                      (if (workerIsStalled? rec slidingLimit nowMs)
                        (listAppend acc (list wId))
                        acc))
                    ((none) acc)))
                (list)
                (mapKeys pool.workers)))
        (updatedWorkers
          (fold (fn [(acc (Map Str WorkerRecord)) (sId Str)] -> (Map Str WorkerRecord)
                  (mt (mapGet acc sId)
                    ((some rec)
                      (mapSet acc sId
                               (WorkerRecord
                                 :workerId rec.workerId
                                 :pid rec.pid
                                 :sandboxMode rec.sandboxMode
                                 :owns rec.owns
                                 :status (workerStalled)
                                 :startedAt rec.startedAt
                                 :lastActivityAt rec.lastActivityAt
                                 :memUsageMb rec.memUsageMb)))
                    ((none) acc)))
                pool.workers
                stalledIds))]
    (pair
      (with pool :cfg cfg :workers updatedWorkers)
      stalledIds))

fn workerReap pool: WorkerPool wId: Str -> WorkerPool
  (let [(updatedWorkers (mapRemove pool.workers wId))
        (updatedIdle (filter (fn [(id Str)] -> Bool (not (= id wId))) pool.idleWorkers))]
    (with pool :workers updatedWorkers :idleWorkers updatedIdle))

fn formatWorkerRecord rec: WorkerRecord -> Str
  (str "(:worker-record :id \"" rec.workerId "\" :pid " (stringFromInt64 rec.pid)
       " :owns-count " (stringFromInt64 (listLength rec.owns))
       " :mem-mb " (stringFromInt64 rec.memUsageMb) ")")
