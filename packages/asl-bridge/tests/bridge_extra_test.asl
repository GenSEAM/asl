(module asl-bridge/extraTest
  :d "Unit tests for remaining bridge and schema functions."
  :x [testExtra runTests]
  :i [(ports :a p) (schemaBridge :a sb) (router :a r)])

(df testExtra [] -> Bool
  :d "Verifies all helper functions and edge cases."
  (let [(d1 (p/strToDriverKind "sqlite-wasm"))
        (t1 (p/strToTierKind "wasm"))
        (dt (r/driverTier (p/drvSqliteWasm)))
        (pas (sb/toPascalCase "user_profile"))
        (cat (sb/colCategory "i64"))
        (kt (sb/kyselyType "i64"))
        (rk (sb/renderKyselyCol (p/makeDbColumn "id" "i64" false true)))
        (dfn (sb/drizzleTypeFn "i64"))
        (dcb (sb/drizzleColBuilder (p/makeDbColumn "id" "i64" false true)))
        (sqt (sb/sqlalchemyType "i64"))
        (rsq (sb/renderSqlalchemyCol (p/makeDbColumn "id" "i64" false true)))
        (set (sb/seaormType "i64"))
        (rse (sb/renderSeaormCol (p/makeDbColumn "id" "i64" false true)))]
    (assert (= pas "UserProfile") "PascalCase conversion must match")
    (assert (= cat "int") "Category must be int")
    (assert (= kt "number") "Kysely type must be number")
    (assert (= sqt "int") "SQLAlchemy type must be int")
    (assert (= set "i64") "SeaORM type must be i64")
    true))

(df runTests [] -> Bool
  :d "Executes extra test suite."
  (do
    (assert (testExtra) "test-extra must pass")
    true))
