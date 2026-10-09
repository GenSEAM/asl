(module asl-sql/schemaGen :x [deriveSqlTableSchema mapColumnDef] :i [(asl-derive/derive :a drv)])

fn mapColumnDef f: drv/FieldDef isPk: Bool dialect: Str -> Str
  (let [(fName f.name) (tName f.typeName) (opt f.isOptional)] (if isPk (if (= dialect "sqlite") (str fName " INTEGER PRIMARY KEY") (str fName " BIGINT PRIMARY KEY")) (if (= tName "Int") (if (= dialect "sqlite") (if opt (str fName " INTEGER") (str fName " INTEGER NOT NULL")) (if opt (str fName " BIGINT") (str fName " BIGINT NOT NULL"))) (if (= tName "Str") (if opt (str fName " TEXT") (str fName " TEXT NOT NULL")) (if (= tName "Bool") (if opt (str fName " BOOLEAN") (str fName " BOOLEAN NOT NULL")) (if (= tName "Float") (if (= dialect "sqlite") (if opt (str fName " REAL") (str fName " REAL NOT NULL")) (if opt (str fName " DOUBLE PRECISION") (str fName " DOUBLE PRECISION NOT NULL"))) (if opt (str fName " TEXT") (str fName " TEXT NOT NULL"))))))))

fn deriveSqlTableSchema schema: drv/RecordSchema dialect: Str -> Str
  (let [(tName schema.tableName) (pkOpt schema.primaryKey) (pkName (optionOr pkOpt "")) (fields schema.fields) (colClauses (map (fn [(f drv/FieldDef)] (let [(isPk (and (!= pkName "") (= f.name pkName)))] (mapColumnDef f isPk dialect))) fields)) (joined (stringJoin colClauses ",\n  "))] (str "CREATE TABLE IF NOT EXISTS " tName " (\n  " joined "\n);"))
