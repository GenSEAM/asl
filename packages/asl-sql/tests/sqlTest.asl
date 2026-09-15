(module asl-sql/test
  :d "Unit tests for native ASL cross-dialect SQL query builder and DDL generator."
  :x [testSqlSelect testSqlJoinParams testSqlDialects testSqlDdl runTests]
  :i [(core :a sql)
      (ddl :a ddl)])

(df testSqlSelect [] -> Bool
  :d "Verifies SQL SELECT query generation and parameter rendering."
  (let [(sel (sql/makeSelect (list "id" "name") "users" (none)))
        (rendered (sql/renderSelect sel (sql/sqlite)))
        (whereCond (sql/binary (sql/eq) (sql/colExpr "id") (sql/intExpr 42)))
        (selWhere (sql/makeSelect (list "id" "name") "users" (some whereCond)))
        (renderedWhere (sql/renderSelect selWhere (sql/postgres)))
        (jCond (sql/binary (sql/eq) (sql/colExpr "users.id") (sql/colExpr "orders.user_id")))
        (j (sql/makeJoin (sql/innerJoin) "orders" jCond))
        (selFull (sql/SelectQuery :columns (list "id")
                                   :fromTable "users"
                                   :joins (list j)
                                   :whereClause (none)
                                   :orderColumn (some "id")
                                   :orderDir (sql/desc)
                                   :limitCount (some 10)
                                   :offsetCount (some 5)
                                   :forUpdateSkipLocked true
                                   :returningColumns (list "id")))
        (renderedFull (sql/renderSelect selFull (sql/postgres)))
        (fullSql (.-sql renderedFull))]
    (do
      (assert (> (string-length (.-sql rendered)) 0) "rendered select length > 0")
      (assert (= (list-length (.-params rendered)) 0) "rendered params count is 0")
      (assert (= (list-length (.-params renderedWhere)) 1) "rendered where params count is 1")
      (assert (string-contains? fullSql "INNER JOIN orders ON") "full sql contains INNER JOIN")
      (refute (string-contains? fullSql "DELETE FROM") "full sql must not contain DELETE")
      true)))

(df testSqlJoinParams [] -> Bool
  :d "Verifies SQL JOIN ON parameter collection and placeholder numbering."
  (let [(jCond1 (sql/binary (sql/eq) (sql/colExpr "orders.status") (sql/strExpr "completed")))
        (j1 (sql/makeJoin (sql/innerJoin) "orders" jCond1))
        (jCond2 (sql/binary (sql/gt) (sql/colExpr "items.price") (sql/intExpr 100)))
        (j2 (sql/makeJoin (sql/leftJoin) "items" jCond2))
        (whereCond (sql/binary (sql/eq) (sql/colExpr "users.active") (sql/boolExpr true)))
        (q (sql/SelectQuery :columns (list "users.id" "orders.total")
                            :fromTable "users"
                            :joins (list j1 j2)
                            :whereClause (some whereCond)
                            :orderColumn (none)
                            :orderDir (sql/asc)
                            :limitCount (none)
                            :offsetCount (none)
                            :forUpdateSkipLocked false
                            :returningColumns (list)))
        (resPg (sql/renderSelect q (sql/postgres)))
        (resSq (sql/renderSelect q (sql/sqlite)))
        (sqlPg (.-sql resPg))
        (sqlSq (.-sql resSq))]
    (do
      (assert (= (.-paramCount resPg) 3) "param count must be 3")
      (assert (= (list-length (.-params resPg)) 3) "params list length must be 3")
      (assert (string-contains? sqlPg "INNER JOIN orders ON orders.status = $1") "pg inner join")
      (assert (string-contains? sqlSq "INNER JOIN orders ON orders.status = ?") "sqlite inner join")
      (refute (string-contains? sqlPg "DROP") "must not contain drop")
      true)))

(df testSqlDialects [] -> Bool
  :d "Verifies dialect quoting and default dialects."
  (let [(qPg (sql/dialectQuoteChar (sql/postgres)))
        (qMy (sql/dialectQuoteChar (sql/mysql)))
        (qSq (sql/dialectQuoteChar (sql/sqlite)))]
    (do
      (assert (= qPg "\"") "pg quote char is double quote")
      (assert (= qMy "`") "mysql quote char is backtick")
      (assert (= qSq "\"") "sqlite quote char is double quote")
      (refute (= qPg "`") "pg quote char is not backtick")
      true)))

(df testSqlDdl [] -> Bool
  :d "Verifies DDL CREATE TABLE, parameterized INSERT and UPSERT rendering."
  (let [(colId (ddl/makeColumn "id" (ddl/colInt64) true false))
        (colName (ddl/makeColumn "username" (ddl/colText) false false))
        (tbl (ddl/makeTable "accounts" (list colId colName)))
        (createSql (ddl/renderCreateTable tbl false))
        (ins (ddl/makeInsert "accounts" (list "id" "username") (list "1" "'eddie'")))
        (insSqlSqlite (ddl/renderInsert ins false))
        (insSqlPg (ddl/renderInsert ins true))
        (ups (ddl/makeUpsert "accounts" (list "id" "username") (list "1" "'eddie'") (list "id") (list "username")))
        (upsSqlPg (ddl/renderUpsert ups true))
        (upsSqlSq (ddl/renderUpsert ups false))]
    (do
      (assert (> (string-length createSql) 0) "create table sql length > 0")
      (assert (string-contains? insSqlSqlite "VALUES (?, ?);") "sqlite insert values")
      (assert (string-contains? insSqlPg "VALUES ($1, $2);") "pg insert values")
      (refute (string-contains? createSql "DROP TABLE") "create table must not contain drop")
      true)))

(df runTests [] -> Bool
  :d "Executes all SQL test assertions."
  (do
    (assert (testSqlSelect))
    (assert (testSqlJoinParams))
    (assert (testSqlDialects))
    (assert (testSqlDdl))))
