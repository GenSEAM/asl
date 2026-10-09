(module asl-syntax/asl/astSchema
  :x [generateAstSchema
      generateAstSchemaFromAstFile!
      validateJsonSchema
      validateTopFormWithSchema
      prettyJson
      jsonEqual?
      findKey
      getProp
      getString
      getInt
      getFloat
      getBool
      getArray
      getObject
      main]
  :i [(asl-parser/ast :a a)
      (asl-json/json :a j)])

fn findKey kvs: (List (Pair String j/Json)) key: String -> (Option j/Json)
  (mt (listHead kvs)
    ((none) (none))
    ((some p)
     (if (= (pairFirst p) key)
       (some (pairSecond p))
       (findKey (optionOr (listTail kvs) (list)) key))))

fn getProp val: j/Json key: String -> (Option j/Json)
  (mt val
    ((j/jobj kvs) (findKey kvs key))
    (_ (none)))

fn getString val: j/Json key: String -> (Option String)
  (mt (getProp val key)
    ((some pVal)
     (mt pVal
       ((j/jstr s) (some s))
       (_ (none))))
    (_ (none)))

fn getInt val: j/Json key: String -> (Option Int64)
  (mt (getProp val key)
    ((some pVal)
     (mt pVal
       ((j/jint i) (some i))
       (_ (none))))
    (_ (none)))

fn getFloat val: j/Json key: String -> (Option Float64)
  (mt (getProp val key)
    ((some pVal)
     (mt pVal
       ((j/jfloat f) (some f))
       ((j/jint i) (some (int64ToFloat64 i)))
       (_ (none))))
    (_ (none)))

fn getBool val: j/Json key: String -> (Option Bool)
  (mt (getProp val key)
    ((some pVal)
     (mt pVal
       ((j/jbool b) (some b))
       (_ (none))))
    (_ (none)))

fn getArray val: j/Json key: String -> (Option (List j/Json))
  (mt (getProp val key)
    ((some pVal)
     (mt pVal
       ((j/jarr xs) (some xs))
       (_ (none))))
    (_ (none)))

fn getObject val: j/Json key: String -> (Option (List (Pair String j/Json)))
  (mt (getProp val key)
    ((some pVal)
     (mt pVal
       ((j/jobj kvs) (some kvs))
       (_ (none))))
    (_ (none)))

fn jsonEqual? a: j/Json b: j/Json -> Bool
  (mt a
    ((j/jnull) (mt b ((j/jnull) true) (_ false)))
    ((j/jbool ba) (mt b ((j/jbool bb) (= ba bb)) (_ false)))
    ((j/jint ia)
     (mt b
       ((j/jint ib) (= ia ib))
       ((j/jfloat fb) (= (int64ToFloat64 ia) fb))
       ((j/jnum nb) (= (int64ToFloat64 ia) nb))
       (_ false)))
    ((j/jfloat fa)
     (mt b
       ((j/jfloat fb) (= fa fb))
       ((j/jint ib) (= fa (int64ToFloat64 ib)))
       ((j/jnum nb) (= fa nb))
       (_ false)))
    ((j/jnum na)
     (mt b
       ((j/jnum nb) (= na nb))
       ((j/jint ib) (= na (int64ToFloat64 ib)))
       ((j/jfloat fb) (= na fb))
       (_ false)))
    ((j/jstr sa) (mt b ((j/jstr sb) (= sa sb)) (_ false)))
    ((j/jarr xa)
     (mt b
       ((j/jarr xb)
        (if (!= (listLength xa) (listLength xb))
          false
          (fold (fn [(acc Bool) (p (Pair j/Json j/Json))] -> Bool
                  (and acc (jsonEqual? (pairFirst p) (pairSecond p))))
                true (zip xa xb))))
       (_ false)))
    ((j/jobj ka)
     (mt b
       ((j/jobj kb)
        (if (!= (listLength ka) (listLength kb))
          false
          (fold (fn [(acc Bool) (p (Pair String j/Json))] -> Bool
                  (and acc
                       (mt (findKey kb (pairFirst p))
                         ((none) false)
                         ((some v) (jsonEqual? (pairSecond p) v)))))
                true ka)))
       (_ false))))

fn makeIndent n: Int64 -> String
  (if (<= n 0)
    ""
    (stringRepeat " " n))

