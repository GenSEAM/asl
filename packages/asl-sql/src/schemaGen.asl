(module asl-sql/schemaGen
  :d "SQL DDL Table Schema Generator from Record Schemas"
  :x [deriveSqlTableSchema mapColumnDef]
  :i [(asl-derive/derive :a drv)])

(df mapColumnDef [(f drv/FieldDef) (isPk Bool) (dialect Str)] -> Str
  :d "Maps field definition to dialect-specific SQL column clause."
  (let [(fName (.-name f))
        (tName (.-typeName f))
        (opt (.-isOptional f))]
    (if isPk
      (if (= dialect "sqlite")
        (str fName " INTEGER PRIMARY KEY")
        (str fName " BIGINT PRIMARY KEY"))
      (if (= tName "Int")
        (if (= dialect "sqlite")
          (if opt (str fName " INTEGER") (str fName " INTEGER NOT NULL"))
          (if opt (str fName " BIGINT") (str fName " BIGINT NOT NULL")))
        (if (= tName "Str")
          (if opt (str fName " TEXT") (str fName " TEXT NOT NULL"))
          (if (= tName "Bool")
            (if opt (str fName " BOOLEAN") (str fName " BOOLEAN NOT NULL"))
            (if (= tName "Float")
              (if (= dialect "sqlite")
                (if opt (str fName " REAL") (str fName " REAL NOT NULL"))
                (if opt (str fName " DOUBLE PRECISION") (str fName " DOUBLE PRECISION NOT NULL")))
              (if opt (str fName " TEXT") (str fName " TEXT NOT NULL")))))))))

(df deriveSqlTableSchema [(schema drv/RecordSchema) (dialect Str)] -> Str
  :d "Generates CREATE TABLE DDL statement for specified dialect."
  (let [(tName (.-tableName schema))
        (pkOpt (.-primaryKey schema))
        (pkName (option-or pkOpt ""))
        (fields (.-fields schema))
        (colClauses (list-map
                      (fn [(f drv/FieldDef)]
                        (let [(isPk (and (!= pkName "") (= (.-name f) pkName)))]
                          (mapColumnDef f isPk dialect)))
                      fields))
        (joined (string-join colClauses ",\n  "))]
    (str "CREATE TABLE IF NOT EXISTS " tName " (\n  " joined "\n);")))
