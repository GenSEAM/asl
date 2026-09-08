(module asl-bridge/test
  :d "Comprehensive unit tests for the Polyglot Bridge, schema transpiler, and workload execution router."
  :x [run-tests
      sample-table
      test-ports-and-types
      test-schema-kysely
      test-schema-drizzle
      test-schema-sqlalchemy
      test-schema-seaorm
      test-router-workload
      test-router-planning]
  :i [(ports :a p) (schema-bridge :a sb) (router :a r)])

(df sample-table [] -> p/TableDef
  :d "Constructs a sample TableDef record with diverse column types."
  (let [(c1 (p/make-db-column "id" "i64" false true))
        (c2 (p/make-db-column "name" "text" false false))
        (c3 (p/make-db-column "email" "text" true false))
        (c4 (p/make-db-column "is_active" "bool" false false))
        (c5 (p/make-db-column "score" "f64" true false))
        (cols (cons c1 (cons c2 (cons c3 (cons c4 (cons c5 (list)))))))]
    (p/make-table-def "users" cols)))

(df test-ports-and-types [] -> Bool
  :d "Verifies DbColumn, TableDef, QueryPlan, DbResult, and enum conversions."
  (let [(tbl (sample-table))
        (p-wasm (p/drv-sqlite-wasm))
        (p-pg (p/drv-pg-socket))
        (t-w (p/tier-wasm-sandbox))
        (t-h (p/tier-host-ipc))
        (t-m (p/tier-microvm))
        (qp (p/make-query-plan "SELECT * FROM users" t-w (cons "1" (list))))
        (row1 (map-set (map-empty) "id" "1"))
        (rows (cons row1 (list)))
        (res (p/make-db-result rows 1))]
    (assert (= (.-name tbl) "users") "Table name must be users")
    (assert (= (list-length (.-columns tbl)) 5) "Columns count must be 5")
    (assert (= (p/driver-kind-to-str p-wasm) "drv-sqlite-wasm") "Driver kind wasm must match")
    (assert (= (p/driver-kind-to-str p-pg) "drv-pg-socket") "Driver kind pg must match")
    (assert (= (p/tier-kind-to-str t-w) "tier-wasm-sandbox") "Tier wasm must match")
    (assert (= (p/tier-kind-to-str t-h) "tier-host-ipc") "Tier host must match")
    (assert (= (p/tier-kind-to-str t-m) "tier-microvm") "Tier microvm must match")
    (assert (= (.-sql qp) "SELECT * FROM users") "SQL must match")
    (assert (= (.-affected res) 1) "Affected rows must be 1")
    (assert (= (list-length (.-rows res)) 1) "Result rows count must be 1")
    true))

(df test-schema-kysely [] -> Bool
  :d "Verifies TypeScript Kysely interface transpilation."
  (let [(tbl (sample-table))
        (out (sb/table-to-kysely tbl))]
    (assert (string-contains? out "export interface UsersTable {") "Kysely interface must exist")
    (assert (string-contains? out "  id: number;") "id column must be number")
    (assert (string-contains? out "  name: string;") "name column must be string")
    (assert (string-contains? out "  email: string | null;") "email column must be nullable string")
    (assert (string-contains? out "  is_active: boolean;") "is_active column must be boolean")
    (assert (string-contains? out "  score: number | null;") "score column must be nullable number")
    true))

(df test-schema-drizzle [] -> Bool
  :d "Verifies TypeScript Drizzle table definition transpilation."
  (let [(tbl (sample-table))
        (out (sb/table-to-drizzle tbl))]
    (assert (string-contains? out "export const users = pgTable(\"users\", {") "pgTable must exist")
    (assert (string-contains? out "  id: integer(\"id\").primaryKey(),") "id primary key must exist")
    (assert (string-contains? out "  name: text(\"name\").notNull(),") "name notNull must exist")
    (assert (string-contains? out "  email: text(\"email\"),") "email text must exist")
    (assert (string-contains? out "  is_active: boolean(\"is_active\").notNull(),") "is_active notNull must exist")
    (assert (string-contains? out "  score: real(\"score\"),") "score real must exist")
    true))

