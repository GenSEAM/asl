(module asl-bridge/ports
  :d "Polyglot capability ports, database drivers, execution tiers, and query models."
  :x [DriverKind
      TierKind
      DbColumn
      TableDef
      QueryPlan
      DbResult
      make-db-column
      make-table-def
      make-query-plan
      make-db-result
      driver-kind-to-str
      tier-kind-to-str
      str-to-driver-kind
      str-to-tier-kind]
  :i [])

(dfe DriverKind
  (:c drv-sqlite-wasm [] "In-memory WebAssembly SQLite execution driver")
  (:c drv-pg-socket   [] "Host network socket Postgres connection pool driver")
  (:c drv-mysql       [] "Host network socket MySQL connection pool driver")
  (:c drv-agentbus-ipc [] "Agent-Bus IPC transport channel driver"))

(dfe TierKind
  (:c tier-wasm-sandbox [] "Tier 1: Sub-millisecond in-memory Wasm sandbox")
  (:c tier-host-ipc     [] "Tier 2: Host process / streaming sockets / system tools")
  (:c tier-microvm      [] "Tier 3: MicroVM / Firecracker / GPU / CUDA workload"))

(dfs DbColumn
  (:f name Str "Column identifier name")
  (:f col-type Str "Abstract data type: text, i64, f64, bool, timestamp")
  (:f nullable Bool "True if column permits NULL values")
  (:f is-pk Bool "True if column is part of PRIMARY KEY"))

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

(df make-db-column [(name Str) (col-type Str) (nullable Bool) (is-pk Bool)] -> DbColumn
  :d "Constructs a DbColumn record."
  (DbColumn
    :name name
    :col-type col-type
    :nullable nullable
    :is-pk is-pk))

(df make-table-def [(name Str) (columns (List DbColumn))] -> TableDef
  :d "Constructs a TableDef record."
  (TableDef
    :name name
    :columns columns))

(df make-query-plan [(sql Str) (tier TierKind) (params (List Str))] -> QueryPlan
  :d "Constructs a QueryPlan record."
  (QueryPlan
    :sql sql
    :tier tier
    :params params))

(df make-db-result [(rows (List (Map Str Str))) (affected I64)] -> DbResult
  :d "Constructs a DbResult record."
  (DbResult
    :rows rows
    :affected affected))

(df driver-kind-to-str [(dk DriverKind)] -> Str
  :d "Converts DriverKind to canonical string identifier."
  (mt dk
    ((drv-sqlite-wasm) "drv-sqlite-wasm")
    ((drv-pg-socket) "drv-pg-socket")
    ((drv-mysql) "drv-mysql")
    ((drv-agentbus-ipc) "drv-agentbus-ipc")))

(df tier-kind-to-str [(tk TierKind)] -> Str
  :d "Converts TierKind to canonical string identifier."
  (mt tk
    ((tier-wasm-sandbox) "tier-wasm-sandbox")
    ((tier-host-ipc) "tier-host-ipc")
    ((tier-microvm) "tier-microvm")))

(df str-to-driver-kind [(s Str)] -> (Option DriverKind)
  :d "Parses string into DriverKind enum variant."
  (cond
    ((= s "drv-sqlite-wasm") (some (drv-sqlite-wasm)))
    ((= s "drv-pg-socket") (some (drv-pg-socket)))
    ((= s "drv-mysql") (some (drv-mysql)))
    ((= s "drv-agentbus-ipc") (some (drv-agentbus-ipc)))
    ((= s "sqlite") (some (drv-sqlite-wasm)))
    ((= s "postgres") (some (drv-pg-socket)))
    ((= s "mysql") (some (drv-mysql)))
    ((= s "agentbus") (some (drv-agentbus-ipc)))
    (:else (none))))

(df str-to-tier-kind [(s Str)] -> (Option TierKind)
  :d "Parses string into TierKind enum variant."
  (cond
    ((= s "tier-wasm-sandbox") (some (tier-wasm-sandbox)))
    ((= s "tier-host-ipc") (some (tier-host-ipc)))
    ((= s "tier-microvm") (some (tier-microvm)))
    ((= s "wasm") (some (tier-wasm-sandbox)))
    ((= s "host") (some (tier-host-ipc)))
    ((= s "microvm") (some (tier-microvm)))
    (:else (none))))
