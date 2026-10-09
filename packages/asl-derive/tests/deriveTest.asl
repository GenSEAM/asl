(module asl-derive/tests/deriveTest
  :x [testFieldCreation testRecordSchema testDeriveJsonCodec testDeriveAsnCodec testVariantSchema runTests]
  :i [(asl-derive/derive :a d)])

fn testFieldCreation -> Bool
  (let [(f1 (d/makeField "id" "I64" false))
        (f2 (d/makeField "email" "Str" true))]
    (do
      (assert (= f1.name "id") "f1 name is id")
      (assert (= f1.typeName "I64") "f1 type is I64")
      (refute (!= f1.typeName "I64") "f1 type refutes non-I64")
      (assert (not f1.isOptional) "f1 is not optional")
      (refute f1.isOptional "f1 refutes optional")
      (assert f2.isOptional "f2 is optional")
      (refute (not f2.isOptional) "f2 refutes non-optional")
      true))

fn testRecordSchema -> Bool
  (let [(f1 (d/makeField "id" "I64" false))
        (f2 (d/makeField "name" "Str" false))
        (schema (d/makeRecordSchema "User" "users" (some "id") (list f1 f2)))]
    (do
      (assert (= schema.name "User") "schema name is User")
      (refute (!= schema.name "User") "schema name refutes mismatch")
      (assert (= schema.tableName "users") "table is users")
      (assert (= (listLength schema.fields) 2) "has 2 fields")
      (refute (!= (listLength schema.fields) 2) "fields count refutes non-2")
      true))

fn testDeriveJsonCodec -> Bool
  (let [(f1 (d/makeField "title" "Str" false))
        (schema (d/makeRecordSchema "Post" "posts" (none) (list f1)))
        (codec (d/deriveJsonCodec schema))]
    (do
      (assert (stringContains? codec.encoderSource "serializePostToJson") "codec has serializePostToJson")
      (refute (stringEmpty? codec.encoderSource) "JSON encoder source refutes empty")
      (refute (stringContains? codec.encoderSource "undefined") "JSON encoder source refutes undefined")
      true))

fn testDeriveAsnCodec -> Bool
  (let [(f1 (d/makeField "status" "Str" false))
        (schema (d/makeRecordSchema "StatusRecord" "statuses" (none) (list f1)))
        (codec (d/deriveAsnCodec schema))]
    (do
      (assert (stringContains? codec.encoderSource "serializeStatusRecordToAsn") "codec has serializeStatusRecordToAsn")
      (refute (stringEmpty? codec.encoderSource) "ASN encoder source refutes empty")
      (refute (stringContains? codec.encoderSource "undefined") "ASN encoder source refutes undefined")
      true))

fn testVariantSchema -> Bool
  (let [(c1 (d/makeVariantCase "active" (none)))
        (c2 (d/makeVariantCase "suspended" (some "Str")))
        (vSchema (d/makeVariantSchema "AccountStatus" (list c1 c2)))]
    (do
      (assert (= vSchema.name "AccountStatus") "variant name matches")
      (refute (!= vSchema.name "AccountStatus") "variant name refutes mismatch")
      (assert (= (listLength vSchema.cases) 2) "variant has 2 cases")
      (refute (!= (listLength vSchema.cases) 2) "variant cases refutes non-2")
      true))

fn ! runTests -> Bool
  (do
    (assert (testFieldCreation) "testFieldCreation")
    (assert (testRecordSchema) "testRecordSchema")
    (assert (testDeriveJsonCodec) "testDeriveJsonCodec")
    (assert (testDeriveAsnCodec) "testDeriveAsnCodec")
    (assert (testVariantSchema) "testVariantSchema")
    true)
