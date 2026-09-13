(module asl-sql/ddl
  :d "Native AgentScript SQL DDL (Schema & Migrations) and DML (Insert, Update, Delete, Upsert) Generator."
  :x [SqlColumnType ColumnDef TableDef InsertQuery UpdateQuery UpsertQuery
           typeToSqlString renderColumnDef renderCreateTable
           renderInsert renderUpdate renderDelete renderUpsert
           makeColumn makeColumnCustom makeTable makeInsert makeUpdate makeUpsert
           colInt64 colFloat64 colText colBoolean colBool colTimestamp]
  :i [(sql :a sql)])

(dfe SqlColumnType
  (:c colInt64     [] "64-bit integer (BIGINT)")
  (:c colFloat64   [] "64-bit floating point (DOUBLE PRECISION or REAL)")
  (:c colText      [] "Variable length character string (TEXT)")
  (:c colBoolean   [] "Boolean flag (BOOLEAN or INTEGER)")
  (:c colTimestamp [] "Timestamp with timezone (TIMESTAMPTZ or TEXT)"))

(df colBool [] -> SqlColumnType
  :d "Alias for col-boolean column type."
  (colBoolean))

(dfs ColumnDef
  (:f name String "Column identifier name")
  (:f colType SqlColumnType "Data type of the column")
  (:f isPrimary Bool "True if column is PRIMARY KEY")
  (:f isNullable Bool "True if column allows NULL values")
  (:f extraSql String "Custom vendor-specific SQL clauses (e.g. REFERENCES, COLLATE, DEFAULT)"))

(dfs TableDef
  (:f tableName String "Target database table name")
  (:f columns (List ColumnDef) "List of column definitions"))

(dfs InsertQuery
  (:f tableName String "Target table to insert into")
  (:f columns (List String) "Column identifiers")
  (:f values (List String) "Parameter placeholder strings"))

(dfs UpdateQuery
  (:f tableName String "Target table to update")
  (:f setAssignments (List String) "Column assignments (col = val)")
  (:f whereClause String "Update predicate condition"))

(dfs UpsertQuery
  (:f tableName String "Target table to upsert into")
  (:f columns (List String) "Column identifiers")
  (:f values (List String) "Parameter placeholder strings")
  (:f conflictCols (List String) "Conflict target columns for ON CONFLICT")
  (:f updateCols (List String) "Columns to update on conflict"))

(df makeColumn [(colName String) (t SqlColumnType) (pk Bool) (nullable Bool)] -> ColumnDef
  :d "Constructs a standard ColumnDef record."
  (ColumnDef :name colName :colType t :isPrimary pk :isNullable nullable :extraSql ""))

(df makeColumnCustom [(colName String) (t SqlColumnType) (pk Bool) (nullable Bool) (extra String)] -> ColumnDef
  :d "Constructs a ColumnDef record with custom vendor extra SQL clause."
  (ColumnDef :name colName :colType t :isPrimary pk :isNullable nullable :extraSql extra))

(df makeTable [(name String) (cols (List ColumnDef))] -> TableDef
  :d "Constructs a TableDef record."
  (TableDef :tableName name :columns cols))

(df makeInsert [(tbl String) (cols (List String)) (vals (List String))] -> InsertQuery
  :d "Constructs an InsertQuery record."
  (InsertQuery :tableName tbl :columns cols :values vals))

(df makeUpdate [(tbl String) (assigns (List String)) (whereSql String)] -> UpdateQuery
  :d "Constructs an UpdateQuery record."
  (UpdateQuery :tableName tbl :setAssignments assigns :whereClause whereSql))

(df makeUpsert [(tbl String) (cols (List String)) (vals (List String)) (conflicts (List String)) (updates (List String))] -> UpsertQuery
  :d "Constructs an UpsertQuery record."
  (UpsertQuery :tableName tbl :columns cols :values vals :conflictCols conflicts :updateCols updates))

(df normalizeDialect [(dialect sql/SqlDialect)] -> sql/SqlDialect
  :d "Normalizes dialect variant or legacy boolean flag to canonical SqlDialect."
  (if (= dialect true)
    (sql/postgres)
    (if (= dialect false)
      (sql/sqlite)
      dialect)))

(df typeToSqlString [(t SqlColumnType) (dialect sql/SqlDialect)] -> String
  :d "Maps abstract column type to target dialect data type keyword."
  (let [(d (normalizeDialect dialect))]
    (mt t
      ((colInt64)
        (mt d
          ((clickhouse) "Int64")
          (_ "BIGINT")))
      ((colFloat64)
        (mt d
          ((postgres) "DOUBLE PRECISION")
          ((mysql) "DOUBLE")
          ((clickhouse) "Float64")
          (_ "REAL")))
      ((colText)
        (mt d
          ((clickhouse) "String")
          (_ "TEXT")))
      ((colBoolean)
        (mt d
          ((postgres) "BOOLEAN")
          ((mysql) "BOOLEAN")
          ((clickhouse) "Bool")
          (_ "INTEGER")))
      ((colTimestamp)
        (mt d
          ((postgres) "TIMESTAMPTZ")
          ((mysql) "DATETIME")
          ((clickhouse) "DateTime64")
          (_ "TEXT"))))))

