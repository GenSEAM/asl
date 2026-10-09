(module asl-sql/ddl :x [SqlColumnType ColumnDef TableDef InsertQuery UpdateQuery UpsertQuery typeToSqlString renderColumnDef renderCreateTable renderInsert renderUpdate renderDelete renderUpsert makeColumn makeColumnCustom makeTable makeInsert makeUpdate makeUpsert colInt64 colFloat64 colText colBoolean colBool colTimestamp] :i [(core :a sql)])

(enum SqlColumnType (:c colInt64 [] "64-bit integer (BIGINT)") (:c colFloat64 [] "64-bit floating point (DOUBLE PRECISION or REAL)") (:c colText [] "Variable length character string (TEXT)") (:c colBoolean [] "Boolean flag (BOOLEAN or INTEGER)") (:c colTimestamp [] "Timestamp with timezone (TIMESTAMPTZ or TEXT)"))

fn colBool -> SqlColumnType
  (colBoolean)

(schema ColumnDef (:f name String) (:f colType SqlColumnType) (:f isPrimary Bool) (:f isNullable Bool) (:f extraSql String))

(schema TableDef (:f tableName String) (:f columns (List ColumnDef)))

(schema InsertQuery (:f tableName String) (:f columns (List String)) (:f values (List String)))

(schema UpdateQuery (:f tableName String) (:f setAssignments (List String)) (:f whereClause String))

(schema UpsertQuery (:f tableName String) (:f columns (List String)) (:f values (List String)) (:f conflictCols (List String)) (:f updateCols (List String)))

fn makeColumn colName: String t: SqlColumnType pk: Bool nullable: Bool -> ColumnDef
  (ColumnDef :name colName :colType t :isPrimary pk :isNullable nullable :extraSql "")

fn makeColumnCustom colName: String t: SqlColumnType pk: Bool nullable: Bool extra: String -> ColumnDef
  (ColumnDef :name colName :colType t :isPrimary pk :isNullable nullable :extraSql extra)

fn makeTable name: String cols: (List ColumnDef) -> TableDef
  (TableDef :tableName name :columns cols)

fn makeInsert tbl: String cols: (List String) vals: (List String) -> InsertQuery
  (InsertQuery :tableName tbl :columns cols :values vals)

fn makeUpdate tbl: String assigns: (List String) whereSql: String -> UpdateQuery
  (UpdateQuery :tableName tbl :setAssignments assigns :whereClause whereSql)

fn makeUpsert tbl: String cols: (List String) vals: (List String) conflicts: (List String) updates: (List String) -> UpsertQuery
  (UpsertQuery :tableName tbl :columns cols :values vals :conflictCols conflicts :updateCols updates)

fn normalizeDialect dialect: sql/SqlDialect -> sql/SqlDialect
  dialect

fn typeToSqlString t: SqlColumnType dialect: sql/SqlDialect -> String
  (let [(d (normalizeDialect dialect))] (mt t ((colInt64) (mt d ((clickhouse) "Int64") (_ "BIGINT"))) ((colFloat64) (mt d ((postgres) "DOUBLE PRECISION") ((mysql) "DOUBLE") ((clickhouse) "Float64") (_ "REAL"))) ((colText) (mt d ((clickhouse) "String") (_ "TEXT"))) ((colBoolean) (mt d ((postgres) "BOOLEAN") ((mysql) "BOOLEAN") ((clickhouse) "Bool") (_ "INTEGER"))) ((colTimestamp) (mt d ((postgres) "TIMESTAMPTZ") ((mysql) "DATETIME") ((clickhouse) "DateTime64") (_ "TEXT")))))

fn renderColumnDef col: ColumnDef dialect: sql/SqlDialect -> String
  (let [(d (normalizeDialect dialect)) (tStr (typeToSqlString col.colType d)) (base (str col.name " " tStr)) (withPk (if col.isPrimary (str base " PRIMARY KEY") base)) (withNull (if col.isNullable withPk (str withPk " NOT NULL")))] (if (> (stringLength col.extraSql) 0) (str withNull " " col.extraSql) withNull))

fn formatAssignments cols: (List String) prefix: String suffix: String -> String
  (stringJoin (map (fn [c] (str c " = " prefix c suffix)) cols) ", ")

fn renderPlaceholderItem idx: Int64 dialect: sql/SqlDialect -> String
  (let [(d (normalizeDialect dialect))] (mt d ((postgres) (str "$" (stringFromInt64 idx))) (_ "?")))

fn renderPlaceholders count: Int64 dialect: sql/SqlDialect -> (List String)
  (if (<= count 0) (list) (let [(d (normalizeDialect dialect))] (map (fn [idx] (renderPlaceholderItem idx d)) (range 1 (+ count 1)))))

fn countColumns cols: (List String) vals: (List String) -> Int64
  (let [(cLen (listLength cols))] (if (> cLen 0) cLen (listLength vals)))

fn renderUpsert q: UpsertQuery dialect: sql/SqlDialect -> String
  (let [(d (normalizeDialect dialect)) (cLen (countColumns q.columns q.values)) (phList (renderPlaceholders cLen d)) (base (str "INSERT INTO " q.tableName " (" (stringJoin q.columns ", ") ") VALUES (" (stringJoin phList ", ") ") "))] (mt d ((mysql) (let [(upd (formatAssignments q.updateCols "VALUES(" ")"))] (str base "ON DUPLICATE KEY UPDATE " upd ";"))) (_ (let [(upd (formatAssignments q.updateCols "EXCLUDED." ""))] (str base "ON CONFLICT (" (stringJoin q.conflictCols ", ") ") DO UPDATE SET " upd ";")))))

fn renderCreateTable tbl: TableDef dialect: sql/SqlDialect -> String
  (let [(d (normalizeDialect dialect)) (renderedCols (map (fn [c] (renderColumnDef c d)) tbl.columns)) (colsBody (stringJoin renderedCols ", "))] (str "CREATE TABLE " tbl.tableName " (" colsBody ");"))

fn renderInsert q: InsertQuery dialect: sql/SqlDialect -> String
  (let [(d (normalizeDialect dialect)) (cols (stringJoin q.columns ", ")) (cLen (countColumns q.columns q.values)) (phList (renderPlaceholders cLen d)) (vals (stringJoin phList ", "))] (str "INSERT INTO " q.tableName " (" cols ") VALUES (" vals ");"))

fn renderUpdate q: UpdateQuery -> String
  (str "UPDATE " q.tableName " SET " (stringJoin q.setAssignments ", ") " WHERE " q.whereClause ";")

fn whereClauseSuffix w: String -> String
  (str " WHERE " w ";")

fn renderDelete tbl: String whereClause: String -> String
  (str "DELETE FROM " tbl (whereClauseSuffix whereClause))
