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

"run: (run-tests)"

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
    (and (= (.-name tbl) "users")
         (and (= (list-length (.-columns tbl)) 5)
              (and (= (p/driver-kind-to-str p-wasm) "drv-sqlite-wasm")
                   (and (= (p/driver-kind-to-str p-pg) "drv-pg-socket")
                        (and (= (p/tier-kind-to-str t-w) "tier-wasm-sandbox")
                             (and (= (p/tier-kind-to-str t-h) "tier-host-ipc")
                                  (and (= (p/tier-kind-to-str t-m) "tier-microvm")
                                       (and (= (.-sql qp) "SELECT * FROM users")
                                            (and (= (.-affected res) 1)
                                                 (= (list-length (.-rows res)) 1))))))))))))

(df test-schema-kysely [] -> Bool
  :d "Verifies TypeScript Kysely interface transpilation."
  (let [(tbl (sample-table))
        (out (sb/table-to-kysely tbl))]
    (and (string-contains? out "export interface UsersTable {")
         (and (string-contains? out "  id: number;")
              (and (string-contains? out "  name: string;")
                   (and (string-contains? out "  email: string | null;")
                        (and (string-contains? out "  is_active: boolean;")
                             (string-contains? out "  score: number | null;"))))))))

(df test-schema-drizzle [] -> Bool
  :d "Verifies TypeScript Drizzle table definition transpilation."
  (let [(tbl (sample-table))
        (out (sb/table-to-drizzle tbl))]
    (and (string-contains? out "export const users = pgTable(\"users\", {")
         (and (string-contains? out "  id: integer(\"id\").primaryKey(),")
              (and (string-contains? out "  name: text(\"name\").notNull(),")
                   (and (string-contains? out "  email: text(\"email\"),")
                        (and (string-contains? out "  is_active: boolean(\"is_active\").notNull(),")
                             (string-contains? out "  score: real(\"score\"),"))))))))

(df test-schema-sqlalchemy [] -> Bool
  :d "Verifies Python SQLAlchemy 2.0 DeclarativeBase model transpilation."
  (let [(tbl (sample-table))
        (out (sb/table-to-sqlalchemy tbl))]
    (and (string-contains? out "class Users(Base):")
         (and (string-contains? out "__tablename__ = \"users\"")
              (and (string-contains? out "id: Mapped[int] = mapped_column(primary_key=True)")
                   (and (string-contains? out "name: Mapped[str] = mapped_column(nullable=False)")
                        (and (string-contains? out "email: Mapped[Optional[str]] = mapped_column(nullable=True)")
                             (and (string-contains? out "is_active: Mapped[bool] = mapped_column(nullable=False)")
                                  (string-contains? out "score: Mapped[Optional[float]] = mapped_column(nullable=True)")))))))))

(df test-schema-seaorm [] -> Bool
  :d "Verifies Rust SeaORM entity struct transpilation."
  (let [(tbl (sample-table))
        (out (sb/table-to-seaorm tbl))]
    (and (string-contains? out "#[derive(Clone, Debug, PartialEq, DeriveEntityModel)]")
         (and (string-contains? out "#[sea_orm(table_name = \"users\")]")
              (and (string-contains? out "pub struct Model {")
                   (and (string-contains? out "#[sea_orm(primary_key)]")
                        (and (string-contains? out "pub id: i64,")
                             (and (string-contains? out "pub name: String,")
                                  (and (string-contains? out "pub email: Option<String>,")
                                       (and (string-contains? out "pub is_active: bool,")
                                            (string-contains? out "pub score: Option<f64>,")))))))))))

(df test-router-workload [] -> Bool
  :d "Verifies workload router tiers based on capabilities and ops."
  (let [(t1 (r/route-workload "compute" false false))
        (t2 (r/route-workload "query" true false))
        (t3 (r/route-workload "train-model" false true))
        (t4 (r/route-workload "gpu-compute" false false))
        (t5 (r/route-workload "host-ipc" false false))]
    (and (r/is-wasm-tier? t1)
         (and (r/is-host-tier? t2)
              (and (r/is-microvm-tier? t3)
                   (and (r/is-microvm-tier? t4)
                        (r/is-host-tier? t5)))))))

(df test-router-planning [] -> Bool
  :d "Verifies query planning defaults per driver kind."
  (let [(p-wasm (r/plan-query "SELECT 1" (p/drv-sqlite-wasm) (list)))
        (p-pg (r/plan-query "SELECT 1" (p/drv-pg-socket) (list)))
        (p-my (r/plan-query "SELECT 1" (p/drv-mysql) (list)))
        (p-bus (r/plan-query "SELECT 1" (p/drv-agentbus-ipc) (list)))
        (p-cust (r/plan-custom "SELECT 1" (p/tier-microvm) (list)))]
    (and (r/is-wasm-tier? (.-tier p-wasm))
         (and (r/is-host-tier? (.-tier p-pg))
              (and (r/is-host-tier? (.-tier p-my))
                   (and (r/is-host-tier? (.-tier p-bus))
                        (r/is-microvm-tier? (.-tier p-cust))))))))

(df run-tests [] -> Bool
  :d "Runs all Polyglot Bridge test suites."
  (let [(results (list (test-ports-and-types)
                       (test-schema-kysely)
                       (test-schema-drizzle)
                       (test-schema-sqlalchemy)
                       (test-schema-seaorm)
                       (test-router-workload)
                       (test-router-planning)))]
    (not (list-contains? results false))))