fn prettyJson val: j/Json indent: Int64 -> String
  (mt val
    ((j/jnull) "null")
    ((j/jbool b) (if b "true" "false"))
    ((j/jint i) (stringFromInt64 i))
    ((j/jfloat f) (stringFromFloat64 f))
    ((j/jnum n) (stringFromFloat64 n))
    ((j/jstr s) (j/jsonEmit (j/jstr s)))
    ((j/jarr xs)
     (if (listEmpty? xs)
       "[]"
       (let [(pad (makeIndent (+ indent 2)))
             (closePad (makeIndent indent))
             (items (map (fn [(x j/Json)] -> String (str pad (prettyJson x (+ indent 2)))) xs))]
         (str "[\n" (stringJoin items ",\n") "\n" closePad "]"))))
    ((j/jobj kvs)
     (if (listEmpty? kvs)
       "{}"
       (let [(pad (makeIndent (+ indent 2)))
             (closePad (makeIndent indent))
             (pairs (map (fn [(p (Pair String j/Json))] -> String
                           (str pad (j/jsonEmit (j/jstr (pairFirst p))) ": " (prettyJson (pairSecond p) (+ indent 2))))
                         kvs))]
         (str "{\n" (stringJoin pairs ",\n") "\n" closePad "}")))))

fn cleanDoc doc: String -> String
  (let [(len (stringLength doc))]
    (if (and (>= len 2) (and (stringStartsWith? doc "\"") (stringEndsWith? doc "\"")))
      (optionOr (stringSlice doc 1 (- len 1)) "")
      doc))

fn isAstType? name: String -> Bool
  (or (= name "Param")
  (or (= name "AstField")
  (or (= name "EnumCase")
  (or (= name "ModuleNode")
  (or (= name "SchemaNode")
  (or (= name "EnumNode")
  (or (= name "DefunNode")
  (or (= name "AstMatchArm")
  (or (= name "TopForm")
  (or (= name "PosForm")
  (or (= name "AstLit")
  (or (= name "AstPattern")
  (or (= name "AstExpr")
      (= name "AstType"))))))))))))))

fn isAuxiliaryType? name: String -> Bool
  (or (= name "ImportEntry")
  (or (= name "LetBinding")
  (or (= name "FieldPattern")
  (or (= name "FieldExpr")
  (or (= name "CondClause")
      (= name "FieldType"))))))

fn nullableTypeName schema: j/Json -> (Option String)
  (mt schema
    ((j/jobj kvs)
     (if (= (listLength kvs) 1) (getString schema "type") (none)))
    (_ (none)))

