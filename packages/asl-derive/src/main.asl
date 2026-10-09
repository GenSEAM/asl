(module asl-derive :x [FieldDef RecordSchema VariantCaseDef VariantSchema JsonCodec AsnCodec VisitorCode VariantCodec makeField makeRecordSchema makeVariantCase makeVariantSchema deriveJsonCodec deriveAsnCodec deriveRecordVisitor deriveVariantCodec formatRecordToJson formatRecordToAsn parseJsonToFieldPairs parseAsnToFieldPairs runTests RunTests] :i [(asl-derive/derive :a drv)])

fn makeField name: Str typeName: Str isOptional: Bool -> drv/FieldDef
  (drv/makeField name typeName isOptional)

fn makeRecordSchema name: Str tableName: Str primaryKey: (Option Str) fields: (List drv/FieldDef) -> drv/RecordSchema
  (drv/makeRecordSchema name tableName primaryKey fields)

fn makeVariantCase tagName: Str payloadType: (Option Str) -> drv/VariantCaseDef
  (drv/makeVariantCase tagName payloadType)

fn makeVariantSchema name: Str cases: (List drv/VariantCaseDef) -> drv/VariantSchema
  (drv/makeVariantSchema name cases)

fn deriveJsonCodec schema: drv/RecordSchema -> drv/JsonCodec
  (drv/deriveJsonCodec schema)

fn deriveAsnCodec schema: drv/RecordSchema -> drv/AsnCodec
  (drv/deriveAsnCodec schema)

fn deriveRecordVisitor schema: drv/RecordSchema -> drv/VisitorCode
  (drv/deriveRecordVisitor schema)

fn deriveVariantCodec schema: drv/VariantSchema -> drv/VariantCodec
  (drv/deriveVariantCodec schema)

fn formatRecordToJson schema: drv/RecordSchema fieldVals: (List (Pair Str Str)) -> Str
  (drv/formatRecordToJson schema fieldVals)

fn formatRecordToAsn schema: drv/RecordSchema fieldVals: (List (Pair Str Str)) -> Str
  (drv/formatRecordToAsn schema fieldVals)

fn parseJsonToFieldPairs schema: drv/RecordSchema json: Str -> (List (Pair Str Str))
  (drv/parseJsonToFieldPairs schema json)

fn parseAsnToFieldPairs schema: drv/RecordSchema asn: Str -> (List (Pair Str Str))
  (drv/parseAsnToFieldPairs schema asn)

fn runTests -> Bool
  (let [(f1 (makeField "id" "I64" false))
        (s1 (makeRecordSchema "User" "users" (some "id") (list f1)))
        (jc (deriveJsonCodec s1))
        (ac (deriveAsnCodec s1))]
    (do
      (assert (= s1.name "User") "schema name verified")
      (assert (stringContains? jc.encoderSource "serializeUserToJson") "JSON codec verified")
      (assert (stringContains? ac.encoderSource "serializeUserToAsn") "ASN codec verified")
      true))

fn RunTests -> Bool
  (runTests)
