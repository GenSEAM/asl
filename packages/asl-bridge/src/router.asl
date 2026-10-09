(module asl-bridge/router :x [routeWorkload driverTier planQuery planCustom isWasmTier? isHostTier? isMicrovmTier?] :i [(ports :a p)])

fn routeWorkload op: Str hasRawSockets: Bool needsGpu: Bool -> p/TierKind
  (cond (needsGpu (p/tierMicrovm)) (hasRawSockets (p/tierHostIpc)) ((= op "gpu-compute") (p/tierMicrovm)) ((= op "cuda") (p/tierMicrovm)) ((= op "microvm") (p/tierMicrovm)) ((= op "legacy-binary") (p/tierMicrovm)) ((= op "host-ipc") (p/tierHostIpc)) ((= op "socket-stream") (p/tierHostIpc)) ((= op "system-tool") (p/tierHostIpc)) ((= op "shell") (p/tierHostIpc)) (else (p/tierWasmSandbox)))

fn driverTier drv: p/DriverKind -> p/TierKind
  (mt drv ((p/drvSqliteWasm) (p/tierWasmSandbox)) ((p/drvPgSocket) (p/tierHostIpc)) ((p/drvMysql) (p/tierHostIpc)) ((p/drvAgentbusIpc) (p/tierHostIpc)))

fn planQuery sql: Str drv: p/DriverKind params: (List Str) -> p/QueryPlan
  (p/makeQueryPlan sql (driverTier drv) params)

fn planCustom sql: Str tier: p/TierKind params: (List Str) -> p/QueryPlan
  (p/makeQueryPlan sql tier params)

fn isWasmTier? tk: p/TierKind -> Bool
  (mt tk ((p/tierWasmSandbox) true) ((p/tierHostIpc) false) ((p/tierMicrovm) false))

fn isHostTier? tk: p/TierKind -> Bool
  (mt tk ((p/tierHostIpc) true) ((p/tierWasmSandbox) false) ((p/tierMicrovm) false))

fn isMicrovmTier? tk: p/TierKind -> Bool
  (mt tk ((p/tierMicrovm) true) ((p/tierWasmSandbox) false) ((p/tierHostIpc) false))