fn typeToSchema schemaName: String fieldName: String t: String -> (Result j/Json String)
  (cond
    ((= t "String") (ok (j/jobj (list (pair "type" (j/jstr "string"))))))
    ((= t "Bool") (ok (j/jobj (list (pair "type" (j/jstr "boolean"))))))
    ((= t "Int64") (ok (j/jobj (list (pair "type" (j/jstr "integer"))))))
    ((= t "Float64") (ok (j/jobj (list (pair "type" (j/jstr "number"))))))
    ((and (stringStartsWith? t "(Map String ") (stringEndsWith? t ")"))
     (let [(valueT (optionOr (stringSlice t 12 (- (stringLength t) 1)) ""))]
       (mt (typeToSchema schemaName fieldName valueT)
         ((err e) (err e))
         ((ok valueSchema)
          (ok (j/jobj (list (pair "type" (j/jstr "object"))
                            (pair "additionalProperties" valueSchema))))))))
    ((and (stringStartsWith? t "(Option ") (stringEndsWith? t ")"))
     (let [(innerT (optionOr (stringSlice t 8 (- (stringLength t) 1)) ""))]
       (mt (typeToSchema schemaName fieldName innerT)
         ((err e) (err e))
         ((ok innerSchema)
          (mt (nullableTypeName innerSchema)
            ((some typeStr)
             (ok (j/jobj (list (pair "type" (j/jarr (list (j/jstr typeStr) (j/jstr "null"))))))))
            (_
             (ok (j/jobj (list (pair "anyOf" (j/jarr (list innerSchema (j/jobj (list (pair "type" (j/jstr "null"))))))))))))))))
    ((= t "(List (Pair String String))")
     (ok (j/jobj (list (pair "type" (j/jstr "array"))
                       (pair "items" (j/jobj (list (pair "$ref" (j/jstr "#/$defs/ImportEntry")))))))))
    ((= t "(List (Pair AstPattern AstExpr))")
     (ok (j/jobj (list (pair "type" (j/jstr "array"))
                       (pair "items" (j/jobj (list (pair "$ref" (j/jstr "#/$defs/LetBinding")))))))))
    ((= t "(List (Pair String AstPattern))")
     (ok (j/jobj (list (pair "type" (j/jstr "array"))
                       (pair "items" (j/jobj (list (pair "$ref" (j/jstr "#/$defs/FieldPattern")))))))))
    ((= t "(List (Pair String AstExpr))")
     (ok (j/jobj (list (pair "type" (j/jstr "array"))
                       (pair "items" (j/jobj (list (pair "$ref" (j/jstr "#/$defs/FieldExpr")))))))))
    ((= t "(List (Pair AstExpr (List AstExpr)))")
     (ok (j/jobj (list (pair "type" (j/jstr "array"))
                       (pair "items" (j/jobj (list (pair "$ref" (j/jstr "#/$defs/CondClause")))))))))
    ((= t "(List (Pair String AstType))")
     (ok (j/jobj (list (pair "type" (j/jstr "array"))
                       (pair "items" (j/jobj (list (pair "$ref" (j/jstr "#/$defs/FieldType")))))))))
    ((or (= t "(List rd/SExpr)") (= t "(List AstExpr)"))
     (ok (j/jobj (list (pair "type" (j/jstr "array"))
                       (pair "items" (j/jobj (list (pair "$ref" (j/jstr "#/$defs/AstExpr")))))))))
    ((and (stringStartsWith? t "(List ") (stringEndsWith? t ")"))
     (let [(innerT (optionOr (stringSlice t 6 (- (stringLength t) 1)) ""))]
       (mt (typeToSchema schemaName fieldName innerT)
         ((err e) (err e))
         ((ok itemSchema)
          (ok (j/jobj (list (pair "type" (j/jstr "array"))
                            (pair "items" itemSchema))))))))
    ((= t "rd/SExpr")
     (ok (j/jobj (list (pair "$ref" (j/jstr "#/$defs/AstExpr"))))))
    ((or (isAstType? t) (isAuxiliaryType? t))
     (ok (j/jobj (list (pair "$ref" (j/jstr (str "#/$defs/" t)))))))
    (else
     (err (str "unmapped type " t " in " schemaName "." fieldName))))

fn fieldToProp schemaName: String f: a/AstField -> (Result (Pair String j/Json) String)
  (mt (typeToSchema schemaName f.name f.type)
    ((err e) (err e))
    ((ok baseSchema)
     (let [(doc (cleanDoc f.docstring))
           (withDoc (if (stringEmpty? doc)
                      baseSchema
                      (mt baseSchema
                        ((j/jobj kvs) (j/jobj (listAppend kvs (list (pair "description" (j/jstr doc))))))
                        (_ baseSchema))))]
       (ok (pair f.name withDoc)))))

fn fieldsToProps schemaName: String fields: (List a/AstField) -> (Result (List (Pair String j/Json)) String)
  (fold (fn [(acc (Result (List (Pair String j/Json)) String)) (f a/AstField)] -> (Result (List (Pair String j/Json)) String)
          (mt acc
            ((err e) (err e))
            ((ok ps)
             (mt (fieldToProp schemaName f)
               ((err e) (err e))
               ((ok p) (ok (listAppend ps (list p))))))))
        (ok (list)) fields)

fn paramToProp schemaName: String p: a/Param -> (Result (Pair String j/Json) String)
  (mt (typeToSchema schemaName p.name p.type)
    ((err e) (err e))
    ((ok baseSchema)
     (ok (pair p.name baseSchema))))

fn paramsToProps schemaName: String params: (List a/Param) -> (Result (List (Pair String j/Json)) String)
  (fold (fn [(acc (Result (List (Pair String j/Json)) String)) (p a/Param)] -> (Result (List (Pair String j/Json)) String)
          (mt acc
            ((err e) (err e))
            ((ok ps)
             (mt (paramToProp schemaName p)
               ((err e) (err e))
               ((ok prop) (ok (listAppend ps (list prop))))))))
        (ok (list)) params)

