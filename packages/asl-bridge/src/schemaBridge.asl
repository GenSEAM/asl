(module asl-bridge/schemaBridge :x [toPascalCase colCategory kyselyType renderKyselyCol tableToKysely drizzleTypeFn drizzleColBuilder tableToDrizzle sqlalchemyType renderSqlalchemyCol tableToSqlalchemy seaormType renderSeaormCol tableToSeaorm] :i [(ports :a p)])

fn capitalizeWord w: Str -> Str
  (let [(wLen (stringLength w))] (if (<= wLen 0) "" (let [(head (stringUpper (optionOr (stringSlice w 0 1) ""))) (tail (stringLower (optionOr (stringSlice w 1 wLen) "")))] (str head tail))))

fn toPascalCase s: Str -> Str
  (if (and (not (stringContains? s "_")) (not (stringContains? s "-"))) (capitalizeWord s) (let [(norm (stringReplace s "-" "_")) (parts (stringSplit norm "_")) (capped (map capitalizeWord parts))] (stringJoin capped "")))

fn colCategory colType: Str -> Str
  (let [(norm (stringLower colType))] (cond ((or (= norm "i64") (or (= norm "int") (or (= norm "integer") (= norm "i32")))) "int") ((or (= norm "f64") (= norm "float")) "float") ((or (= norm "bool") (= norm "boolean")) "bool") ((= norm "timestamp") "timestamp") (else "text")))

fn kyselyType colType: Str -> Str
  (let [(cat (colCategory colType))] (if (or (= cat "int") (= cat "float")) "number" (if (= cat "bool") "boolean" "string")))

fn renderKyselyCol col: p/DbColumn -> Str
  (let [(baseType (kyselyType col.colType)) (finalType (if col.nullable (str baseType " | null") baseType))] (str "  " col.name ": " finalType ";"))

fn tableToKysely tbl: p/TableDef -> Str
  (let [(pName (toPascalCase tbl.name)) (colLines (map renderKyselyCol tbl.columns)) (body (stringJoin colLines "\n"))] (str "export interface " pName "Table {\n" body "\n}"))

fn drizzleTypeFn colType: Str -> Str
  (let [(cat (colCategory colType))] (if (= cat "int") "integer" (if (= cat "float") "real" (if (= cat "bool") "boolean" cat))))

fn drizzleColBuilder col: p/DbColumn -> Str
  (let [(cName col.name) (typeFn (drizzleTypeFn col.colType)) (base (str typeFn "(\"" cName "\")")) (withPk (if col.isPk (str base ".primaryKey()") base)) (withNull (if (and (not col.isPk) (not col.nullable)) (str withPk ".notNull()") withPk))] (str "  " cName ": " withNull ","))

fn tableToDrizzle tbl: p/TableDef -> Str
  (let [(tName tbl.name) (colLines (map drizzleColBuilder tbl.columns)) (body (stringJoin colLines "\n"))] (str "export const " tName " = pgTable(\"" tName "\", {\n" body "\n});"))

fn sqlalchemyType colType: Str -> Str
  (let [(cat (colCategory colType))] (if (= cat "int") "int" (if (= cat "float") "float" (if (= cat "bool") "bool" "str"))))

fn renderSqlalchemyCol col: p/DbColumn -> Str
  (let [(cName col.name) (pyType (sqlalchemyType col.colType)) (annot (if col.nullable (str "Mapped[Optional[" pyType "]]") (str "Mapped[" pyType "]"))) (arg (cond (col.isPk "mapped_column(primary_key=True)") (col.nullable "mapped_column(nullable=True)") (else "mapped_column(nullable=False)")))] (str "    " cName ": " annot " = " arg))

fn tableToSqlalchemy tbl: p/TableDef -> Str
  (let [(pName (toPascalCase tbl.name)) (colLines (map renderSqlalchemyCol tbl.columns)) (body (stringJoin colLines "\n"))] (str "class " pName "(Base):\n    __tablename__ = \"" tbl.name "\"\n\n" body))

fn seaormType colType: Str -> Str
  (let [(cat (colCategory colType))] (if (= cat "int") "i64" (if (= cat "float") "f64" (if (= cat "bool") "bool" "String"))))

fn renderSeaormCol col: p/DbColumn -> Str
  (let [(cName col.name) (rType (seaormType col.colType)) (finalType (if col.nullable (str "Option<" rType ">") rType)) (fieldDecl (str "    pub " cName ": " finalType ","))] (if col.isPk (str "    #[sea_orm(primary_key)]\n" fieldDecl) fieldDecl))

fn tableToSeaorm tbl: p/TableDef -> Str
  (let [(tName tbl.name) (colLines (map renderSeaormCol tbl.columns)) (body (stringJoin colLines "\n"))] (str "#[derive(Clone, Debug, PartialEq, DeriveEntityModel)]\n" "#[sea_orm(table_name = \"" tName "\")]\n" "pub struct Model {\n" body "\n}"))
