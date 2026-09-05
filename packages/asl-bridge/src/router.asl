(module asl-bridge/router
  :d "Workload execution tier router for AgentScript 3-tier execution matrix."
  :x [route-workload
      driver-tier
      plan-query
      plan-custom
      is-wasm-tier?
      is-host-tier?
      is-microvm-tier?]
  :i [(ports :a p)])

(df route-workload [(op Str) (has-raw-sockets Bool) (needs-gpu Bool)] -> p/TierKind
  :d "Routes workload operation to the appropriate execution tier based on capabilities."
  (cond
    (needs-gpu (p/tier-microvm))
    (has-raw-sockets (p/tier-host-ipc))
    ((= op "gpu-compute") (p/tier-microvm))
    ((= op "cuda") (p/tier-microvm))
    ((= op "microvm") (p/tier-microvm))
    ((= op "legacy-binary") (p/tier-microvm))
    ((= op "host-ipc") (p/tier-host-ipc))
    ((= op "socket-stream") (p/tier-host-ipc))
    ((= op "system-tool") (p/tier-host-ipc))
    ((= op "shell") (p/tier-host-ipc))
    (:else (p/tier-wasm-sandbox))))

(df driver-tier [(drv p/DriverKind)] -> p/TierKind
  :d "Maps database driver capability kind to default execution tier."
  (mt drv
    ((p/drv-sqlite-wasm) (p/tier-wasm-sandbox))
    ((p/drv-pg-socket) (p/tier-host-ipc))
    ((p/drv-mysql) (p/tier-host-ipc))
    ((p/drv-agentbus-ipc) (p/tier-host-ipc))))

(df plan-query [(sql Str) (drv p/DriverKind) (params (List Str))] -> p/QueryPlan
  :d "Constructs a QueryPlan automatically routed to the driver default tier."
  (p/make-query-plan sql (driver-tier drv) params))

(df plan-custom [(sql Str) (tier p/TierKind) (params (List Str))] -> p/QueryPlan
  :d "Constructs a QueryPlan explicitly targeted to a specific execution tier."
  (p/make-query-plan sql tier params))

(df is-wasm-tier? [(tk p/TierKind)] -> Bool
  :d "Checks if tier is tier-wasm-sandbox."
  (mt tk
    ((p/tier-wasm-sandbox) true)
    ((p/tier-host-ipc) false)
    ((p/tier-microvm) false)))

(df is-host-tier? [(tk p/TierKind)] -> Bool
  :d "Checks if tier is tier-host-ipc."
  (mt tk
    ((p/tier-host-ipc) true)
    ((p/tier-wasm-sandbox) false)
    ((p/tier-microvm) false)))

(df is-microvm-tier? [(tk p/TierKind)] -> Bool
  :d "Checks if tier is tier-microvm."
  (mt tk
    ((p/tier-microvm) true)
    ((p/tier-wasm-sandbox) false)
    ((p/tier-host-ipc) false)))