fn isInternalField? name: String -> Bool
  (or (= name "bodyPos") (= name "rawParams"))

fn schemaToDef s: a/SchemaNode -> (Result (Pair String j/Json) String)
  (let [(validFields (filter (fn [(f a/AstField)] -> Bool (not (isInternalField? f.name))) s.fields))
        (reqNames (map (fn [(f a/AstField)] -> j/Json (j/jstr f.name)) validFields))]
    (mt (fieldsToProps s.name validFields)
      ((err e) (err e))
      ((ok propPairs)
       (ok (pair s.name
                 (j/jobj (list (pair "type" (j/jstr "object"))
                               (pair "properties" (j/jobj propPairs))
                               (pair "required" (j/jarr reqNames))
                               (pair "additionalProperties" (j/jbool false)))))))))

fn enumCaseToArm enumName: String c: a/EnumCase -> (Result j/Json String)
  (let [(validParams (filter (fn [(p a/Param)] -> Bool (not (isInternalField? p.name))) c.fields))
        (kindProp (pair "kind" (j/jobj (list (pair "type" (j/jstr "string"))
                                             (pair "enum" (j/jarr (list (j/jstr c.name))))))))
        (reqNames (cons (j/jstr "kind") (map (fn [(p a/Param)] -> j/Json (j/jstr p.name)) validParams)))]
    (mt (paramsToProps enumName validParams)
      ((err e) (err e))
      ((ok otherProps)
       (let [(allProps (cons kindProp otherProps))]
         (ok (j/jobj (list (pair "type" (j/jstr "object"))
                           (pair "properties" (j/jobj allProps))
                           (pair "required" (j/jarr reqNames))
                           (pair "additionalProperties" (j/jbool false)))))))))

fn enumToDef e: a/EnumNode -> (Result (Pair String j/Json) String)
  (let [(eName e.name)]
    (fold (fn [(acc (Result (Pair String j/Json) String)) (c a/EnumCase)] -> (Result (Pair String j/Json) String)
            (mt acc
              ((err errStr) (err errStr))
              ((ok p)
               (let [(n (pairFirst p))
                     (v (pairSecond p))]
                 (mt v
                   ((j/jobj kvs)
                    (mt (enumCaseToArm eName c)
                      ((err errStr) (err errStr))
                      ((ok arm)
                       (let [(arms (mt (findKey kvs "anyOf")
                                     ((some v2)
                                      (mt v2
                                        ((j/jarr xs) xs)
                                        (_ (list))))
                                     (_ (list))))]
                         (ok (pair n (j/jobj (list (pair "anyOf" (j/jarr (listAppend arms (list arm))))))))))))
                   (_ (err "Invalid enum accumulator")))))))
          (ok (pair eName (j/jobj (list (pair "anyOf" (j/jarr (list)))))))
          e.cases))

