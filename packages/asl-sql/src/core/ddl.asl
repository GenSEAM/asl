(module asl-sql/ddl
  :d "Native AgentScript SQL DDL (Schema & Migrations) and DML (Insert, Update, Delete, Upsert) Generator."
  :x [SqlColumnType ColumnDef TableDef InsertQuery UpdateQuery UpsertQuery
           type-to-sql-string render-column-def render-create-table
           render-insert render-update render-delete render-upsert
           make-column make-column-custom make-table make-insert make-update make-upsert])

(dfe SqlColumnType
  (:c col-int64     [] "64-bit integer (BIGINT)")
  (:c col-float64   [] "64-bit floating point (DOUBLE PRECISION or REAL)")
  (:c col-text      [] "Variable length character string (TEXT)")
  (:c col-boolean   [] "Boolean flag (BOOLEAN or INTEGER)")
  (:c col-timestamp [] "Timestamp with timezone (TIMESTAMPTZ or TEXT)"))

(dfs ColumnDef
  (:f name String "Column identifier name")
  (:f col-type SqlColumnType "Data type of the column")
  (:f is-primary Bool "True if column is PRIMARY KEY")
  (:f is-nullable Bool "True if column allows NULL values")
  (:f extra-sql String "Custom vendor-specific SQL clauses (e.g. REFERENCES, COLLATE, DEFAULT)"))

(dfs TableDef
  (:f table-name String "Target database table name")
  (:f columns (List ColumnDef) "List of column definitions"))

(dfs InsertQuery
  (:f table-name String "Target table to insert into")
  (:f columns (List String) "Column identifiers")
  (:f values (List String) "Parameter placeholder strings"))

(dfs UpdateQuery
  (:f table-name String "Target table to update")
  (:f set-assignments (List String) "Column assignments (col = val)")
  (:f where-clause String "Update predicate condition"))

(dfs UpsertQuery
  (:f table-name String "Target table to upsert into")
  (:f columns (List String) "Column identifiers")
  (:f values (List String) "Parameter placeholder strings")
  (:f conflict-cols (List String) "Conflict target columns for ON CONFLICT")
  (:f update-cols (List String) "Columns to update on conflict"))

(df make-column [(col-name String) (t SqlColumnType) (pk Bool) (nullable Bool)] -> ColumnDef
  :d "Constructs a standard ColumnDef record."
  (ColumnDef :name col-name :col-type t :is-primary pk :is-nullable nullable :extra-sql ""))

(df make-column-custom [(col-name String) (t SqlColumnType) (pk Bool) (nullable Bool) (extra String)] -> ColumnDef
  :d "Constructs a ColumnDef record with custom vendor extra SQL clause."
  (ColumnDef :name col-name :col-type t :is-primary pk :is-nullable nullable :extra-sql extra))

(df make-table [(name String) (cols (List ColumnDef))] -> TableDef
  :d "Constructs a TableDef record."
  (TableDef :table-name name :columns cols))

(df make-insert [(tbl String) (cols (List String)) (vals (List String))] -> InsertQuery
  :d "Constructs an InsertQuery record."
  (InsertQuery :table-name tbl :columns cols :values vals))

(df make-update [(tbl String) (assigns (List String)) (where-sql String)] -> UpdateQuery
  :d "Constructs an UpdateQuery record."
  (UpdateQuery :table-name tbl :set-assignments assigns :where-clause where-sql))

(df make-upsert [(tbl String) (cols (List String)) (vals (List String)) (conflicts (List String)) (updates (List String))] -> UpsertQuery
  :d "Constructs an UpsertQuery record."
  (UpsertQuery :table-name tbl :columns cols :values vals :conflict-cols conflicts :update-cols updates))

(df pg-or-alt [(is-pg Bool) (pg-type String) (alt-type String)] -> String
  :d "Returns pg-type when is-pg is true, otherwise alt-type."
  (if is-pg pg-type alt-type))

(df type-to-sql-string [(t SqlColumnType) (is-pg Bool)] -> String
  :d "Maps abstract column type to target dialect data type keyword."
  (mt t
    ((col-int64)     "BIGINT")
    ((col-float64)   (pg-or-alt is-pg "DOUBLE PRECISION" "REAL"))
    ((col-text)      "TEXT")
    ((col-boolean)   (pg-or-alt is-pg "BOOLEAN" "INTEGER"))
    ((col-timestamp) (pg-or-alt is-pg "TIMESTAMPTZ" "TEXT"))))

(df render-column-def [(col ColumnDef) (is-pg Bool)] -> String
  :d "Renders a single column definition line for CREATE TABLE."
  (let [(t-str (type-to-sql-string (.-col-type col) is-pg))
        (base (str (.-name col) " " t-str))
        (with-pk (if (.-is-primary col) (str base " PRIMARY KEY") base))
        (with-null (if (.-is-nullable col) with-pk (str with-pk " NOT NULL")))]
    (if (> (string-length (.-extra-sql col)) 0)
      (str with-null " " (.-extra-sql col))
      with-null)))

(df format-assignments [(cols (List String)) (prefix String) (suffix String)] -> String
  :d "Helper to format assignment pairs."
  (string-join (map (fn [c] (str c " = " prefix c suffix)) cols) ", "))

(df render-upsert [(q UpsertQuery) (is-pg Bool)] -> String
  :d "Renders cross-dialect UPSERT query (Postgres/SQLite ON CONFLICT vs MySQL ON DUPLICATE KEY)."
  (let [(base (str "INSERT INTO " (.-table-name q) " (" (string-join (.-columns q) ", ") ") VALUES (" (string-join (.-values q) ", ") ") "))]
    (if is-pg
      (let [(upd (format-assignments (.-update-cols q) "EXCLUDED." ""))]
        (str base "ON CONFLICT (" (string-join (.-conflict-cols q) ", ") ") DO UPDATE SET " upd ";"))
      (let [(upd (format-assignments (.-update-cols q) "VALUES(" ")"))]
        (str base "ON DUPLICATE KEY UPDATE " upd ";")))))

(df render-create-table [(tbl TableDef) (is-pg Bool)] -> String
  :d "Renders a complete SQL CREATE TABLE DDL statement."
  (let [(rendered-cols (map (fn [c] (render-column-def c is-pg)) (.-columns tbl)))
        (cols-body (string-join rendered-cols ", "))]
    (str "CREATE TABLE " (.-table-name tbl) " (" cols-body ");")))

(df render-insert [(q InsertQuery)] -> String
  :d "Renders a parameterized SQL INSERT statement."
  (let [(cols (string-join (.-columns q) ", "))
        (vals (string-join (.-values q) ", "))]
    (str "INSERT INTO " (.-table-name q) " (" cols ") VALUES (" vals ");")))

(df render-update [(q UpdateQuery)] -> String
  :d "Renders a parameterized SQL UPDATE statement."
  (str "UPDATE " (.-table-name q) " SET " (string-join (.-set-assignments q) ", ") " WHERE " (.-where-clause q) ";"))

(df where-clause-suffix [(w String)] -> String
  :d "Helper to format WHERE clause suffix."
  (str " WHERE " w ";"))

(df render-delete [(tbl String) (where-clause String)] -> String
  :d "Renders a parameterized SQL DELETE statement."
  (str "DELETE FROM " tbl (where-clause-suffix where-clause)))
