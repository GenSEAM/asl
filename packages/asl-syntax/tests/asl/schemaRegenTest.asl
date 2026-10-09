(module asl-syntax/tests/asl/schemaRegenTest
  :x [runTests]
  :i [(asl-syntax/asl/astSchema :a s)
      (asl-parser/ast :a a)
      (asl-json/json :a j)])

fn collectRefs val: j/Json -> (List String)
  (mt val
    ((j/jobj kvs)
     (let [(directRef (mt (s/findKey kvs "$ref")
                        ((some v)
                         (mt v
                           ((j/jstr r) (list r))
                           (_ (list))))
                        (_ (list))))
           (childRefs (fold (fn [(acc (List String)) (p (Pair String j/Json))] -> (List String)
                              (listAppend acc (collectRefs (pairSecond p))))
                            (list) kvs))]
       (listAppend directRef childRefs)))
    ((j/jarr xs)
     (fold (fn [(acc (List String)) (x j/Json)] -> (List String)
             (listAppend acc (collectRefs x)))
           (list) xs))
    (_ (list)))

fn unresolvedRefs schema: j/Json -> (List String)
  (let [(defsKvs (mt (s/getObject schema "$defs") ((some kvs) kvs) ((none) (list))))
        (defsKeys (map (fn [(p (Pair String j/Json))] -> String (pairFirst p)) defsKvs))]
    (filter (fn [(r String)] -> Bool
              (not (and (stringStartsWith? r "#/$defs/")
                        (listContains? defsKeys (optionOr (stringSlice r 8 (stringLength r)) "")))))
            (collectRefs schema)))

fn loadCommittedSchema! -> (Result j/Json String)
  (mt (fileRead "asl/grammar/aslAst.schema.json")
    ((err e) (err (str "read asl/grammar/aslAst.schema.json: " e)))
    ((ok text)
     (mt (j/jsonParse text)
       ((err e) (err (str "parse asl/grammar/aslAst.schema.json: " e)))
       ((ok root) (ok root)))))

fn loadAstForms! -> (Result (List a/TopForm) String)
  (mt (fileRead "asl/packages/asl-parser/src/ast.asl")
    ((err e) (err (str "read asl/packages/asl-parser/src/ast.asl: " e)))
    ((ok src)
     (mt (a/parse src)
       ((err e) (err (str "parse asl/packages/asl-parser/src/ast.asl: " e.msg)))
       ((ok forms) (ok forms)))))

fn addParamField forms: (List a/TopForm) field: a/AstField -> (List a/TopForm)
  (map (fn [(tf a/TopForm)] -> a/TopForm
         (mt tf
           ((a/topSchema sn)
            (if (= sn.name "Param")
              (a/topSchema (a/SchemaNode :name sn.name :typeVars sn.typeVars :fields (cons field sn.fields) :jsonCase sn.jsonCase))
              tf))
           (_ tf)))
       forms)

fn addAstLitCase forms: (List a/TopForm) extraCase: a/EnumCase -> (List a/TopForm)
  (map (fn [(tf a/TopForm)] -> a/TopForm
         (mt tf
           ((a/topEnum en)
            (if (= en.name "AstLit")
              (a/topEnum (a/EnumNode :name en.name :typeVars en.typeVars :cases (cons extraCase en.cases)))
              tf))
           (_ tf)))
       forms)

fn testSchemaDrift! -> Bool
  (mt (fileRead "asl/grammar/aslAst.schema.json")
    ((err e)
     (do
       (assert false (str "Failed reading committed schema: " e))
       false))
    ((ok committedStr)
     (mt (s/generateAstSchemaFromAstFile! "asl/packages/asl-parser/src/ast.asl")
       ((err e)
        (do
          (assert false (str "Failed generating schema: " e))
          false))
       ((ok generatedStr)
        (let [(matches (= committedStr generatedStr))]
          (do
            (assert matches "regenerated schema matches committed aslAst.schema.json byte-for-byte")
            matches))))))

