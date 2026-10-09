(module aslAgentCore/omniDaemon
  :x [DaemonStatus DaemonConfig DaemonState
      daemonBooting daemonRunning daemonDraining daemonStopped
      daemonInit daemonTick daemonShutdown daemonDispatchFiber daemonDispatchWorker formatDaemonStatus]
  :i [(asl/packages/asl-agent-core/src/fiberPool :a fp)
      (asl/packages/asl-agent-core/src/workerSupervisor :a ws)
      (asl/packages/asl-agent-core/src/fastKnowledgeCache :a kc)])

(enum DaemonStatus
  (:c daemonBooting [] "Initializing memory caches, socket listeners, and worker pools")
  (:c daemonRunning [] "Actively processing multi-protocol ingress and scheduler ticks")
  (:c daemonDraining [] "Rejecting new ingress, finishing in-flight tasks")
  (:c daemonStopped [] "All workers reaped, sockets closed, daemon cleanly shut down"))

(schema DaemonConfig
  (:f socketPath Str)
  (:f httpPort I64)
  (:f maxFibers I64)
  (:f maxWorkers I64)
  (:f limitsCfg ws/SupervisorLimitsConfig))

(schema DaemonState
  (:f cfg DaemonConfig)
  (:f status DaemonStatus)
  (:f fibers fp/FiberPool)
  (:f workers ws/WorkerPool)
  (:f cache kc/KnowledgeSnapshot)
  (:f activeIngressChannels (List Str))
  (:f lastTickMs I64))

fn daemonInit cfg: DaemonConfig nowMs: I64 -> DaemonState
  (DaemonState
    :cfg cfg
    :status (daemonRunning)
    :fibers (fp/fiberPoolCreate cfg.maxFibers)
    :workers (ws/workerPoolCreate cfg.limitsCfg)
    :cache (kc/knowledgeCacheCreate)
    :activeIngressChannels (list "unix-socket" "http-rest" "terminal-cli" "voice-stream")
    :lastTickMs nowMs)

fn daemonDispatchFiber state: DaemonState prio: fp/FiberPriority directive: Str nowMs: I64 -> (Pair DaemonState Str)
  (let [(spawnRes (fp/fiberSpawn state.fibers prio directive nowMs))
        (updatedFibers (pairFirst spawnRes))
        (fId (pairSecond spawnRes))]
    (pair
      (with state :fibers updatedFibers :lastTickMs nowMs)
      fId))

fn daemonDispatchWorker state: DaemonState mode: ws/WorkerSandboxMode owns: (List Str) pid: I64 nowMs: I64 -> (Pair DaemonState Str)
  (let [(spawnRes (ws/workerSpawn state.workers mode owns pid nowMs))
        (updatedWorkers (pairFirst spawnRes))
        (wId (pairSecond spawnRes))]
    (pair
      (with state :workers updatedWorkers :lastTickMs nowMs)
      wId))

fn daemonTick state: DaemonState nowMs: I64 -> DaemonState
  (let [(limitsRes (ws/workerCheckLimits state.workers nowMs))
        (checkedWorkers (pairFirst limitsRes))]
    (with state :workers checkedWorkers :lastTickMs nowMs))

fn daemonShutdown state: DaemonState -> DaemonState
  (with state :status (daemonStopped) :activeIngressChannels (list))

fn formatDaemonStatus state: DaemonState -> Str
  (let [(stStr (mt state.status
                 ((daemonBooting) "booting")
                 ((daemonRunning) "running")
                 ((daemonDraining) "draining")
                 ((daemonStopped) "stopped")))]
    (str "(:daemon-status :state :" stStr
         " :socket \"" state.cfg.socketPath "\""
         " :http-port " (stringFromInt64 state.cfg.httpPort)
         " :fibers-active " (stringFromInt64 (mapSize state.fibers.activeFibers))
         " :workers-active " (stringFromInt64 (mapSize state.workers.workers))
         " :cache-symbols " (stringFromInt64 (mapSize state.cache.symbols))
         " :ingress-channels " (stringFromInt64 (listLength state.activeIngressChannels)) ")"))