fn auxiliaryDefs -> (List (Pair String j/Json))
  (list
    (pair "ImportEntry"
          (j/jobj (list (pair "type" (j/jstr "object"))
                        (pair "properties" (j/jobj (list (pair "path" (j/jobj (list (pair "type" (j/jstr "string")) (pair "description" (j/jstr "Imported module path")))))
                                                         (pair "alias" (j/jobj (list (pair "type" (j/jstr "string")) (pair "description" (j/jstr "Local alias for module"))))))))
                        (pair "required" (j/jarr (list (j/jstr "path") (j/jstr "alias"))))
                        (pair "additionalProperties" (j/jbool false)))))
    (pair "LetBinding"
          (j/jobj (list (pair "type" (j/jstr "object"))
                        (pair "properties" (j/jobj (list (pair "pat" (j/jobj (list (pair "$ref" (j/jstr "#/$defs/AstPattern")))))
                                                         (pair "val" (j/jobj (list (pair "$ref" (j/jstr "#/$defs/AstExpr"))))))))
                        (pair "required" (j/jarr (list (j/jstr "pat") (j/jstr "val"))))
                        (pair "additionalProperties" (j/jbool false)))))
    (pair "FieldPattern"
          (j/jobj (list (pair "type" (j/jstr "object"))
                        (pair "properties" (j/jobj (list (pair "name" (j/jobj (list (pair "type" (j/jstr "string")) (pair "description" (j/jstr "Record field pattern name")))))
                                                         (pair "pat" (j/jobj (list (pair "$ref" (j/jstr "#/$defs/AstPattern"))))))))
                        (pair "required" (j/jarr (list (j/jstr "name") (j/jstr "pat"))))
                        (pair "additionalProperties" (j/jbool false)))))
    (pair "FieldExpr"
          (j/jobj (list (pair "type" (j/jstr "object"))
                        (pair "properties" (j/jobj (list (pair "name" (j/jobj (list (pair "type" (j/jstr "string")) (pair "description" (j/jstr "Record field name")))))
                                                         (pair "val" (j/jobj (list (pair "$ref" (j/jstr "#/$defs/AstExpr"))))))))
                        (pair "required" (j/jarr (list (j/jstr "name") (j/jstr "val"))))
                        (pair "additionalProperties" (j/jbool false)))))
    (pair "CondClause"
          (j/jobj (list (pair "type" (j/jstr "object"))
                        (pair "properties" (j/jobj (list (pair "test" (j/jobj (list (pair "$ref" (j/jstr "#/$defs/AstExpr")))))
                                                         (pair "body" (j/jobj (list (pair "type" (j/jstr "array"))
                                                                                    (pair "items" (j/jobj (list (pair "$ref" (j/jstr "#/$defs/AstExpr")))))))))))
                        (pair "required" (j/jarr (list (j/jstr "test") (j/jstr "body"))))
                        (pair "additionalProperties" (j/jbool false)))))
    (pair "FieldType"
          (j/jobj (list (pair "type" (j/jstr "object"))
                        (pair "properties" (j/jobj (list (pair "name" (j/jobj (list (pair "type" (j/jstr "string")) (pair "description" (j/jstr "Record field type name")))))
                                                         (pair "type" (j/jobj (list (pair "$ref" (j/jstr "#/$defs/AstType"))))))))
                        (pair "required" (j/jarr (list (j/jstr "name") (j/jstr "type"))))
                        (pair "additionalProperties" (j/jbool false))))))

fn buildSchemaJson forms: (List a/TopForm) -> (Result j/Json String)
  (let [(defsRes (fold (fn [(acc (Result (List (Pair String j/Json)) String)) (tf a/TopForm)] -> (Result (List (Pair String j/Json)) String)
                         (mt acc
                           ((err e) (err e))
                           ((ok curDefs)
                            (mt tf
                              ((a/topSchema s)
                               (if (isAstType? s.name)
                                 (mt (schemaToDef s)
                                   ((err e) (err e))
                                   ((ok def) (ok (listAppend curDefs (list def)))))
                                 (ok curDefs)))
                              ((a/topEnum e)
                               (if (isAstType? e.name)
                                 (mt (enumToDef e)
                                   ((err e) (err e))
                                   ((ok def) (ok (listAppend curDefs (list def)))))
                                 (ok curDefs)))
                              (_ (ok curDefs))))))
                       (ok (list)) forms))]
    (mt defsRes
      ((err e) (err e))
      ((ok astSchemas)
       (let [(allDefs (listAppend (auxiliaryDefs) astSchemas))
             (root (j/jobj (list (pair "$schema" (j/jstr "https://json-schema.org/draft/2020-12/schema"))
                                 (pair "title" (j/jstr "AslAst"))
                                 (pair "description" (j/jstr "JSON schema of the ASL AST for provider structured output (agy --json-schema)"))
                                 (pair "$defs" (j/jobj allDefs))
                                 (pair "anyOf" (j/jarr (list (j/jobj (list (pair "$ref" (j/jstr "#/$defs/TopForm"))))
                                                             (j/jobj (list (pair "$ref" (j/jstr "#/$defs/ModuleNode"))))
                                                             (j/jobj (list (pair "$ref" (j/jstr "#/$defs/AstExpr"))))))))))]
         (ok root)))))

fn generateAstSchema forms: (List a/TopForm) -> (Result String String)
  (mt (buildSchemaJson forms)
    ((err e) (err e))
    ((ok j) (ok (str (prettyJson j 0) "\n"))))

fn generateAstSchemaFromAstFile! path: String -> (Result String String)
  (mt (fileRead path)
    ((err e) (err (str "Could not read " path ": " e)))
    ((ok src)
     (mt (a/parse src)
       ((err e) (err (str "Parse error in " path ": " e.msg)))
       ((ok forms) (generateAstSchema forms)))))

