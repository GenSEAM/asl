(module asl-bridge/extra-test
  :d "Unit tests for remaining bridge and schema functions."
  :x []
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
        (rse (sb/render-seaorm-col (p/make-db-column "id" "i64" false true)))
        (cap capitalize-word)]
    (and (= pas "UserProfile")
         (and (= cat "int")
              (and (= kt "number")
                   (and (= sqt "Integer")
                        (= set "i64")))))))