fn testAstTypeMutationChangesSchema! -> Bool
  (mt (loadAstForms!)
    ((err e)
     (do
       (assert false (str "changing AST type must change generated schema: " e))
       false))
    ((ok origForms)
     (let [(mutatedForms (addAstLitCase
                           (addParamField origForms (a/AstField :name "testMutantField" :type "String" :docstring "\"extra field for mutation test\"" :default (none) :json (none)))
                           (a/EnumCase :name "litMutantExtra" :fields (list (a/Param :name "extraVal" :type "String")) :docstring "\"mutant case\"")))]
       (mt (s/generateAstSchema origForms)
         ((err e)
          (do
            (assert false (str "original schema generation failed: " e))
            false))
         ((ok origSchema)
          (mt (s/generateAstSchema mutatedForms)
            ((err e)
             (do
               (assert false (str "mutated schema generation failed: " e))
               false))
            ((ok mutatedSchema)
             (let [(changed (!= origSchema mutatedSchema))
                   (hasField (stringContains? mutatedSchema "testMutantField"))
                   (hasCase (stringContains? mutatedSchema "litMutantExtra"))]
               (do
                 (assert changed "changing AST type must change generated schema")
                 (assert hasField "mutated schema contains added field")
                 (assert hasCase "mutated schema contains added enum case")
                 (and changed (and hasField hasCase)))))))))))

fn testRefCheckerFlagsDangling -> Bool
  (let [(seeded (j/jobj (list (pair "$defs" (j/jobj (list (pair "A" (j/jobj (list (pair "$ref" (j/jstr "#/$defs/B"))))))))
                              (pair "anyOf" (j/jarr (list (j/jobj (list (pair "$ref" (j/jstr "#/$defs/A"))))
                                                          (j/jobj (list (pair "$ref" (j/jstr "https://example.org/x"))))))))))
        (dangling (unresolvedRefs seeded))
        (flagged (= dangling (list "#/$defs/B" "https://example.org/x")))]
    (do
      (assert flagged (str "ref checker flags exactly the seeded dangling refs, got: " (stringJoin dangling ", ")))
      flagged))

fn testCommittedSchemaRefsResolve! -> Bool
  (mt (loadCommittedSchema!)
    ((err e)
     (do
       (assert false (str "every $ref in committed schema resolves: " e))
       false))
    ((ok schema)
     (let [(refCount (listLength (collectRefs schema)))
           (dangling (unresolvedRefs schema))]
       (do
         (assert (> refCount 0) (str "committed schema carries $ref entries, found " (stringFromInt64 refCount)))
         (assert (listEmpty? dangling) (str "every $ref in committed schema resolves to a $defs key, dangling: " (stringJoin dangling ", ")))
         (and (> refCount 0) (listEmpty? dangling))))))

fn generationError res: (Result String String) -> String
  (mt res
    ((err msg) msg)
    (_ "no error"))

fn testUnmappedTypeFails! -> Bool
  (mt (loadAstForms!)
    ((err e)
     (do
       (assert false (str "unmapped type yields exact error: " e))
       false))
    ((ok forms)
     (let [(fieldMsg (generationError (s/generateAstSchema (addParamField forms (a/AstField :name "arity" :type "(Option FooBar)" :docstring "\"\"" :default (none) :json (none))))))
           (caseMsg (generationError (s/generateAstSchema (addAstLitCase forms (a/EnumCase :name "litSpan" :fields (list (a/Param :name "span" :type "(List (Pair Int64 Int64))")) :docstring "\"\"")))))
           (fieldOk (= fieldMsg "unmapped type FooBar in Param.arity"))
           (caseOk (= caseMsg "unmapped type (Pair Int64 Int64) in AstLit.span"))]
       (do
         (assert fieldOk (str "schema field with unmapped type yields exact err, got: " fieldMsg))
         (assert caseOk (str "enum case param with unmapped type yields exact err, got: " caseMsg))
         (and fieldOk caseOk)))))

