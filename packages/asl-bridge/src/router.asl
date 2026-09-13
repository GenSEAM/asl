(module asl-bridge/router
  :d "Workload execution tier router for AgentScript 3-tier execution matrix."
  :x [routeWorkload
      driverTier
      planQuery
      planCustom
      isWasmTier?
      isHostTier?
      isMicrovmTier?]
  :i [(ports :a p)])

(df routeWorkload [(op Str) (hasRawSockets Bool) (needsGpu Bool)] -> p/TierKind
  :d "Routes workload operation to the appropriate execution tier based on capabilities."
  (cond
    (needsGpu (p/tierMicrovm))
    (hasRawSockets (p/tierHostIpc))
    ((= op "gpu-compute") (p/tierMicrovm))
    ((= op "cuda") (p/tierMicrovm))
    ((= op "microvm") (p/tierMicrovm))
    ((= op "legacy-binary") (p/tierMicrovm))
    ((= op "host-ipc") (p/tierHostIpc))
    ((= op "socket-stream") (p/tierHostIpc))
    ((= op "system-tool") (p/tierHostIpc))
    ((= op "shell") (p/tierHostIpc))
    (:else (p/tierWasmSandbox))))

(df driverTier [(drv p/DriverKind)] -> p/TierKind
  :d "Maps database driver capability kind to default execution tier."
  (mt drv
    ((p/drvSqliteWasm) (p/tierWasmSandbox))
    ((p/drvPgSocket) (p/tierHostIpc))
    ((p/drvMysql) (p/tierHostIpc))
    ((p/drvAgentbusIpc) (p/tierHostIpc))))

(df planQuery [(sql Str) (drv p/DriverKind) (params (List Str))] -> p/QueryPlan
  :d "Constructs a QueryPlan automatically routed to the driver default tier."
  (p/makeQueryPlan sql (driverTier drv) params))

(df planCustom [(sql Str) (tier p/TierKind) (params (List Str))] -> p/QueryPlan
  :d "Constructs a QueryPlan explicitly targeted to a specific execution tier."
  (p/makeQueryPlan sql tier params))

(df isWasmTier? [(tk p/TierKind)] -> Bool
  :d "Checks if tier is tier-wasm-sandbox."
  (mt tk
    ((p/tierWasmSandbox) true)
    ((p/tierHostIpc) false)
    ((p/tierMicrovm) false)))

(df isHostTier? [(tk p/TierKind)] -> Bool
  :d "Checks if tier is tier-host-ipc."
  (mt tk
    ((p/tierHostIpc) true)
    ((p/tierWasmSandbox) false)
    ((p/tierMicrovm) false)))

(df isMicrovmTier? [(tk p/TierKind)] -> Bool
  :d "Checks if tier is tier-microvm."
  (mt tk
    ((p/tierMicrovm) true)
    ((p/tierWasmSandbox) false)
    ((p/tierHostIpc) false)))