fn validateItems itemSchema: (Option j/Json) rootSchema: j/Json instance: j/Json -> (Result Bool String)
  (mt itemSchema
    ((none) (ok true))
    ((some is)
     (mt instance
       ((j/jarr xs)
        (fold (fn [(acc (Result Bool String)) (x j/Json)] -> (Result Bool String)
                (mt acc
                  ((err e) (err e))
                  ((ok _) (validateJsonSchema is rootSchema x))))
              (ok true) xs))
       (_ (err "Expected array for items check")))))

fn validateProperties propOpt: (Option (List (Pair String j/Json))) schema: j/Json rootSchema: j/Json instance: j/Json -> (Result Bool String)
  (mt propOpt
    ((none) (validateItems (getProp schema "items") rootSchema instance))
    ((some propKvs)
     (mt instance
       ((j/jobj instKvs)
        (let [(propErr (fold (fn [(acc (Option String)) (p (Pair String j/Json))] -> (Option String)
                               (mt acc
                                 ((some _) acc)
                                 ((none)
                                  (mt (findKey instKvs (pairFirst p))
                                    ((some instVal)
                                     (mt (validateJsonSchema (pairSecond p) rootSchema instVal)
                                       ((ok _) (none))
                                       ((err e) (some (str "Property " (pairFirst p) ": " e)))))
                                    ((none) (none))))))
                             (none) propKvs))]
          (mt propErr
            ((some pe) (err pe))
            ((none)
             (let [(allowAdditional (mt (getProp schema "additionalProperties")
                                      ((some apVal) (mt apVal ((j/jbool b) b) (_ true)))
                                      (_ true)))]
               (if allowAdditional
                 (validateItems (getProp schema "items") rootSchema instance)
                 (let [(extraKey (fold (fn [(acc (Option String)) (p (Pair String j/Json))] -> (Option String)
                                         (mt acc
                                           ((some _) acc)
                                           ((none)
                                            (if (none? (findKey propKvs (pairFirst p)))
                                              (some (pairFirst p))
                                              (none)))))
                                       (none) instKvs))]
                   (mt extraKey
                     ((some ek) (err (str "Additional property not allowed: " ek)))
                     ((none) (validateItems (getProp schema "items") rootSchema instance))))))))))
       (_ (err "Expected object for properties check")))))

fn validateRequired reqOpt: (Option (List j/Json)) schema: j/Json rootSchema: j/Json instance: j/Json -> (Result Bool String)
  (mt reqOpt
    ((none) (validateProperties (getObject schema "properties") schema rootSchema instance))
    ((some reqs)
     (mt instance
       ((j/jobj kvs)
        (let [(missing (fold (fn [(acc (Option String)) (r j/Json)] -> (Option String)
                               (mt acc
                                 ((some _) acc)
                                 ((none)
                                  (mt r
                                    ((j/jstr rKey)
                                     (if (none? (findKey kvs rKey)) (some rKey) (none)))
                                    (_ (none))))))
                             (none) reqs))]
          (mt missing
            ((some k) (err (str "Missing required property: " k)))
            ((none) (validateProperties (getObject schema "properties") schema rootSchema instance)))))
       (_ (err "Expected object for required properties")))))

fn validateType typeOpt: (Option j/Json) schema: j/Json rootSchema: j/Json instance: j/Json -> (Result Bool String)
  (mt typeOpt
    ((none) (validateRequired (getArray schema "required") schema rootSchema instance))
    ((some typeVal)
     (let [(typeMatch? (fn [(t String)] -> Bool
                         (cond
                           ((= t "string") (mt instance ((j/jstr _) true) (_ false)))
                           ((= t "boolean") (mt instance ((j/jbool _) true) (_ false)))
                           ((= t "integer") (mt instance ((j/jint _) true) (_ false)))
                           ((= t "number") (mt instance ((j/jint _) true) ((j/jfloat _) true) ((j/jnum _) true) (_ false)))
                           ((= t "array") (mt instance ((j/jarr _) true) (_ false)))
                           ((= t "object") (mt instance ((j/jobj _) true) (_ false)))
                           ((= t "null") (mt instance ((j/jnull) true) (_ false)))
                           (else false))))
           (okType (mt typeVal
                     ((j/jstr t) (typeMatch? t))
                     ((j/jarr ts)
                      (fold (fn [(acc Bool) (tv j/Json)] -> Bool
                              (or acc (mt tv ((j/jstr t) (typeMatch? t)) (_ false))))
                            false ts))
                     (_ false)))]
       (if (not okType)
         (err "Instance type does not match schema type")
         (validateRequired (getArray schema "required") schema rootSchema instance)))))