fn testOptionInt64Maps! -> Bool
  (mt (loadAstForms!)
    ((err e)
     (do
       (assert false (str "Option Int64 maps to nullable integer: " e))
       false))
    ((ok forms)
     (mt (s/generateAstSchema (addParamField forms (a/AstField :name "arity" :type "(Option Int64)" :docstring "\"\"" :default (none) :json (none))))
       ((err e)
        (do
          (assert false (str "Option Int64 schema generation failed: " e))
          false))
       ((ok text)
        (mt (j/jsonParse text)
          ((err e)
           (do
             (assert false (str "Option Int64 schema parse failed: " e))
             false))
          ((ok schema)
           (let [(dangling (unresolvedRefs schema))
                 (arity (mt (s/getProp schema "$defs")
                          ((some defs) (mt (s/getProp defs "Param")
                                         ((some param) (mt (s/getProp param "properties")
                                                         ((some props) (s/getProp props "arity"))
                                                         ((none) (none))))
                                         ((none) (none))))
                          ((none) (none))))
                 (expected (j/jobj (list (pair "type" (j/jarr (list (j/jstr "integer") (j/jstr "null")))))))
                 (mapped (mt arity ((some v) (s/jsonEqual? v expected)) ((none) false)))]
             (do
               (assert (listEmpty? dangling) (str "schema with Option Int64 has no dangling refs, dangling: " (stringJoin dangling ", ")))
               (assert mapped "Param.arity of type (Option Int64) is {\"type\": [\"integer\", \"null\"]}")
               (and (listEmpty? dangling) mapped)))))))))

