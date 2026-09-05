(module asl-bridge/schema-facade
  :d "Facade bridge export for schema transpiler definitions."
  :x [table-to-kysely
      table-to-drizzle
      table-to-sqlalchemy
      table-to-seaorm]
  :i [(schema-bridge :a sb) (ports :a p)])

(df table-to-kysely [(tbl p/TableDef)] -> Str
  :d "Translates TableDef to TypeScript Kysely interface."
  (sb/table-to-kysely tbl))

(df table-to-drizzle [(tbl p/TableDef)] -> Str
  :d "Translates TableDef to TypeScript Drizzle table definition."
  (sb/table-to-drizzle tbl))

(df table-to-sqlalchemy [(tbl p/TableDef)] -> Str
  :d "Translates TableDef to Python SQLAlchemy DeclarativeBase model definition."
  (sb/table-to-sqlalchemy tbl))

(df table-to-seaorm [(tbl p/TableDef)] -> Str
  :d "Translates TableDef to Rust SeaORM entity struct definition."
  (sb/table-to-seaorm tbl))