(df renderColumnDef [(col ColumnDef) (dialect sql/SqlDialect)] -> String
  :d "Renders a single column definition line for CREATE TABLE."
  (let [(d (normalizeDialect dialect))
        (tStr (typeToSqlString (.-colType col) d))
        (base (str (.-name col) " " tStr))
        (withPk (if (.-isPrimary col) (str base " PRIMARY KEY") base))
        (withNull (if (.-isNullable col) withPk (str withPk " NOT NULL")))]
    (if (> (string-length (.-extraSql col)) 0)
      (str withNull " " (.-extraSql col))
      withNull)))

(df formatAssignments [(cols (List String)) (prefix String) (suffix String)] -> String
  :d "Helper to format assignment pairs."
  (string-join (map (fn [c] (str c " = " prefix c suffix)) cols) ", "))

(df renderPlaceholderItem [(idx Int64) (dialect sql/SqlDialect)] -> String
  :d "Renders a single parameter placeholder."
  (let [(d (normalizeDialect dialect))]
    (mt d
      ((postgres) (str "$" (string-from-int64 idx)))
      (_ "?"))))

(df renderPlaceholders [(count Int64) (dialect sql/SqlDialect)] -> (List String)
  :d "Generates list of parameter placeholders for query binding."
  (if (<= count 0)
    (list)
    (let [(d (normalizeDialect dialect))]
      (map (fn [idx] (renderPlaceholderItem idx d)) (range 1 (+ count 1))))))

(df countColumns [(cols (List String)) (vals (List String))] -> Int64
  :d "Determines placeholder count from columns or values list."
  (let [(cLen (list-length cols))]
    (if (> cLen 0)
      cLen
      (list-length vals))))

(df renderUpsert [(q UpsertQuery) (dialect sql/SqlDialect)] -> String
  :d "Renders cross-dialect UPSERT query (Postgres/SQLite ON CONFLICT vs MySQL ON DUPLICATE KEY)."
  (let [(d (normalizeDialect dialect))
        (cLen (countColumns (.-columns q) (.-values q)))
        (phList (renderPlaceholders cLen d))
        (base (str "INSERT INTO " (.-tableName q) " (" (string-join (.-columns q) ", ") ") VALUES (" (string-join phList ", ") ") "))]
    (mt d
      ((mysql)
        (let [(upd (formatAssignments (.-updateCols q) "VALUES(" ")"))]
          (str base "ON DUPLICATE KEY UPDATE " upd ";")))
      (_
        (let [(upd (formatAssignments (.-updateCols q) "EXCLUDED." ""))]
          (str base "ON CONFLICT (" (string-join (.-conflictCols q) ", ") ") DO UPDATE SET " upd ";"))))))

(df renderCreateTable [(tbl TableDef) (dialect sql/SqlDialect)] -> String
  :d "Renders a complete SQL CREATE TABLE DDL statement."
  (let [(d (normalizeDialect dialect))
        (renderedCols (map (fn [c] (renderColumnDef c d)) (.-columns tbl)))
        (colsBody (string-join renderedCols ", "))]
    (str "CREATE TABLE " (.-tableName tbl) " (" colsBody ");")))

(df renderInsert [(q InsertQuery) (dialect sql/SqlDialect)] -> String
  :d "Renders a parameterized SQL INSERT statement."
  (let [(d (normalizeDialect dialect))
        (cols (string-join (.-columns q) ", "))
        (cLen (countColumns (.-columns q) (.-values q)))
        (phList (renderPlaceholders cLen d))
        (vals (string-join phList ", "))]
    (str "INSERT INTO " (.-tableName q) " (" cols ") VALUES (" vals ");")))

(df renderUpdate [(q UpdateQuery)] -> String
  :d "Renders a parameterized SQL UPDATE statement."
  (str "UPDATE " (.-tableName q) " SET " (string-join (.-setAssignments q) ", ") " WHERE " (.-whereClause q) ";"))

(df whereClauseSuffix [(w String)] -> String
  :d "Helper to format WHERE clause suffix."
  (str " WHERE " w ";"))

(df renderDelete [(tbl String) (whereClause String)] -> String
  :d "Renders a parameterized SQL DELETE statement."
  (str "DELETE FROM " tbl (whereClauseSuffix whereClause)))
