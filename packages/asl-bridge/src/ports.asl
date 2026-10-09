(module asl-bridge/ports :x [DriverKind TierKind DbColumn TableDef QueryPlan DbResult makeDbColumn makeTableDef makeQueryPlan makeDbResult driverKindToStr tierKindToStr strToDriverKind strToTierKind] :i [])

(enum DriverKind (:c drvSqliteWasm [] "In-memory WebAssembly SQLite execution driver") (:c drvPgSocket [] "Host network socket Postgres connection pool driver") (:c drvMysql [] "Host network socket MySQL connection pool driver") (:c drvAgentbusIpc [] "Agent-Bus IPC transport channel driver"))

(enum TierKind (:c tierWasmSandbox [] "Tier 1: Sub-millisecond in-memory Wasm sandbox") (:c tierHostIpc [] "Tier 2: Host process / streaming sockets / system tools") (:c tierMicrovm [] "Tier 3: MicroVM / Firecracker / GPU / CUDA workload"))

(schema DbColumn (:f name Str) (:f colType Str) (:f nullable Bool) (:f isPk Bool))

(schema TableDef (:f name Str) (:f columns (List DbColumn)))

(schema QueryPlan (:f sql Str) (:f tier TierKind) (:f params (List Str)))

(schema DbResult (:f rows (List (Map Str Str))) (:f affected I64))

fn makeDbColumn name: Str colType: Str nullable: Bool isPk: Bool -> DbColumn
  (DbColumn :name name :colType colType :nullable nullable :isPk isPk)

fn makeTableDef name: Str columns: (List DbColumn) -> TableDef
  (TableDef :name name :columns columns)

fn makeQueryPlan sql: Str tier: TierKind params: (List Str) -> QueryPlan
  (QueryPlan :sql sql :tier tier :params params)

fn makeDbResult rows: (List (Map Str Str)) affected: I64 -> DbResult
  (DbResult :rows rows :affected affected)

fn driverKindToStr dk: DriverKind -> Str
  (mt dk ((drvSqliteWasm) "drv-sqlite-wasm") ((drvPgSocket) "drv-pg-socket") ((drvMysql) "drv-mysql") ((drvAgentbusIpc) "drv-agentbus-ipc"))

fn tierKindToStr tk: TierKind -> Str
  (mt tk ((tierWasmSandbox) "tier-wasm-sandbox") ((tierHostIpc) "tier-host-ipc") ((tierMicrovm) "tier-microvm"))

fn strToDriverKind s: Str -> (Option DriverKind)
  (cond ((= s "drv-sqlite-wasm") (some (drvSqliteWasm))) ((= s "drv-pg-socket") (some (drvPgSocket))) ((= s "drv-mysql") (some (drvMysql))) ((= s "drv-agentbus-ipc") (some (drvAgentbusIpc))) ((= s "sqlite") (some (drvSqliteWasm))) ((= s "postgres") (some (drvPgSocket))) ((= s "mysql") (some (drvMysql))) ((= s "agentbus") (some (drvAgentbusIpc))) (else (none)))

fn strToTierKind s: Str -> (Option TierKind)
  (cond ((= s "tier-wasm-sandbox") (some (tierWasmSandbox))) ((= s "tier-host-ipc") (some (tierHostIpc))) ((= s "tier-microvm") (some (tierMicrovm))) ((= s "wasm") (some (tierWasmSandbox))) ((= s "host") (some (tierHostIpc))) ((= s "microvm") (some (tierMicrovm))) (else (none)))