fn testValidatorKeywordsAndNegatives -> Bool
  (let [(root (j/jobj (list (pair "$defs"
                                  (j/jobj (list (pair "Person"
                                                      (j/jobj (list (pair "type" (j/jstr "object"))
                                                                    (pair "properties" (j/jobj (list (pair "name" (j/jobj (list (pair "type" (j/jstr "string")))))
                                                                                                     (pair "age" (j/jobj (list (pair "type" (j/jstr "integer"))))))))
                                                                    (pair "required" (j/jarr (list (j/jstr "name") (j/jstr "age"))))
                                                                    (pair "additionalProperties" (j/jbool false)))))))))))
        (typeSchema (j/jobj (list (pair "type" (j/jstr "string")))))
        (typePos (j/jstr "valid string"))
        (typeNeg (j/jint 42))
        (propSchema (j/jobj (list (pair "type" (j/jstr "object"))
                                  (pair "properties" (j/jobj (list (pair "count" (j/jobj (list (pair "type" (j/jstr "integer"))))))))
                                  (pair "additionalProperties" (j/jbool false)))))
        (propPos (j/jobj (list (pair "count" (j/jint 10)))))
        (propNegType (j/jobj (list (pair "count" (j/jstr "not an int")))))
        (propNegAdditional (j/jobj (list (pair "count" (j/jint 10)) (pair "unknown" (j/jbool true)))))
        (reqSchema (j/jobj (list (pair "type" (j/jstr "object"))
                                 (pair "required" (j/jarr (list (j/jstr "keyA") (j/jstr "keyB")))))))
        (reqPos (j/jobj (list (pair "keyA" (j/jint 1)) (pair "keyB" (j/jint 2)))))
        (reqNeg (j/jobj (list (pair "keyA" (j/jint 1)))))
        (itemsSchema (j/jobj (list (pair "type" (j/jstr "array"))
                                   (pair "items" (j/jobj (list (pair "type" (j/jstr "string"))))))))
        (itemsPos (j/jarr (list (j/jstr "a") (j/jstr "b"))))
        (itemsNeg (j/jarr (list (j/jstr "a") (j/jint 99))))
        (enumSchema (j/jobj (list (pair "enum" (j/jarr (list (j/jstr "red") (j/jstr "green") (j/jstr "blue")))))))
        (enumPos (j/jstr "green"))
        (enumNeg (j/jstr "yellow"))
        (anyOfSchema (j/jobj (list (pair "anyOf" (j/jarr (list (j/jobj (list (pair "type" (j/jstr "string"))))
                                                              (j/jobj (list (pair "type" (j/jstr "integer"))))))))))
        (anyOfPos (j/jint 123))
        (anyOfNeg (j/jbool true))
        (oneOfSchema (j/jobj (list (pair "oneOf" (j/jarr (list (j/jobj (list (pair "type" (j/jstr "integer"))))
                                                              (j/jobj (list (pair "type" (j/jstr "number"))))))))))
        (oneOfPos (j/jfloat 3.14))
        (oneOfNegBoth (j/jint 42))
        (oneOfNegNeither (j/jstr "hello"))
        (refSchema (j/jobj (list (pair "$ref" (j/jstr "#/$defs/Person")))))
        (refPos (j/jobj (list (pair "name" (j/jstr "Alice")) (pair "age" (j/jint 30)))))
        (refNegMissing (j/jobj (list (pair "name" (j/jstr "Alice")))))
        (refNegType (j/jobj (list (pair "name" (j/jstr "Alice")) (pair "age" (j/jstr "thirty")))))]
    (do
      (assert (ok? (s/validateJsonSchema typeSchema root typePos)) "type keyword validates valid type")
      (assert (err? (s/validateJsonSchema typeSchema root typeNeg)) "type keyword refutes invalid type negative case")
      (assert (ok? (s/validateJsonSchema propSchema root propPos)) "properties keyword validates valid properties")
      (assert (err? (s/validateJsonSchema propSchema root propNegType)) "properties keyword refutes wrong property type negative case")
      (assert (err? (s/validateJsonSchema propSchema root propNegAdditional)) "properties keyword refutes additional properties negative case")
      (assert (ok? (s/validateJsonSchema reqSchema root reqPos)) "required keyword validates present properties")
      (assert (err? (s/validateJsonSchema reqSchema root reqNeg)) "required keyword refutes missing property negative case")
      (assert (ok? (s/validateJsonSchema itemsSchema root itemsPos)) "items keyword validates valid array items")
      (assert (err? (s/validateJsonSchema itemsSchema root itemsNeg)) "items keyword refutes invalid item negative case")
      (assert (ok? (s/validateJsonSchema enumSchema root enumPos)) "enum keyword validates member")
      (assert (err? (s/validateJsonSchema enumSchema root enumNeg)) "enum keyword refutes non-member negative case")
      (assert (ok? (s/validateJsonSchema anyOfSchema root anyOfPos)) "anyOf keyword validates matching variant")
      (assert (err? (s/validateJsonSchema anyOfSchema root anyOfNeg)) "anyOf keyword refutes non-matching variant negative case")
      (assert (ok? (s/validateJsonSchema oneOfSchema root oneOfPos)) "oneOf keyword validates single matching variant")
      (assert (err? (s/validateJsonSchema oneOfSchema root oneOfNegBoth)) "oneOf keyword refutes multiple matching variants negative case")
      (assert (err? (s/validateJsonSchema oneOfSchema root oneOfNegNeither)) "oneOf keyword refutes neither matching variant negative case")
      (assert (ok? (s/validateJsonSchema refSchema root refPos)) "$ref keyword validates referenced schema")
      (assert (err? (s/validateJsonSchema refSchema root refNegMissing)) "$ref keyword refutes missing required in referenced schema negative case")
      (assert (err? (s/validateJsonSchema refSchema root refNegType)) "$ref keyword refutes wrong type in referenced schema negative case")
      true))

fn ! runTests -> Bool
  (do
    (assert (testSchemaDrift!) "committed aslAst.schema.json equals regenerated schema")
    (assert (testAstTypeMutationChangesSchema!) "changing AST type changes generated schema")
    (assert (testRefCheckerFlagsDangling) "ref checker flags seeded dangling refs")
    (assert (testCommittedSchemaRefsResolve!) "every $ref in committed schema resolves")
    (assert (testUnmappedTypeFails!) "unmapped types yield the exact err")
    (assert (testOptionInt64Maps!) "Option Int64 maps to a nullable integer")
    (assert (testValidatorKeywordsAndNegatives) "schema validator keywords and negative cases all pass")
    true)
