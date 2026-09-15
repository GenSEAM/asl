(module asl-bridge/test
  :d "Comprehensive unit tests for the Polyglot Bridge, schema transpiler, and workload execution router."
  :x [runTests
      sampleTable
      testPortsAndTypes
      testSchemaKysely
      testSchemaDrizzle
      testSchemaSqlalchemy
      testSchemaSeaorm
      testRouterWorkload
      testRouterPlanning]
  :i [(ports :a p) (schemaBridge :a sb) (router :a r)])

(df sampleTable [] -> p/TableDef
  :d "Constructs a sample TableDef record with diverse column types."
  (let [(c1 (p/makeDbColumn "id" "i64" false true))
        (c2 (p/makeDbColumn "name" "text" false false))
        (c3 (p/makeDbColumn "email" "text" true false))
        (c4 (p/makeDbColumn "is_active" "bool" false false))
        (c5 (p/makeDbColumn "score" "f64" true false))
        (cols (cons c1 (cons c2 (cons c3 (cons c4 (cons c5 (list)))))))]
    (p/makeTableDef "users" cols)))

(df testPortsAndTypes [] -> Bool
  :d "Verifies DbColumn, TableDef, QueryPlan, DbResult, and enum conversions."
  (let [(tbl (sampleTable))
        (pWasm (p/drvSqliteWasm))
        (pPg (p/drvPgSocket))
        (tW (p/tierWasmSandbox))
        (tH (p/tierHostIpc))
        (tM (p/tierMicrovm))
        (qp (p/makeQueryPlan "SELECT * FROM users" tW (cons "1" (list))))
        (row1 (map-set (map-empty) "id" "1"))
        (rows (cons row1 (list)))
        (res (p/makeDbResult rows 1))]
    (assert (= (.-name tbl) "users") "Table name must be users")
    (assert (= (list-length (.-columns tbl)) 5) "Columns count must be 5")
    (assert (= (p/driverKindToStr pWasm) "drv-sqlite-wasm") "Driver kind wasm must match")
    (assert (= (p/driverKindToStr pPg) "drv-pg-socket") "Driver kind pg must match")
    (assert (= (p/tierKindToStr tW) "tier-wasm-sandbox") "Tier wasm must match")
    (assert (= (p/tierKindToStr tH) "tier-host-ipc") "Tier host must match")
    (assert (= (p/tierKindToStr tM) "tier-microvm") "Tier microvm must match")
    (assert (= (.-sql qp) "SELECT * FROM users") "SQL must match")
    (assert (= (.-affected res) 1) "Affected rows must be 1")
    (assert (= (list-length (.-rows res)) 1) "Result rows count must be 1")
    true))

(df testSchemaKysely [] -> Bool
  :d "Verifies TypeScript Kysely interface transpilation."
  (let [(tbl (sampleTable))
        (out (sb/tableToKysely tbl))]
    (assert (string-contains? out "export interface UsersTable {") "Kysely interface must exist")
    (assert (string-contains? out "  id: number;") "id column must be number")
    (assert (string-contains? out "  name: string;") "name column must be string")
    (assert (string-contains? out "  email: string | null;") "email column must be nullable string")
    (assert (string-contains? out "  is_active: boolean;") "is_active column must be boolean")
    (assert (string-contains? out "  score: number | null;") "score column must be nullable number")
    true))

(df testSchemaDrizzle [] -> Bool
  :d "Verifies TypeScript Drizzle table definition transpilation."
  (let [(tbl (sampleTable))
        (out (sb/tableToDrizzle tbl))]
    (assert (string-contains? out "export const users = pgTable(\"users\", {") "pgTable must exist")
    (assert (string-contains? out "  id: integer(\"id\").primaryKey(),") "id primary key must exist")
    (assert (string-contains? out "  name: text(\"name\").notNull(),") "name notNull must exist")
    (assert (string-contains? out "  email: text(\"email\"),") "email text must exist")
    (assert (string-contains? out "  is_active: boolean(\"is_active\").notNull(),") "is_active notNull must exist")
    (assert (string-contains? out "  score: real(\"score\"),") "score real must exist")
    true))

