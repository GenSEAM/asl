(module aslAgentCore/tests/omniDaemonTest
  :x [testDaemonInit testDaemonDispatchFiber testDaemonDispatchWorker testDaemonTick testDaemonShutdown runTests]
  :i [(asl/packages/asl-agent-core/src/omniDaemon :a od)
      (asl/packages/asl-agent-core/src/fiberPool :a fp)
      (asl/packages/asl-agent-core/src/workerSupervisor :a ws)])

fn testDaemonInit -> Bool
  (let [(wCfg (ws/SupervisorLimitsConfig :slidingIdleMs 10000 :maxWallClockMs 900000 :maxMemMb 1024))
        (dCfg (od/DaemonConfig :socketPath "/tmp/test-daemon.sock" :httpPort 8765 :maxFibers 32 :maxWorkers 8 :limitsCfg wCfg))
        (st (od/daemonInit dCfg 1000))]
    (assert (= (listLength st.activeIngressChannels) 4) "Daemon must open 4 ingress channels")
    (assert (= st.cfg.httpPort 8765) "HTTP port is 8765")
    (assert (= (mapSize st.fibers.activeFibers) 0) "Zero initial fibers")
    (assert (= (mapSize st.workers.workers) 0) "Zero initial workers")
    true)

fn testDaemonDispatchFiber -> Bool
  (let [(wCfg (ws/SupervisorLimitsConfig :slidingIdleMs 10000 :maxWallClockMs 900000 :maxMemMb 1024))
        (dCfg (od/DaemonConfig :socketPath "/tmp/test-daemon.sock" :httpPort 8765 :maxFibers 32 :maxWorkers 8 :limitsCfg wCfg))
        (st (od/daemonInit dCfg 1000))
        (dispRes (od/daemonDispatchFiber st (fp/prioInteractive) "(search 'test)" 1050))
        (nextSt (pairFirst dispRes))
        (fId (pairSecond dispRes))]
    (assert (= (mapSize nextSt.fibers.activeFibers) 1) "Daemon dispatched 1 in-process fiber")
    (assert (stringStartsWith? fId "fiber-") "Fiber ID starts with fiber-")
    true)

fn testDaemonDispatchWorker -> Bool
  (let [(wCfg (ws/SupervisorLimitsConfig :slidingIdleMs 10000 :maxWallClockMs 900000 :maxMemMb 1024))
        (dCfg (od/DaemonConfig :socketPath "/tmp/test-daemon.sock" :httpPort 8765 :maxFibers 32 :maxWorkers 8 :limitsCfg wCfg))
        (st (od/daemonInit dCfg 1000))
        (dispRes (od/daemonDispatchWorker st (ws/sandboxWorkspaceWrite) (list "src/compiler.asl") 98765 1100))
        (nextSt (pairFirst dispRes))
        (wId (pairSecond dispRes))]
    (assert (= (mapSize nextSt.workers.workers) 1) "Daemon dispatched 1 out-of-process worker")
    (assert (stringStartsWith? wId "worker-") "Worker ID starts with worker-")
    true)

fn testDaemonTick -> Bool
  (let [(wCfg (ws/SupervisorLimitsConfig :slidingIdleMs 10000 :maxWallClockMs 900000 :maxMemMb 1024))
        (dCfg (od/DaemonConfig :socketPath "/tmp/test-daemon.sock" :httpPort 8765 :maxFibers 32 :maxWorkers 8 :limitsCfg wCfg))
        (st (od/daemonInit dCfg 1000))
        (ticked (od/daemonTick st 2000))]
    (assert (= ticked.lastTickMs 2000) "Daemon tick advances lastTickMs to 2000")
    true)

fn testDaemonShutdown -> Bool
  (let [(wCfg (ws/SupervisorLimitsConfig :slidingIdleMs 10000 :maxWallClockMs 900000 :maxMemMb 1024))
        (dCfg (od/DaemonConfig :socketPath "/tmp/test-daemon.sock" :httpPort 8765 :maxFibers 32 :maxWorkers 8 :limitsCfg wCfg))
        (st (od/daemonInit dCfg 1000))
        (stopped (od/daemonShutdown st))]
    (assert (= (listLength stopped.activeIngressChannels) 0) "Ingress channels closed on shutdown")
    (assert (stringContains? (od/formatDaemonStatus stopped) ":stopped") "Status string indicates :stopped")
    true)

fn runTests -> Bool
  (do
    (assert (testDaemonInit) "Daemon init must pass")
    (assert (testDaemonDispatchFiber) "Daemon dispatch fiber must pass")
    (assert (testDaemonDispatchWorker) "Daemon dispatch worker must pass")
    (assert (testDaemonTick) "Daemon tick must pass")
    (assert (testDaemonShutdown) "Daemon shutdown must pass")
    true)
