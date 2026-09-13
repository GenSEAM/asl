(module asl-bridge/ports
  :d "Polyglot capability ports, database drivers, execution tiers, and query models."
  :x [DriverKind
      TierKind
      DbColumn
      TableDef
      QueryPlan
      DbResult
      makeDbColumn
      makeTableDef
      makeQueryPlan
      makeDbResult
      driverKindToStr
      tierKindToStr
      strToDriverKind
      strToTierKind]
  :i [])

(dfe DriverKind
  (:c drvSqliteWasm [] "In-memory WebAssembly SQLite execution driver")
  (:c drvPgSocket   [] "Host network socket Postgres connection pool driver")
  (:c drvMysql       [] "Host network socket MySQL connection pool driver")
  (:c drvAgentbusIpc [] "Agent-Bus IPC transport channel driver"))

(dfe TierKind
  (:c tierWasmSandbox [] "Tier 1: Sub-millisecond in-memory Wasm sandbox")
  (:c tierHostIpc     [] "Tier 2: Host process / streaming sockets / system tools")
  (:c tierMicrovm      [] "Tier 3: MicroVM / Firecracker / GPU / CUDA workload"))

(dfs DbColumn
  (:f name Str "Column identifier name")
  (:f colType Str "Abstract data type: text, i64, f64, bool, timestamp")
  (:f nullable Bool "True if column permits NULL values")
  (:f isPk Bool "True if column is part of PRIMARY KEY"))

(dfs TableDef
  (:f name Str "Target database table name")
  (:f columns (List DbColumn) "List of column specifications"))

(dfs QueryPlan
  (:f sql Str "Rendered SQL query statement")
  (:f tier TierKind "Workload execution tier targeted")
  (:f params (List Str) "Positional query parameter values"))

(dfs DbResult
  (:f rows (List (Map Str Str)) "Tabular row results as list of column-value maps")
  (:f affected I64 "Number of affected rows by mutation"))

(df makeDbColumn [(name Str) (colType Str) (nullable Bool) (isPk Bool)] -> DbColumn
  :d "Constructs a DbColumn record."
  (DbColumn
    :name name
    :colType colType
    :nullable nullable
    :isPk isPk))

(df makeTableDef [(name Str) (columns (List DbColumn))] -> TableDef
  :d "Constructs a TableDef record."
  (TableDef
    :name name
    :columns columns))

(df makeQueryPlan [(sql Str) (tier TierKind) (params (List Str))] -> QueryPlan
  :d "Constructs a QueryPlan record."
  (QueryPlan
    :sql sql
    :tier tier
    :params params))

(df makeDbResult [(rows (List (Map Str Str))) (affected I64)] -> DbResult
  :d "Constructs a DbResult record."
  (DbResult
    :rows rows
    :affected affected))

(df driverKindToStr [(dk DriverKind)] -> Str
  :d "Converts DriverKind to canonical string identifier."
  (mt dk
    ((drvSqliteWasm) "drv-sqlite-wasm")
    ((drvPgSocket) "drv-pg-socket")
    ((drvMysql) "drv-mysql")
    ((drvAgentbusIpc) "drv-agentbus-ipc")))

(df tierKindToStr [(tk TierKind)] -> Str
  :d "Converts TierKind to canonical string identifier."
  (mt tk
    ((tierWasmSandbox) "tier-wasm-sandbox")
    ((tierHostIpc) "tier-host-ipc")
    ((tierMicrovm) "tier-microvm")))

(df strToDriverKind [(s Str)] -> (Option DriverKind)
  :d "Parses string into DriverKind enum variant."
  (cond
    ((= s "drv-sqlite-wasm") (some (drvSqliteWasm)))
    ((= s "drv-pg-socket") (some (drvPgSocket)))
    ((= s "drv-mysql") (some (drvMysql)))
    ((= s "drv-agentbus-ipc") (some (drvAgentbusIpc)))
    ((= s "sqlite") (some (drvSqliteWasm)))
    ((= s "postgres") (some (drvPgSocket)))
    ((= s "mysql") (some (drvMysql)))
    ((= s "agentbus") (some (drvAgentbusIpc)))
    (:else (none))))

(df strToTierKind [(s Str)] -> (Option TierKind)
  :d "Parses string into TierKind enum variant."
  (cond
    ((= s "tier-wasm-sandbox") (some (tierWasmSandbox)))
    ((= s "tier-host-ipc") (some (tierHostIpc)))
    ((= s "tier-microvm") (some (tierMicrovm)))
    ((= s "wasm") (some (tierWasmSandbox)))
    ((= s "host") (some (tierHostIpc)))
    ((= s "microvm") (some (tierMicrovm)))
    (:else (none))))