(df test-schema-sqlalchemy [] -> Bool
  :d "Verifies Python SQLAlchemy 2.0 DeclarativeBase model transpilation."
  (let [(tbl (sample-table))
        (out (sb/table-to-sqlalchemy tbl))]
    (assert (string-contains? out "class Users(Base):") "Base class must exist")
    (assert (string-contains? out "__tablename__ = \"users\"") "tablename must exist")
    (assert (string-contains? out "id: Mapped[int] = mapped_column(primary_key=True)") "id mapped_column must exist")
    (assert (string-contains? out "name: Mapped[str] = mapped_column(nullable=False)") "name mapped_column must exist")
    (assert (string-contains? out "email: Mapped[Optional[str]] = mapped_column(nullable=True)") "email mapped_column must exist")
    (assert (string-contains? out "is_active: Mapped[bool] = mapped_column(nullable=False)") "is_active mapped_column must exist")
    (assert (string-contains? out "score: Mapped[Optional[float]] = mapped_column(nullable=True)") "score mapped_column must exist")
    true))

(df test-schema-seaorm [] -> Bool
  :d "Verifies Rust SeaORM entity struct transpilation."
  (let [(tbl (sample-table))
        (out (sb/table-to-seaorm tbl))]
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

(df test-router-workload [] -> Bool
  :d "Verifies workload router tiers based on capabilities and ops."
  (let [(t1 (r/route-workload "compute" false false))
        (t2 (r/route-workload "query" true false))
        (t3 (r/route-workload "train-model" false true))
        (t4 (r/route-workload "gpu-compute" false false))
        (t5 (r/route-workload "host-ipc" false false))]
    (assert (r/is-wasm-tier? t1) "t1 must be wasm tier")
    (assert (r/is-host-tier? t2) "t2 must be host tier")
    (assert (r/is-microvm-tier? t3) "t3 must be microvm tier")
    (assert (r/is-microvm-tier? t4) "t4 must be microvm tier")
    (assert (r/is-host-tier? t5) "t5 must be host tier")
    true))

(df test-router-planning [] -> Bool
  :d "Verifies query planning defaults per driver kind."
  (let [(p-wasm (r/plan-query "SELECT 1" (p/drv-sqlite-wasm) (list)))
        (p-pg (r/plan-query "SELECT 1" (p/drv-pg-socket) (list)))
        (p-my (r/plan-query "SELECT 1" (p/drv-mysql) (list)))
        (p-bus (r/plan-query "SELECT 1" (p/drv-agentbus-ipc) (list)))
        (p-cust (r/plan-custom "SELECT 1" (p/tier-microvm) (list)))]
    (assert (r/is-wasm-tier? (.-tier p-wasm)) "p-wasm must be wasm tier")
    (assert (r/is-host-tier? (.-tier p-pg)) "p-pg must be host tier")
    (assert (r/is-host-tier? (.-tier p-my)) "p-my must be host tier")
    (assert (r/is-host-tier? (.-tier p-bus)) "p-bus must be host tier")
    (assert (r/is-microvm-tier? (.-tier p-cust)) "p-cust must be microvm tier")
    true))

(df run-tests [] -> Bool
  :d "Runs all Polyglot Bridge test suites."
  (do
    (assert (test-ports-and-types) "test-ports-and-types must pass")
    (assert (test-schema-kysely) "test-schema-kysely must pass")
    (assert (test-schema-drizzle) "test-schema-drizzle must pass")
    (assert (test-schema-sqlalchemy) "test-schema-sqlalchemy must pass")
    (assert (test-schema-seaorm) "test-schema-seaorm must pass")
    (assert (test-router-workload) "test-router-workload must pass")
    (assert (test-router-planning) "test-router-planning must pass")
    true))
