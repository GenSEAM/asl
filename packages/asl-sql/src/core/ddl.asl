(module asl-sql/ddl
  :doc "Native AgentScript SQL DDL (Schema & Migrations) and DML (Insert, Update, Delete) Generator."
  :export [SqlColumnType ColumnDef TableDef InsertQuery UpdateQuery
           type-to-sql-string render-column-def render-create-table
           render-insert render-update render-delete make-column make-table make-insert make-update])

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
  (:field is-nullable Bool "True if column allows NULL values"))

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

(defun make-column [(col-name String) (t SqlColumnType) (pk Bool) (nullable Bool)] -> ColumnDef
  :doc "Constructs a ColumnDef record."
  (ColumnDef :name col-name :col-type t :is-primary pk :is-nullable nullable))

(defun make-table [(name String) (cols (List ColumnDef))] -> TableDef
  :doc "Constructs a TableDef record."
  (TableDef :table-name name :columns cols))

(defun make-insert [(tbl String) (cols (List String)) (vals (List String))] -> InsertQuery
  :doc "Constructs an InsertQuery record."
  (InsertQuery :table-name tbl :columns cols :values vals))

(defun make-update [(tbl String) (assigns (List String)) (where-sql String)] -> UpdateQuery
  :doc "Constructs an UpdateQuery record."
  (UpdateQuery :table-name tbl :set-assignments assigns :where-clause where-sql))

(defun type-to-sql-string [(t SqlColumnType) (is-pg Bool)] -> String
  :doc "Maps abstract column type to target dialect data type keyword."
  (match t
    ((col-int64)     "BIGINT")
    ((col-float64)   (if is-pg "DOUBLE PRECISION" "REAL"))
    ((col-text)      "TEXT")
    ((col-boolean)   (if is-pg "BOOLEAN" "INTEGER"))
    ((col-timestamp) (if is-pg "TIMESTAMPTZ" "TEXT"))))

(defun render-column-def [(col ColumnDef) (is-pg Bool)] -> String
  :doc "Renders a single column definition line for CREATE TABLE."
  (let [(t-str (type-to-sql-string (.-col-type col) is-pg))
        (base (str (.-name col) " " t-str))
        (with-pk (if (.-is-primary col) (str base " PRIMARY KEY") base))]
    (if (.-is-nullable col)
      with-pk
      (str with-pk " NOT NULL"))))

(defun render-create-table [(tbl TableDef) (is-pg Bool)] -> String
  :doc "Renders a complete SQL CREATE TABLE DDL statement."
  (let [(rendered-cols (map (fn [c] (render-column-def c is-pg)) (.-columns tbl)))
        (cols-body (string-join rendered-cols ", "))]
    (str "CREATE TABLE " (.-table-name tbl) " (" cols-body ");")))

(defun render-insert [(q InsertQuery)] -> String
  :doc "Renders a parameterized SQL INSERT statement."
  (let [(cols-sql (string-join (.-columns q) ", "))
        (vals-sql (string-join (.-values q) ", "))]
    (str "INSERT INTO " (.-table-name q) " (" cols-sql ") VALUES (" vals-sql ");")))

(defun render-update [(q UpdateQuery)] -> String
  :doc "Renders a parameterized SQL UPDATE statement."
  (let [(assign-sql (string-join (.-set-assignments q) ", "))]
    (str "UPDATE " (.-table-name q) " SET " assign-sql " WHERE " (.-where-clause q) ";")))

(defun render-delete [(tbl String) (where-clause String)] -> String
  :doc "Renders a parameterized SQL DELETE statement."
  (str "DELETE FROM " tbl " WHERE " where-clause ";"))
