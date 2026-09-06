(module asl-sql/test
  :d "Unit tests for native ASL cross-dialect SQL query builder and DDL generator."
  :x [test-sql-select test-sql-dialects test-sql-ddl run-tests]
  :i [(core :a sql)
      (ddl :a ddl)])

(df test-sql-select [] -> Bool
  :d "Verifies SQL SELECT query generation and parameter rendering."
  (let [(c1 (sql/col-expr "id"))
        (c2 (sql/col-expr "name"))
        (sel (sql/make-select (list c1 c2) "users"))
        (rendered (sql/render-select sel (sql/sqlite)))]
    (and (> (string-length (.-sql rendered)) 0)
         (= (list-length (.-params rendered)) 0))))

(df test-sql-dialects [] -> Bool
  :d "Verifies dialect quoting and default dialects."
  (let [(q-pg (sql/dialect-quote-char (sql/postgres)))
        (q-my (sql/dialect-quote-char (sql/mysql)))
        (q-sq (sql/dialect-quote-char (sql/sqlite)))]
    (and (= q-pg "\"")
         (and (= q-my "`")
              (= q-sq "\"")))))

(df test-sql-ddl [] -> Bool
  :d "Verifies DDL CREATE TABLE and INSERT rendering."
  (let [(col-id (ddl/make-column "id" (ddl/col-int64) true false))
        (col-name (ddl/make-column "username" (ddl/col-text) false false))
        (tbl (ddl/make-table "accounts" (list col-id col-name)))
        (create-sql (ddl/render-create-table tbl (sql/sqlite)))
        (ins (ddl/make-insert "accounts" (list "id" "username") (list "1" "'eddie'")))
        (ins-sql (ddl/render-insert ins (sql/sqlite)))]
    (and (> (string-length create-sql) 0)
         (> (string-length ins-sql) 0))))

(df run-tests [] -> Bool
  :d "Executes all SQL test assertions."
  (and (test-sql-select)
       (and (test-sql-dialects)
            (test-sql-ddl))))
