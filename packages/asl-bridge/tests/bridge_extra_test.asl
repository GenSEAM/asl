(module asl-bridge/extra-test
  :d "Unit tests for remaining bridge and schema functions."
  :x [test-extra run-tests]
  :i [(ports :a p) (schema-bridge :a sb) (router :a r)])

(df test-extra [] -> Bool
  :d "Verifies all helper functions and edge cases."
  (let [(d1 (p/str-to-driver-kind "sqlite-wasm"))
        (t1 (p/str-to-tier-kind "wasm"))
        (dt (r/driver-tier (p/drv-sqlite-wasm)))
        (pas (sb/to-pascal-case "user_profile"))
        (cat (sb/col-category "i64"))
        (kt (sb/kysely-type "i64"))
        (rk (sb/render-kysely-col (p/make-db-column "id" "i64" false true)))
        (dfn (sb/drizzle-type-fn "i64"))
        (dcb (sb/drizzle-col-builder (p/make-db-column "id" "i64" false true)))
        (sqt (sb/sqlalchemy-type "i64"))
        (rsq (sb/render-sqlalchemy-col (p/make-db-column "id" "i64" false true)))
        (set (sb/seaorm-type "i64"))
        (rse (sb/render-seaorm-col (p/make-db-column "id" "i64" false true)))]
    (assert (= pas "UserProfile") "PascalCase conversion must match")
    (assert (= cat "int") "Category must be int")
    (assert (= kt "number") "Kysely type must be number")
    (assert (= sqt "int") "SQLAlchemy type must be int")
    (assert (= set "i64") "SeaORM type must be i64")
    true))

(df run-tests [] -> Bool
  :d "Executes extra test suite."
  (do
    (assert (test-extra) "test-extra must pass")
    true))