(df testSchemaSqlalchemy [] -> Bool
  :d "Verifies Python SQLAlchemy 2.0 DeclarativeBase model transpilation."
  (let [(tbl (sampleTable))
        (out (sb/tableToSqlalchemy tbl))]
    (assert (string-contains? out "class Users(Base):") "Base class must exist")
    (assert (string-contains? out "__tablename__ = \"users\"") "tablename must exist")
    (assert (string-contains? out "id: Mapped[int] = mapped_column(primary_key=True)") "id mapped_column must exist")
    (assert (string-contains? out "name: Mapped[str] = mapped_column(nullable=False)") "name mapped_column must exist")
    (assert (string-contains? out "email: Mapped[Optional[str]] = mapped_column(nullable=True)") "email mapped_column must exist")
    (assert (string-contains? out "is_active: Mapped[bool] = mapped_column(nullable=False)") "is_active mapped_column must exist")
    (assert (string-contains? out "score: Mapped[Optional[float]] = mapped_column(nullable=True)") "score mapped_column must exist")
    true))

(df testSchemaSeaorm [] -> Bool
  :d "Verifies Rust SeaORM entity struct transpilation."
  (let [(tbl (sampleTable))
        (out (sb/tableToSeaorm tbl))]
    (assert (string-contains? out "#[derive(Clone, Debug, PartialEq, DeriveEntityModel)]") "DeriveEntityModel must exist")
    (assert (string-contains? out "#[sea_orm(table_name = \"users\")]") "table_name must exist")
    (assert (string-contains? out "pub struct Model {") "Model struct must exist")
    (assert (string-contains? out "#[sea_orm(primary_key)]") "primary_key must exist")
    (assert (string-contains? out "pub id: i64,") "pub id must exist")
    (assert (string-contains? out "pub name: String,") "pub name must exist")
    (assert (string-contains? out "pub email: Option<String>,") "pub email must exist")
    (assert (string-contains? out "pub is_active: bool,") "pub is_active must exist")
    (assert (string-contains? out "pub score: Option<f64>,") "pub score must exist")
    true))

(df testRouterWorkload [] -> Bool
  :d "Verifies workload router tiers based on capabilities and ops."
  (let [(t1 (r/routeWorkload "compute" false false))
        (t2 (r/routeWorkload "query" true false))
        (t3 (r/routeWorkload "train-model" false true))
        (t4 (r/routeWorkload "gpu-compute" false false))
        (t5 (r/routeWorkload "host-ipc" false false))]
    (assert (r/isWasmTier? t1) "t1 must be wasm tier")
    (assert (r/isHostTier? t2) "t2 must be host tier")
    (assert (r/isMicrovmTier? t3) "t3 must be microvm tier")
    (assert (r/isMicrovmTier? t4) "t4 must be microvm tier")
    (assert (r/isHostTier? t5) "t5 must be host tier")
    true))

(df testRouterPlanning [] -> Bool
  :d "Verifies query planning defaults per driver kind."
  (let [(pWasm (r/planQuery "SELECT 1" (p/drvSqliteWasm) (list)))
        (pPg (r/planQuery "SELECT 1" (p/drvPgSocket) (list)))
        (pMy (r/planQuery "SELECT 1" (p/drvMysql) (list)))
        (pBus (r/planQuery "SELECT 1" (p/drvAgentbusIpc) (list)))
        (pCust (r/planCustom "SELECT 1" (p/tierMicrovm) (list)))]
    (assert (r/isWasmTier? (.-tier pWasm)) "p-wasm must be wasm tier")
    (assert (r/isHostTier? (.-tier pPg)) "p-pg must be host tier")
    (assert (r/isHostTier? (.-tier pMy)) "p-my must be host tier")
    (assert (r/isHostTier? (.-tier pBus)) "p-bus must be host tier")
    (assert (r/isMicrovmTier? (.-tier pCust)) "p-cust must be microvm tier")
    true))

(df runTests [] -> Bool
  :d "Runs all Polyglot Bridge test suites."
  (do
    (assert (testPortsAndTypes) "test-ports-and-types must pass")
    (assert (testSchemaKysely) "test-schema-kysely must pass")
    (assert (testSchemaDrizzle) "test-schema-drizzle must pass")
    (assert (testSchemaSqlalchemy) "test-schema-sqlalchemy must pass")
    (assert (testSchemaSeaorm) "test-schema-seaorm must pass")
    (assert (testRouterWorkload) "test-router-workload must pass")
    (assert (testRouterPlanning) "test-router-planning must pass")
    true))
