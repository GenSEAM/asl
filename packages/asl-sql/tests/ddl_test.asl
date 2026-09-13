(module asl-sql/ddlTest
  :d "Unit tests for native ASL DDL table definition and schema rendering."
  :x [testDdlTableCreation
      testDdlColumnTypes
      testDdlPlaceholdersAndDialects
      runTests]
  :i [(core :a sql)
      (ddl :a ddl)])

(df testDdlTableCreation [] -> Bool
  (let [(colId (ddl/makeColumn "id" (ddl/colInt64) true false))
        (colEmail (ddl/makeColumn "email" (ddl/colText) false false))
        (tbl (ddl/makeTable "users" (list colId colEmail)))
        (sqlStr (ddl/renderCreateTable tbl (sql/sqlite)))]
    (do
      (assert (string-contains? sqlStr "CREATE TABLE") "Must create table")
      (assert (string-contains? sqlStr "users") "Must contain table name")
      (refute (string-contains? sqlStr "DROP TABLE") "Must not drop table")
      true)))

(df testDdlColumnTypes [] -> Bool
  (let [(colB (ddl/makeColumn "is_active" (ddl/colBool) false false))
        (colF (ddl/makeColumn "score" (ddl/colFloat64) false false))
        (tbl (ddl/makeTable "stats" (list colB colF)))
        (sqlPg (ddl/renderCreateTable tbl (sql/postgres)))
        (sqlSq (ddl/renderCreateTable tbl (sql/sqlite)))]
    (do
      (assert (string-contains? sqlPg "stats") "Must contain table stats")
      (assert (string-contains? sqlPg "DOUBLE PRECISION") "PostgreSQL must use DOUBLE PRECISION")
      (assert (string-contains? sqlPg "BOOLEAN") "PostgreSQL must use BOOLEAN")
      (assert (string-contains? sqlSq "REAL") "SQLite must use REAL")
      (assert (string-contains? sqlSq "INTEGER") "SQLite must use INTEGER")
      (assert (> (string-length sqlPg) 0) "SQL length must be positive")
      (refute (string-contains? sqlPg "error") "Must not contain error")
      (refute (string-contains? sqlSq "DOUBLE PRECISION") "SQLite must not contain DOUBLE PRECISION")
      true)))

(df testDdlPlaceholdersAndDialects [] -> Bool
  :d "Verifies dialect-specific placeholders, upsert clauses, and type mappings."
  (let [(colId (ddl/makeColumn "id" (ddl/colInt64) true false))
        (colScore (ddl/makeColumn "score" (ddl/colFloat64) false false))
        (colActive (ddl/makeColumn "active" (ddl/colBool) false false))
        (tbl (ddl/makeTable "metrics" (list colId colScore colActive)))
        (mySql (ddl/renderCreateTable tbl (sql/mysql)))
        (chSql (ddl/renderCreateTable tbl (sql/clickhouse)))
        (ins (ddl/makeInsert "metrics" (list "id" "score" "active") (list "1" "9.5" "1")))
        (sqIns (ddl/renderInsert ins (sql/sqlite)))
        (pgIns (ddl/renderInsert ins (sql/postgres)))
        (ups (ddl/makeUpsert "metrics" (list "id" "score") (list "1" "10.0") (list "id") (list "score")))
        (myUps (ddl/renderUpsert ups (sql/mysql)))
        (pgUps (ddl/renderUpsert ups (sql/postgres)))]
    (do
      (assert (string-contains? mySql "DOUBLE") "MySQL must use DOUBLE")
      (assert (string-contains? chSql "Float64") "ClickHouse must use Float64")
      (assert (string-contains? sqIns "(?, ?, ?)") "SQLite insert must use ? placeholders")
      (refute (string-contains? sqIns "$1") "SQLite insert must not use $1 placeholder")
      (assert (string-contains? pgIns "($1, $2, $3)") "PostgreSQL insert must use $1, $2, $3 placeholders")
      (refute (string-contains? pgIns "(?, ?, ?)") "PostgreSQL insert must not use ? placeholders")
      (assert (string-contains? myUps "ON DUPLICATE KEY UPDATE") "MySQL upsert must emit ON DUPLICATE KEY UPDATE")
      (refute (string-contains? myUps "ON CONFLICT") "MySQL upsert must not emit ON CONFLICT")
      (assert (string-contains? pgUps "ON CONFLICT") "PostgreSQL upsert must emit ON CONFLICT")
      (refute (string-contains? pgUps "ON DUPLICATE KEY UPDATE") "PostgreSQL upsert must not emit ON DUPLICATE KEY UPDATE")
      true)))

(df runTests [] -> Bool
  (do
    (assert (testDdlTableCreation))
    (assert (testDdlColumnTypes))
    (assert (testDdlPlaceholdersAndDialects))))
