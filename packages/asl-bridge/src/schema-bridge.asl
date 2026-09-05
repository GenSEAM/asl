(module asl-bridge/schema-bridge
  :d "Universal Multi-ORM schema transpiler for TypeScript, Python, and Rust ecosystems."
  :x [to-pascal-case
      col-category
      kysely-type
      render-kysely-col
      table-to-kysely
      drizzle-type-fn
      drizzle-col-builder
      table-to-drizzle
      sqlalchemy-type
      render-sqlalchemy-col
      table-to-sqlalchemy
      seaorm-type
      render-seaorm-col
      table-to-seaorm]
  :i [(ports :a p)])

(df capitalize-word [(w Str)] -> Str
  :d "Capitalizes the first character of a word and lowers the rest."
  (let [(w-len (string-length w))]
    (if (<= w-len 0)
      ""
      (let [(head (string-upper (option-or (string-slice w 0 1) "")))
            (tail (string-lower (option-or (string-slice w 1 w-len) "")))]
        (str head tail)))))

(df to-pascal-case [(s Str)] -> Str
  :d "Converts a snake_case or kebab-case identifier to PascalCase."
  (if (and (not (string-contains? s "_")) (not (string-contains? s "-")))
    (capitalize-word s)
    (let [(norm (string-replace s "-" "_"))
          (parts (string-split norm "_"))
          (capped (map capitalize-word parts))]
      (string-join capped ""))))

(df col-category [(col-type Str)] -> Str
  :d "Normalizes column type string into standard type category."
  (let [(norm (string-lower col-type))]
    (cond
      ((or (= norm "i64") (or (= norm "int") (or (= norm "integer") (= norm "i32")))) "int")
      ((or (= norm "f64") (= norm "float")) "float")
      ((or (= norm "bool") (= norm "boolean")) "bool")
      ((= norm "timestamp") "timestamp")
      (:else "text"))))

(df kysely-type [(col-type Str)] -> Str
  :d "Maps abstract column type to TypeScript primitive type."
  (let [(cat (col-category col-type))]
    (if (or (= cat "int") (= cat "float"))
      "number"
      (if (= cat "bool")
        "boolean"
        "string"))))

(df render-kysely-col [(col p/DbColumn)] -> Str
  :d "Renders a single column for Kysely interface."
  (let [(base-type (kysely-type (.-col-type col)))
        (final-type (if (.-nullable col) (str base-type " | null") base-type))]
    (str "  " (.-name col) ": " final-type ";")))

(df table-to-kysely [(tbl p/TableDef)] -> Str
  :d "Translates TableDef to TypeScript Kysely interface definition."
  (let [(p-name (to-pascal-case (.-name tbl)))
        (col-lines (map render-kysely-col (.-columns tbl)))
        (body (string-join col-lines "\n"))]
    (str "export interface " p-name "Table {\n" body "\n}")))

(df drizzle-type-fn [(col-type Str)] -> Str
  :d "Determines Drizzle column builder function name."
  (let [(cat (col-category col-type))]
    (if (= cat "int")
      "integer"
      (if (= cat "float")
        "real"
        cat))))

(df drizzle-col-builder [(col p/DbColumn)] -> Str
  :d "Renders Drizzle column builder chain."
  (let [(c-name (.-name col))
        (type-fn (drizzle-type-fn (.-col-type col)))
        (base (str type-fn "(\"" c-name "\")"))
        (with-pk (if (.-is-pk col) (str base ".primaryKey()") base))
        (with-null (if (and (not (.-is-pk col)) (not (.-nullable col))) (str with-pk ".notNull()") with-pk))]
    (str "  " c-name ": " with-null ",")))

(df table-to-drizzle [(tbl p/TableDef)] -> Str
  :d "Translates TableDef to TypeScript Drizzle table definition."
  (let [(t-name (.-name tbl))
        (col-lines (map drizzle-col-builder (.-columns tbl)))
        (body (string-join col-lines "\n"))]
    (str "export const " t-name " = pgTable(\"" t-name "\", {\n" body "\n});")))

(df sqlalchemy-type [(col-type Str)] -> Str
  :d "Maps abstract column type to Python type annotation."
  (let [(cat (col-category col-type))]
    (if (= cat "int")
      "int"
      (if (= cat "float")
        "float"
        (if (= cat "bool")
          "bool"
          "str")))))

(df render-sqlalchemy-col [(col p/DbColumn)] -> Str
  :d "Renders a single column for SQLAlchemy DeclarativeBase model."
  (let [(c-name (.-name col))
        (py-type (sqlalchemy-type (.-col-type col)))
        (annot (if (.-nullable col) (str "Mapped[Optional[" py-type "]]") (str "Mapped[" py-type "]")))
        (arg (cond
               ((.-is-pk col) "mapped_column(primary_key=True)")
               ((.-nullable col) "mapped_column(nullable=True)")
               (:else "mapped_column(nullable=False)")))]
    (str "    " c-name ": " annot " = " arg)))

(df table-to-sqlalchemy [(tbl p/TableDef)] -> Str
  :d "Translates TableDef to Python SQLAlchemy DeclarativeBase model definition."
  (let [(p-name (to-pascal-case (.-name tbl)))
        (col-lines (map render-sqlalchemy-col (.-columns tbl)))
        (body (string-join col-lines "\n"))]
    (str "class " p-name "(Base):\n    __tablename__ = \"" (.-name tbl) "\"\n\n" body)))

(df seaorm-type [(col-type Str)] -> Str
  :d "Maps abstract column type to Rust type annotation."
  (let [(cat (col-category col-type))]
    (if (= cat "int")
      "i64"
      (if (= cat "float")
        "f64"
        (if (= cat "bool")
          "bool"
          "String")))))

(df render-seaorm-col [(col p/DbColumn)] -> Str
  :d "Renders a single field for SeaORM entity model."
  (let [(c-name (.-name col))
        (r-type (seaorm-type (.-col-type col)))
        (final-type (if (.-nullable col) (str "Option<" r-type ">") r-type))
        (field-decl (str "    pub " c-name ": " final-type ","))]
    (if (.-is-pk col)
      (str "    #[sea_orm(primary_key)]\n" field-decl)
      field-decl)))

(df table-to-seaorm [(tbl p/TableDef)] -> Str
  :d "Translates TableDef to Rust SeaORM entity struct definition."
  (let [(t-name (.-name tbl))
        (col-lines (map render-seaorm-col (.-columns tbl)))
        (body (string-join col-lines "\n"))]
    (str "#[derive(Clone, Debug, PartialEq, DeriveEntityModel)]\n"
         "#[sea_orm(table_name = \"" t-name "\")]\n"
         "pub struct Model {\n" body "\n}")))
