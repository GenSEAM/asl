(module asl-derive
  :d "Top-level facade for asl-derive package"
  :x [FieldDef RecordSchema VariantCaseDef VariantSchema
      JsonCodec AsnCodec VisitorCode VariantCodec
      makeField makeRecordSchema makeVariantCase makeVariantSchema
      deriveJsonCodec deriveAsnCodec deriveRecordVisitor deriveVariantCodec
      formatRecordToJson formatRecordToAsn
      parseJsonToFieldPairs parseAsnToFieldPairs
      runTests RunTests]
  :i [(asl-derive/derive :a drv)])

(df makeField [(name Str) (typeName Str) (isOptional Bool)] -> drv/FieldDef
  (drv/makeField name typeName isOptional))

(df makeRecordSchema [(name Str) (tableName Str) (primaryKey (Option Str)) (fields (List drv/FieldDef))] -> drv/RecordSchema
  (drv/makeRecordSchema name tableName primaryKey fields))

(df makeVariantCase [(tagName Str) (payloadType (Option Str))] -> drv/VariantCaseDef
  (drv/makeVariantCase tagName payloadType))

(df makeVariantSchema [(name Str) (cases (List drv/VariantCaseDef))] -> drv/VariantSchema
  (drv/makeVariantSchema name cases))

(df deriveJsonCodec [(schema drv/RecordSchema)] -> drv/JsonCodec
  (drv/deriveJsonCodec schema))

(df deriveAsnCodec [(schema drv/RecordSchema)] -> drv/AsnCodec
  (drv/deriveAsnCodec schema))

(df deriveRecordVisitor [(schema drv/RecordSchema)] -> drv/VisitorCode
  (drv/deriveRecordVisitor schema))

(df deriveVariantCodec [(schema drv/VariantSchema)] -> drv/VariantCodec
  (drv/deriveVariantCodec schema))

(df formatRecordToJson [(schema drv/RecordSchema) (fieldVals (List (Pair Str Str)))] -> Str
  (drv/formatRecordToJson schema fieldVals))

(df formatRecordToAsn [(schema drv/RecordSchema) (fieldVals (List (Pair Str Str)))] -> Str
  (drv/formatRecordToAsn schema fieldVals))

(df parseJsonToFieldPairs [(schema drv/RecordSchema) (json Str)] -> (List (Pair Str Str))
  (drv/parseJsonToFieldPairs schema json))

(df parseAsnToFieldPairs [(schema drv/RecordSchema) (asn Str)] -> (List (Pair Str Str))
  (drv/parseAsnToFieldPairs schema asn))

(df runTests [] -> Bool
  true)

(df RunTests [] -> Bool
  (runTests))
