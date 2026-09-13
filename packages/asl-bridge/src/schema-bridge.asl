(module asl-bridge/schemaBridge
  :d "Universal Multi-ORM schema transpiler for TypeScript, Python, and Rust ecosystems."
  :x [toPascalCase
      colCategory
      kyselyType
      renderKyselyCol
      tableToKysely
      drizzleTypeFn
      drizzleColBuilder
      tableToDrizzle
      sqlalchemyType
      renderSqlalchemyCol
      tableToSqlalchemy
      seaormType
      renderSeaormCol
      tableToSeaorm]
  :i [(ports :a p)])

(df capitalizeWord [(w Str)] -> Str
  :d "Capitalizes the first character of a word and lowers the rest."
  (let [(wLen (string-length w))]
    (if (<= wLen 0)
      ""
      (let [(head (string-upper (option-or (string-slice w 0 1) "")))
            (tail (string-lower (option-or (string-slice w 1 wLen) "")))]
        (str head tail)))))

(df toPascalCase [(s Str)] -> Str
  :d "Converts a snake_case or kebab-case identifier to PascalCase."
  (if (and (not (string-contains? s "_")) (not (string-contains? s "-")))
    (capitalizeWord s)
    (let [(norm (string-replace s "-" "_"))
          (parts (string-split norm "_"))
          (capped (map capitalizeWord parts))]
      (string-join capped ""))))

(df colCategory [(colType Str)] -> Str
  :d "Normalizes column type string into standard type category."
  (let [(norm (string-lower colType))]
    (cond
      ((or (= norm "i64") (or (= norm "int") (or (= norm "integer") (= norm "i32")))) "int")
      ((or (= norm "f64") (= norm "float")) "float")
      ((or (= norm "bool") (= norm "boolean")) "bool")
      ((= norm "timestamp") "timestamp")
      (:else "text"))))

(df kyselyType [(colType Str)] -> Str
  :d "Maps abstract column type to TypeScript primitive type."
  (let [(cat (colCategory colType))]
    (if (or (= cat "int") (= cat "float"))
      "number"
      (if (= cat "bool")
        "boolean"
        "string"))))

(df renderKyselyCol [(col p/DbColumn)] -> Str
  :d "Renders a single column for Kysely interface."
  (let [(baseType (kyselyType (.-colType col)))
        (finalType (if (.-nullable col) (str baseType " | null") baseType))]
    (str "  " (.-name col) ": " finalType ";")))

(df tableToKysely [(tbl p/TableDef)] -> Str
  :d "Translates TableDef to TypeScript Kysely interface definition."
  (let [(pName (toPascalCase (.-name tbl)))
        (colLines (map renderKyselyCol (.-columns tbl)))
        (body (string-join colLines "\n"))]
    (str "export interface " pName "Table {\n" body "\n}")))

(df drizzleTypeFn [(colType Str)] -> Str
  :d "Determines Drizzle column builder function name."
  (let [(cat (colCategory colType))]
    (if (= cat "int")
      "integer"
      (if (= cat "float")
        "real"
        (if (= cat "bool")
          "boolean"
          cat)))))

(df drizzleColBuilder [(col p/DbColumn)] -> Str
  :d "Renders Drizzle column builder chain."
  (let [(cName (.-name col))
        (typeFn (drizzleTypeFn (.-colType col)))
        (base (str typeFn "(\"" cName "\")"))
        (withPk (if (.-isPk col) (str base ".primaryKey()") base))
        (withNull (if (and (not (.-isPk col)) (not (.-nullable col))) (str withPk ".notNull()") withPk))]
    (str "  " cName ": " withNull ",")))

(df tableToDrizzle [(tbl p/TableDef)] -> Str
  :d "Translates TableDef to TypeScript Drizzle table definition."
  (let [(tName (.-name tbl))
        (colLines (map drizzleColBuilder (.-columns tbl)))
        (body (string-join colLines "\n"))]
    (str "export const " tName " = pgTable(\"" tName "\", {\n" body "\n});")))

(df sqlalchemyType [(colType Str)] -> Str
  :d "Maps abstract column type to Python type annotation."
  (let [(cat (colCategory colType))]
    (if (= cat "int")
      "int"
      (if (= cat "float")
        "float"
        (if (= cat "bool")
          "bool"
          "str")))))

(df renderSqlalchemyCol [(col p/DbColumn)] -> Str
  :d "Renders a single column for SQLAlchemy DeclarativeBase model."
  (let [(cName (.-name col))
        (pyType (sqlalchemyType (.-colType col)))
        (annot (if (.-nullable col) (str "Mapped[Optional[" pyType "]]") (str "Mapped[" pyType "]")))
        (arg (cond
               ((.-isPk col) "mapped_column(primary_key=True)")
               ((.-nullable col) "mapped_column(nullable=True)")
               (:else "mapped_column(nullable=False)")))]
    (str "    " cName ": " annot " = " arg)))

(df tableToSqlalchemy [(tbl p/TableDef)] -> Str
  :d "Translates TableDef to Python SQLAlchemy DeclarativeBase model definition."
  (let [(pName (toPascalCase (.-name tbl)))
        (colLines (map renderSqlalchemyCol (.-columns tbl)))
        (body (string-join colLines "\n"))]
    (str "class " pName "(Base):\n    __tablename__ = \"" (.-name tbl) "\"\n\n" body)))

(df seaormType [(colType Str)] -> Str
  :d "Maps abstract column type to Rust type annotation."
  (let [(cat (colCategory colType))]
    (if (= cat "int")
      "i64"
      (if (= cat "float")
        "f64"
        (if (= cat "bool")
          "bool"
          "String")))))

(df renderSeaormCol [(col p/DbColumn)] -> Str
  :d "Renders a single field for SeaORM entity model."
  (let [(cName (.-name col))
        (rType (seaormType (.-colType col)))
        (finalType (if (.-nullable col) (str "Option<" rType ">") rType))
        (fieldDecl (str "    pub " cName ": " finalType ","))]
    (if (.-isPk col)
      (str "    #[sea_orm(primary_key)]\n" fieldDecl)
      fieldDecl)))

(df tableToSeaorm [(tbl p/TableDef)] -> Str
  :d "Translates TableDef to Rust SeaORM entity struct definition."
  (let [(tName (.-name tbl))
        (colLines (map renderSeaormCol (.-columns tbl)))
        (body (string-join colLines "\n"))]
    (str "#[derive(Clone, Debug, PartialEq, DeriveEntityModel)]\n"
         "#[sea_orm(table_name = \"" tName "\")]\n"
         "pub struct Model {\n" body "\n}")))
