(module asl-sql/ddl
  :doc "Native AgentScript SQL DDL (Schema & Migrations) and DML (Insert, Update, Delete, Upsert) Generator."
  :export [SqlColumnType ColumnDef TableDef InsertQuery UpdateQuery UpsertQuery
           type-to-sql-string render-column-def render-create-table
           render-insert render-update render-delete render-upsert
           make-column make-column-custom make-table make-insert make-update make-upsert])

(defenum SqlColumnType
  (:case col-int64     [] "64-bit integer (BIGINT)")
  (:case col-float64   [] "64-bit floating point (DOUBLE PRECISION or REAL)")
  (:case col-text      [] "Variable length character string (TEXT)")
  (:case col-boolean   [] "Boolean flag (BOOLEAN or INTEGER)")
  (:case col-timestamp [] "Timestamp with timezone (TIMESTAMPTZ or TEXT)"))

(defschema ColumnDef
  (:field name String "Column identifier name")
  (:field col-type SqlColumnType "Data type of the column")
  (:field is-primary Bool "True if column is PRIMARY KEY")
  (:field is-nullable Bool "True if column allows NULL values")
  (:field extra-sql String "Custom vendor-specific SQL clauses (e.g. REFERENCES, COLLATE, DEFAULT)"))

(defschema TableDef
  (:field table-name String "Target database table name")
  (:field columns (List ColumnDef) "List of column definitions"))

(defschema InsertQuery
  (:field table-name String "Target table to insert into")
  (:field columns (List String) "Column identifiers")
  (:field values (List String) "Parameter placeholder strings"))

(defschema UpdateQuery
  (:field table-name String "Target table to update")
  (:field set-assignments (List String) "Column assignments (col = val)")
  (:field where-clause String "Update predicate condition"))

(defschema UpsertQuery
  (:field table-name String "Target table to upsert into")
  (:field columns (List String) "Column identifiers")
  (:field values (List String) "Parameter placeholder strings")
  (:field conflict-cols (List String) "Conflict target columns for ON CONFLICT")
  (:field update-cols (List String) "Columns to update on conflict"))

(defun make-column [(col-name String) (t SqlColumnType) (pk Bool) (nullable Bool)] -> ColumnDef
  :doc "Constructs a standard ColumnDef record."
  (ColumnDef :name col-name :col-type t :is-primary pk :is-nullable nullable :extra-sql ""))

(defun make-column-custom [(col-name String) (t SqlColumnType) (pk Bool) (nullable Bool) (extra String)] -> ColumnDef
  :doc "Constructs a ColumnDef record with custom vendor extra SQL clause."
  (ColumnDef :name col-name :col-type t :is-primary pk :is-nullable nullable :extra-sql extra))

(defun make-table [(name String) (cols (List ColumnDef))] -> TableDef
  :doc "Constructs a TableDef record."
  (TableDef :table-name name :columns cols))

(defun make-insert [(tbl String) (cols (List String)) (vals (List String))] -> InsertQuery
  :doc "Constructs an InsertQuery record."
  (InsertQuery :table-name tbl :columns cols :values vals))

(defun make-update [(tbl String) (assigns (List String)) (where-sql String)] -> UpdateQuery
  :doc "Constructs an UpdateQuery record."
  (UpdateQuery :table-name tbl :set-assignments assigns :where-clause where-sql))

(defun make-upsert [(tbl String) (cols (List String)) (vals (List String)) (conflicts (List String)) (updates (List String))] -> UpsertQuery
  :doc "Constructs an UpsertQuery record."
  (UpsertQuery :table-name tbl :columns cols :values vals :conflict-cols conflicts :update-cols updates))

(defun pg-or-alt [(is-pg Bool) (pg-type String) (alt-type String)] -> String
  :doc "Returns pg-type when is-pg is true, otherwise alt-type."
  (if is-pg pg-type alt-type))

(defun type-to-sql-string [(t SqlColumnType) (is-pg Bool)] -> String
  :doc "Maps abstract column type to target dialect data type keyword."
  (match t
    ((col-int64)     "BIGINT")
    ((col-float64)   (pg-or-alt is-pg "DOUBLE PRECISION" "REAL"))
    ((col-text)      "TEXT")
    ((col-boolean)   (pg-or-alt is-pg "BOOLEAN" "INTEGER"))
    ((col-timestamp) (pg-or-alt is-pg "TIMESTAMPTZ" "TEXT"))))

(defun render-column-def [(col ColumnDef) (is-pg Bool)] -> String
  :doc "Renders a single column definition line for CREATE TABLE."
  (let [(t-str (type-to-sql-string (.-col-type col) is-pg))
        (base (str (.-name col) " " t-str))
        (with-pk (if (.-is-primary col) (str base " PRIMARY KEY") base))
        (with-null (if (.-is-nullable col) with-pk (str with-pk " NOT NULL")))]
    (if (> (string-length (.-extra-sql col)) 0)
      (str with-null " " (.-extra-sql col))
      with-null)))

(defun format-assignments [(cols (List String)) (prefix String) (suffix String)] -> String
  :doc "Helper to format assignment pairs."
  (string-join (map (fn [c] (str c " = " prefix c suffix)) cols) ", "))

(defun render-upsert [(q UpsertQuery) (is-pg Bool)] -> String
  :doc "Renders cross-dialect UPSERT query (Postgres/SQLite ON CONFLICT vs MySQL ON DUPLICATE KEY)."
  (let [(base (str "INSERT INTO " (.-table-name q) " (" (string-join (.-columns q) ", ") ") VALUES (" (string-join (.-values q) ", ") ") "))]
    (if is-pg
      (let [(upd (format-assignments (.-update-cols q) "EXCLUDED." ""))]
        (str base "ON CONFLICT (" (string-join (.-conflict-cols q) ", ") ") DO UPDATE SET " upd ";"))
      (let [(upd (format-assignments (.-update-cols q) "VALUES(" ")"))]
        (str base "ON DUPLICATE KEY UPDATE " upd ";")))))

(defun render-create-table [(tbl TableDef) (is-pg Bool)] -> String
  :doc "Renders a complete SQL CREATE TABLE DDL statement."
  (let [(rendered-cols (map (fn [c] (render-column-def c is-pg)) (.-columns tbl)))
        (cols-body (string-join rendered-cols ", "))]
    (str "CREATE TABLE " (.-table-name tbl) " (" cols-body ");")))

(defun render-insert [(q InsertQuery)] -> String
  :doc "Renders a parameterized SQL INSERT statement."
  (let [(cols (string-join (.-columns q) ", "))
        (vals (string-join (.-values q) ", "))]
    (str "INSERT INTO " (.-table-name q) " (" cols ") VALUES (" vals ");")))

(defun render-update [(q UpdateQuery)] -> String
  :doc "Renders a parameterized SQL UPDATE statement."
  (str "UPDATE " (.-table-name q) " SET " (string-join (.-set-assignments q) ", ") " WHERE " (.-where-clause q) ";"))

(defun where-clause-suffix [(w String)] -> String
  :doc "Helper to format WHERE clause suffix."
  (str " WHERE " w ";"))

(defun render-delete [(tbl String) (where-clause String)] -> String
  :doc "Renders a parameterized SQL DELETE statement."
  (str "DELETE FROM " tbl (where-clause-suffix where-clause)))
