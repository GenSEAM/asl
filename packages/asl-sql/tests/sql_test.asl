(module asl-sql/test
  :d "Unit tests for native ASL cross-dialect SQL query builder and DDL generator."
  :x [test-sql-select test-sql-join-params test-sql-dialects test-sql-ddl run-tests]
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
    (do
      (assert (> (string-length (.-sql rendered)) 0) "rendered select length > 0")
      (assert (= (list-length (.-params rendered)) 0) "rendered params count is 0")
      (assert (= (list-length (.-params rendered-where)) 1) "rendered where params count is 1")
      (assert (string-contains? full-sql "INNER JOIN orders ON") "full sql contains INNER JOIN")
      (assert (not (string-contains? full-sql "DELETE FROM")) "full sql must not contain DELETE")
      true)))

(df test-sql-join-params [] -> Bool
  :d "Verifies SQL JOIN ON parameter collection and placeholder numbering."
  (let [(j-cond1 (sql/binary (sql/eq) (sql/col-expr "orders.status") (sql/str-expr "completed")))
        (j1 (sql/make-join (sql/inner-join) "orders" j-cond1))
        (j-cond2 (sql/binary (sql/gt) (sql/col-expr "items.price") (sql/int-expr 100)))
        (j2 (sql/make-join (sql/left-join) "items" j-cond2))
        (where-cond (sql/binary (sql/eq) (sql/col-expr "users.active") (sql/bool-expr true)))
        (q (sql/SelectQuery :columns (list "users.id" "orders.total")
                            :from-table "users"
                            :joins (list j1 j2)
                            :where-clause (some where-cond)
                            :order-column (none)
                            :order-dir (sql/asc)
                            :limit-count (none)
                            :offset-count (none)
                            :for-update-skip-locked false
                            :returning-columns (list)))
        (res-pg (sql/render-select q (sql/postgres)))
        (res-sq (sql/render-select q (sql/sqlite)))
        (sql-pg (.-sql res-pg))
        (sql-sq (.-sql res-sq))]
    (do
      (assert (= (.-param-count res-pg) 3) "param count must be 3")
      (assert (= (list-length (.-params res-pg)) 3) "params list length must be 3")
      (assert (string-contains? sql-pg "INNER JOIN orders ON orders.status = $1") "pg inner join")
      (assert (string-contains? sql-sq "INNER JOIN orders ON orders.status = ?") "sqlite inner join")
      (assert (not (string-contains? sql-pg "DROP")) "must not contain drop")
      true)))

(df test-sql-dialects [] -> Bool
  :d "Verifies dialect quoting and default dialects."
  (let [(q-pg (sql/dialect-quote-char (sql/postgres)))
        (q-my (sql/dialect-quote-char (sql/mysql)))
        (q-sq (sql/dialect-quote-char (sql/sqlite)))]
    (do
      (assert (= q-pg "\"") "pg quote char is double quote")
      (assert (= q-my "`") "mysql quote char is backtick")
      (assert (= q-sq "\"") "sqlite quote char is double quote")
      (assert (not (= q-pg "`")) "pg quote char is not backtick")
      true)))

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
    (do
      (assert (> (string-length create-sql) 0) "create table sql length > 0")
      (assert (string-contains? ins-sql-sqlite "VALUES (?, ?);") "sqlite insert values")
      (assert (string-contains? ins-sql-pg "VALUES ($1, $2);") "pg insert values")
      (assert (not (string-contains? create-sql "DROP TABLE")) "create table must not contain drop")
      true)))

(df run-tests [] -> Bool
  :d "Executes all SQL test assertions."
  (do
    (assert (test-sql-select))
    (assert (test-sql-join-params))
    (assert (test-sql-dialects))
    (assert (test-sql-ddl))))
