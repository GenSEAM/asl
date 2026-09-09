(module asl-sql/ddl-test
  :d "Unit tests for native ASL DDL table definition and schema rendering."
  :x [test-ddl-table-creation
      test-ddl-column-types
      run-tests]
  :i [(core :a sql)
      (ddl :a ddl)])

(df test-ddl-table-creation [] -> Bool
  (let [(col-id (ddl/make-column "id" (ddl/col-int64) true false))
        (col-email (ddl/make-column "email" (ddl/col-text) false false))
        (tbl (ddl/make-table "users" (list col-id col-email)))
        (sql-str (ddl/render-create-table tbl (sql/sqlite)))]
    (do
      (assert (string-contains? sql-str "CREATE TABLE") "Must create table")
      (assert (string-contains? sql-str "users") "Must contain table name")
      (assert (not (string-contains? sql-str "DROP TABLE")) "Must not drop table")
      true)))

(df test-ddl-column-types [] -> Bool
  (let [(col-b (ddl/make-column "is_active" (ddl/col-bool) false false))
        (col-f (ddl/make-column "score" (ddl/col-float64) false false))
        (tbl (ddl/make-table "stats" (list col-b col-f)))
        (sql-pg (ddl/render-create-table tbl (sql/postgres)))]
    (do
      (assert (string-contains? sql-pg "stats") "Must contain table stats")
      (assert (> (string-length sql-pg) 0) "SQL length must be positive")
      (assert (not (string-contains? sql-pg "error")) "Must not contain error")
      true)))

(df run-tests [] -> Bool
  (do
    (assert (test-ddl-table-creation))
    (assert (test-ddl-column-types))))
