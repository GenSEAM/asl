(module asl-sql/test
  :d "Unit tests for native ASL cross-dialect SQL query builder and DDL generator."
  :x [test-sql-select test-sql-dialects test-sql-ddl run-tests]
  :i [(core :a sql)
      (ddl :a ddl)])

(df test-sql-select [] -> Bool
  :d "Verifies SQL SELECT query generation and parameter rendering."
  (let [(sel (sql/make-select (list "id" "name") "users" (none)))
        (rendered (sql/render-select sel (sql/sqlite)))
        (where-cond (sql/binary (sql/eq) (sql/col-expr "id") (sql/int-expr 42)))
        (sel-where (sql/make-select (list "id" "name") "users" (some where-cond)))
        (rendered-where (sql/render-select sel-where (sql/postgres)))
        (j-cond (sql/binary (sql/eq) (sql/col-expr "users.id") (sql/col-expr "orders.user_id")))
        (j (sql/make-join (sql/inner-join) "orders" j-cond))
        (sel-full (sql/SelectQuery :columns (list "id")
                                   :from-table "users"
                                   :joins (list j)
                                   :where-clause (none)
                                   :order-column (some "id")
                                   :order-dir (sql/desc)
                                   :limit-count (some 10)
                                   :offset-count (some 5)
                                   :for-update-skip-locked true
                                   :returning-columns (list "id")))
        (rendered-full (sql/render-select sel-full (sql/postgres)))
        (full-sql (.-sql rendered-full))]
    (and (> (string-length (.-sql rendered)) 0)
         (and (= (list-length (.-params rendered)) 0)
              (and (= (list-length (.-params rendered-where)) 1)
                   (and (= (.-param-count rendered-where) 1)
                        (and (string-contains? (.-sql rendered-where) "$1")
                             (and (string-contains? full-sql "INNER JOIN orders ON")
                                  (and (string-contains? full-sql "ORDER BY id DESC")
                                       (and (string-contains? full-sql "LIMIT 10")
                                            (and (string-contains? full-sql "OFFSET 5")
                                                 (and (string-contains? full-sql "FOR UPDATE SKIP LOCKED")
                                                      (string-contains? full-sql "RETURNING id")))))))))))))

(df test-sql-dialects [] -> Bool
  :d "Verifies dialect quoting and default dialects."
  (let [(q-pg (sql/dialect-quote-char (sql/postgres)))
        (q-my (sql/dialect-quote-char (sql/mysql)))
        (q-sq (sql/dialect-quote-char (sql/sqlite)))]
    (and (= q-pg "\"")
         (and (= q-my "`")
              (= q-sq "\"")))))

(df test-sql-ddl [] -> Bool
  :d "Verifies DDL CREATE TABLE, parameterized INSERT and UPSERT rendering."
  (let [(col-id (ddl/make-column "id" (ddl/col-int64) true false))
        (col-name (ddl/make-column "username" (ddl/col-text) false false))
        (tbl (ddl/make-table "accounts" (list col-id col-name)))
        (create-sql (ddl/render-create-table tbl false))
        (ins (ddl/make-insert "accounts" (list "id" "username") (list "1" "'eddie'")))
        (ins-sql-sqlite (ddl/render-insert ins false))
        (ins-sql-pg (ddl/render-insert ins true))
        (ups (ddl/make-upsert "accounts" (list "id" "username") (list "1" "'eddie'") (list "id") (list "username")))
        (ups-sql-pg (ddl/render-upsert ups true))
        (ups-sql-sq (ddl/render-upsert ups false))]
    (and (> (string-length create-sql) 0)
         (and (string-contains? ins-sql-sqlite "VALUES (?, ?);")
              (and (string-contains? ins-sql-pg "VALUES ($1, $2);")
                   (and (string-contains? ups-sql-pg "VALUES ($1, $2)")
                        (and (string-contains? ups-sql-pg "EXCLUDED.username")
                             (string-contains? ups-sql-sq "VALUES (?, ?)"))))))))

(df run-tests [] -> Bool
  :d "Executes all SQL test assertions."
  (do
    (assert (test-sql-select))
    (assert (test-sql-dialects))
    (assert (test-sql-ddl))))