fn validateEnum enumOpt: (Option (List j/Json)) schema: j/Json rootSchema: j/Json instance: j/Json -> (Result Bool String)
  (mt enumOpt
    ((none) (validateType (getProp schema "type") schema rootSchema instance))
    ((some vals)
     (let [(inEnum (fold (fn [(acc Bool) (ev j/Json)] -> Bool
                           (or acc (jsonEqual? instance ev)))
                         false vals))]
       (if inEnum
         (validateType (getProp schema "type") schema rootSchema instance)
         (err "Instance not in enum")))))

fn validateOneOf oneOfOpt: (Option (List j/Json)) schema: j/Json rootSchema: j/Json instance: j/Json -> (Result Bool String)
  (mt oneOfOpt
    ((none) (validateEnum (getArray schema "enum") schema rootSchema instance))
    ((some arms)
     (let [(matchCount (fold (fn [(acc Int64) (arm j/Json)] -> Int64
                               (mt (validateJsonSchema arm rootSchema instance)
                                 ((ok b) (if b (+ acc 1) acc))
                                 ((err _) acc)))
                             0 arms))]
       (if (= matchCount 1)
         (validateEnum (getArray schema "enum") schema rootSchema instance)
         (err (str "Instance must match exactly one oneOf schema, matched " (stringFromInt64 matchCount)))))))

fn validateAnyOf anyOfOpt: (Option (List j/Json)) schema: j/Json rootSchema: j/Json instance: j/Json -> (Result Bool String)
  (mt anyOfOpt
    ((none) (validateOneOf (getArray schema "oneOf") schema rootSchema instance))
    ((some arms)
     (let [(anyOk (fold (fn [(acc Bool) (arm j/Json)] -> Bool
                          (or acc (mt (validateJsonSchema arm rootSchema instance)
                                    ((ok b) b)
                                    ((err _) false))))
                        false arms))]
       (if anyOk
         (validateOneOf (getArray schema "oneOf") schema rootSchema instance)
         (err "Instance does not match any schema in anyOf")))))

fn validateJsonSchema schema: j/Json rootSchema: j/Json instance: j/Json -> (Result Bool String)
  (mt (getString schema "$ref")
    ((some refStr)
     (if (stringStartsWith? refStr "#/$defs/")
       (let [(defName (optionOr (stringSlice refStr 8 (stringLength refStr)) ""))
             (defsOpt (getProp rootSchema "$defs"))]
         (mt defsOpt
           ((some defs)
            (mt (getProp defs defName)
              ((some targetSchema) (validateJsonSchema targetSchema rootSchema instance))
              ((none) (err (str "Unresolved $ref def: " defName)))))
           ((none) (err "Root schema missing $defs"))))
       (err (str "Unsupported $ref: " refStr))))
    ((none)
     (validateAnyOf (getArray schema "anyOf") schema rootSchema instance)))

fn validateTopFormWithSchema rootSchema: j/Json instance: j/Json -> (Result Bool String)
  (let [(topSchema (j/jobj (list (pair "$ref" (j/jstr "#/$defs/TopForm")))))]
    (validateJsonSchema topSchema rootSchema instance))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(inPath (optionOr (listGet args 0) "asl/packages/asl-parser/src/ast.asl"))
        (outPath (optionOr (listGet args 1) "asl/grammar/aslAst.schema.json"))]
    (mt (generateAstSchemaFromAstFile! inPath)
      ((err e)
       (do
         (print (str "Schema generation failed: " e "\n"))
         (err e)))
      ((ok schemaStr)
       (mt (fileWrite outPath schemaStr)
         ((err e)
          (do
            (print (str "Failed writing " outPath ": " e "\n"))
            (err e)))
         ((ok _)
          (do
            (print (str "Successfully generated " outPath " from " inPath "\n"))
            (ok 0)))))))
