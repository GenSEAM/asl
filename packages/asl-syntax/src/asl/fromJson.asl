(module asl-syntax/asl/fromJson
  :x [fromJsonToAsl
      fromJsonTopForm
      fromJsonModule
      fromJsonExpr
      fromJsonTopForms
      topFormToJson
      topFormToJsonString
      moduleToJson
      moduleToJsonString
      exprToJson
      exprToJsonString
      topFormsToJson
      topFormsToJsonString
      parseTopForm
      parseModuleNode
      parseSchemaNode
      parseEnumNode
      parseDefunNode
      parseAstExpr
      parseAstLit
      parseAstPattern
      parseAstType
      parseImportEntry
      parseLetBinding
      renderTopForm litToJson]
  :i [(asl-json/json :a j)
      (asl-parser/ast :a a)
      (asl-parser/astConverter :a cv)
      (asl-parser/astPrinter :a ap)
      (asl-parser/reader :a rd)])

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
       ((j/jnum n) (some n))
       ((j/jint i) (stringToFloat64 (stringFromInt64 i)))
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

fn getStringList val: j/Json key: String -> (Option (List String))
  (mt (getArray val key)
    ((none) (none))
    ((some items)
     (let [(strs (fold (fn [(acc (List String)) (item j/Json)] -> (List String)
                         (mt item
                           ((j/jstr s) (listAppend acc (list s)))
                           (_ acc)))
                       (list) items))]
       (some strs))))

fn getKind val: j/Json -> (Option String)
  (getString val "kind")

fn parseParam val: j/Json -> (Result a/Param String)
  (mt (getString val "name")
    ((none) (err "Param missing name"))
    ((some name)
     (mt (getString val "type")
       ((none) (err "Param missing type"))
       ((some typ) (ok (a/Param :name name :type typ))))))

fn paramToJson p: a/Param -> j/Json
  (j/jobj (list (pair "name" (j/jstr p.name))
                (pair "type" (j/jstr p.type))))

fn parseFieldDefault val: j/Json -> (Result (Option rd/SExpr) String)
  (mt (getProp val "default")
    ((none) (ok (none)))
    ((some dv)
     (mt dv
       ((j/jnull) (ok (none)))
       (_ (mt (parseAstExpr dv)
            ((err e) (err e))
            ((ok expr) (ok (some (cv/lower expr)))))))))

fn parseAstField val: j/Json -> (Result a/AstField String)
  (mt (getString val "name")
    ((none) (err "AstField missing name"))
    ((some name)
     (mt (getString val "type")
       ((none) (err "AstField missing type"))
       ((some typ)
        (mt (parseFieldDefault val)
          ((err e) (err e))
          ((ok defVal)
           (let [(doc (optionOr (getString val "docstring") ""))
                 (jsonVal (getString val "json"))]
             (ok (a/AstField :name name :type typ :docstring doc :default defVal :json jsonVal)))))))))

fn fieldToJson f: a/AstField -> j/Json
  (let [(defJson (mt f.default ((some d) (exprToJson (cv/lift d))) ((none) (j/jnull))))
        (jsJson (mt f.json ((some s) (j/jstr s)) ((none) (j/jnull))))]
    (j/jobj (list (pair "name" (j/jstr f.name))
                  (pair "type" (j/jstr f.type))
                  (pair "docstring" (j/jstr f.docstring))
                  (pair "default" defJson)
                  (pair "json" jsJson))))

fn parseEnumCase val: j/Json -> (Result a/EnumCase String)
  (mt (getString val "name")
    ((none) (err "EnumCase missing name"))
    ((some name)
     (let [(doc (optionOr (getString val "docstring") ""))
           (fieldsRaw (optionOr (getArray val "fields") (list)))
           (fieldsRes (fold (fn [(acc (Result (List a/Param) String)) (item j/Json)] -> (Result (List a/Param) String)
                              (mt acc
                                ((err e) (err e))
                                ((ok fs)
                                 (mt (parseParam item)
                                   ((err e) (err e))
                                   ((ok p) (ok (listAppend fs (list p))))))))
                            (ok (list)) fieldsRaw))]
       (mt fieldsRes
         ((err e) (err e))
         ((ok fs) (ok (a/EnumCase :name name :fields fs :docstring doc)))))))

fn enumCaseToJson c: a/EnumCase -> j/Json
  (j/jobj (list (pair "name" (j/jstr c.name))
                (pair "fields" (j/jarr (map paramToJson c.fields)))
                (pair "docstring" (j/jstr c.docstring))))

fn parseImportEntry val: j/Json -> (Result (Pair String String) String)
  (mt val
    ((j/jobj _)
     (mt (getString val "path")
       ((none) (err "ImportEntry missing path"))
       ((some p)
        (mt (getString val "alias")
          ((none) (err "ImportEntry missing alias"))
          ((some al) (ok (pair p al)))))))
    ((j/jarr items)
     (if (>= (listLength items) 2)
       (let [(p0 (listGet items 0)) (p1 (listGet items 1))]
         (mt p0
           ((some p0v)
            (mt p0v
              ((j/jstr path)
               (mt p1
                 ((some p1v)
                  (mt p1v
                    ((j/jstr alias) (ok (pair path alias)))
                    (_ (err "ImportEntry alias must be string"))))
                 (_ (err "ImportEntry alias missing"))))
              (_ (err "ImportEntry path must be string"))))
           (_ (err "ImportEntry path missing"))))
       (err "ImportEntry array too short")))
    (_ (err "ImportEntry must be object or array")))

fn importToJson p: (Pair String String) -> j/Json
  (j/jobj (list (pair "path" (j/jstr (pairFirst p)))
                (pair "alias" (j/jstr (pairSecond p)))))

fn parseAstLit val: j/Json -> (Result a/AstLit String)
  (mt (getKind val)
    ((some k)
     (cond
       ((= k "litInt")
        (mt (getInt val "val")
          ((some i) (ok (a/litInt i)))
          ((none) (err "litInt missing val"))))
       ((= k "litFloat")
        (mt (getFloat val "val")
          ((some f) (ok (a/litFloat f)))
          ((none) (err "litFloat missing val"))))
       ((= k "litString")
        (mt (getString val "val")
          ((some s) (ok (a/litString s)))
          ((none) (err "litString missing val"))))
       ((= k "litBool")
        (mt (getBool val "val")
          ((some b) (ok (a/litBool b)))
          ((none) (err "litBool missing val"))))
       ((= k "litUnit") (ok (a/litUnit)))
       (else (err (str "Unknown lit kind: " k)))))
    ((none)
     (mt val
       ((j/jint i) (ok (a/litInt i)))
       ((j/jfloat f) (ok (a/litFloat f)))
       ((j/jnum n) (ok (a/litFloat n)))
       ((j/jstr s) (ok (a/litString s)))
       ((j/jbool b) (ok (a/litBool b)))
       ((j/jnull) (ok (a/litUnit)))
       (_ (err "Unknown literal json form")))))

fn litToJson lit: a/AstLit -> j/Json
  (mt lit
    ((a/litInt i) (j/jobj (list (pair "kind" (j/jstr "litInt")) (pair "val" (j/jint i)))))
    ((a/litFloat f) (j/jobj (list (pair "kind" (j/jstr "litFloat")) (pair "val" (j/jfloat f)))))
    ((a/litString s) (j/jobj (list (pair "kind" (j/jstr "litString")) (pair "val" (j/jstr s)))))
    ((a/litBool b) (j/jobj (list (pair "kind" (j/jstr "litBool")) (pair "val" (j/jbool b)))))
    ((a/litUnit) (j/jobj (list (pair "kind" (j/jstr "litUnit"))))))

fn parseAstPattern val: j/Json -> (Result a/AstPattern String)
  (mt (getKind val)
    ((some k)
     (cond
       ((= k "patWildcard") (ok (a/patWildcard)))
       ((= k "patVar")
        (mt (getString val "name")
          ((some n) (ok (a/patVar n)))
          ((none) (err "patVar missing name"))))
       ((= k "patLit")
        (mt (getProp val "lit")
          ((some lVal)
           (mt (parseAstLit lVal)
             ((ok lit) (ok (a/patLit lit)))
             ((err e) (err e))))
          ((none) (err "patLit missing lit"))))
       ((= k "patTuple")
        (let [(itemsRaw (optionOr (getArray val "elements") (list)))
              (itemsRes (fold (fn [(acc (Result (List a/AstPattern) String)) (item j/Json)] -> (Result (List a/AstPattern) String)
                                (mt acc
                                  ((err e) (err e))
                                  ((ok ps)
                                   (mt (parseAstPattern item)
                                     ((err e) (err e))
                                     ((ok p) (ok (listAppend ps (list p))))))))
                              (ok (list)) itemsRaw))]
          (mt itemsRes
            ((ok ps) (ok (a/patTuple ps)))
            ((err e) (err e)))))
       ((= k "patRecord")
        (let [(rawFields (optionOr (getArray val "fields") (list)))
              (fieldsRes (fold (fn [(acc (Result (List (Pair String a/AstPattern)) String)) (fItem j/Json)] -> (Result (List (Pair String a/AstPattern)) String)
                                 (mt acc
                                   ((err e) (err e))
                                   ((ok fs)
                                    (mt (getString fItem "name")
                                      ((none) (err "patRecord field missing name"))
                                      ((some fname)
                                       (mt (getProp fItem "pat")
                                         ((none) (err "patRecord field missing pat"))
                                         ((some pVal)
                                          (mt (parseAstPattern pVal)
                                            ((err e) (err e))
                                            ((ok p) (ok (listAppend fs (list (pair fname p)))))))))))))
                               (ok (list)) rawFields))]
          (mt fieldsRes
            ((ok fs) (ok (a/patRecord fs)))
            ((err e) (err e)))))
       ((= k "patCtor")
        (mt (getString val "name")
          ((none) (err "patCtor missing name"))
          ((some cname)
           (let [(argProp (getProp val "arg"))]
             (mt argProp
               ((none) (ok (a/patCtor cname (none))))
               ((some aVal)
                (mt aVal
                  ((j/jnull) (ok (a/patCtor cname (none))))
                  (_
                   (mt (parseAstPattern aVal)
                     ((ok arg) (ok (a/patCtor cname (some arg))))
                     ((err e) (err e)))))))))))
       (else (err (str "Unknown pattern kind: " k)))))
    ((none)
     (mt val
       ((j/jstr s)
        (if (= s "_")
          (ok (a/patWildcard))
          (ok (a/patVar s))))
       (_ (err "Unrecognized pattern json")))))

fn patFieldToJson f: (Pair String a/AstPattern) -> j/Json
  (j/jobj (list (pair "name" (j/jstr (pairFirst f)))
                (pair "pat" (patternToJson (pairSecond f)))))

fn patternToJson pat: a/AstPattern -> j/Json
  (mt pat
    ((a/patWildcard) (j/jobj (list (pair "kind" (j/jstr "patWildcard")))))
    ((a/patVar name) (j/jobj (list (pair "kind" (j/jstr "patVar")) (pair "name" (j/jstr name)))))
    ((a/patLit lit) (j/jobj (list (pair "kind" (j/jstr "patLit")) (pair "lit" (litToJson lit)))))
    ((a/patTuple elements)
     (j/jobj (list (pair "kind" (j/jstr "patTuple"))
                   (pair "elements" (j/jarr (map patternToJson elements))))))
    ((a/patRecord fields)
     (j/jobj (list (pair "kind" (j/jstr "patRecord"))
                   (pair "fields" (j/jarr (map patFieldToJson fields))))))
    ((a/patCtor name arg)
     (let [(argJson (mt arg ((some a) (patternToJson a)) ((none) (j/jnull))))]
       (j/jobj (list (pair "kind" (j/jstr "patCtor"))
                     (pair "name" (j/jstr name))
                     (pair "arg" argJson))))))

fn parseAstType val: j/Json -> (Result a/AstType String)
  (mt (getKind val)
    ((some k)
     (cond
       ((= k "typeNamed")
        (mt (getString val "name")
          ((some n) (ok (a/typeNamed n)))
          ((none) (err "typeNamed missing name"))))
       ((= k "typeTuple")
        (let [(itemsRaw (optionOr (getArray val "elements") (list)))
              (itemsRes (fold (fn [(acc (Result (List a/AstType) String)) (item j/Json)] -> (Result (List a/AstType) String)
                                (mt acc
                                  ((err e) (err e))
                                  ((ok ts)
                                   (mt (parseAstType item)
                                     ((err e) (err e))
                                     ((ok t) (ok (listAppend ts (list t))))))))
                              (ok (list)) itemsRaw))]
          (mt itemsRes
            ((ok ts) (ok (a/typeTuple ts)))
            ((err e) (err e)))))
       ((= k "typeRecord")
        (let [(rawFields (optionOr (getArray val "fields") (list)))
              (fieldsRes (fold (fn [(acc (Result (List (Pair String a/AstType)) String)) (fItem j/Json)] -> (Result (List (Pair String a/AstType)) String)
                                 (mt acc
                                   ((err e) (err e))
                                   ((ok fs)
                                    (mt (getString fItem "name")
                                      ((none) (err "typeRecord field missing name"))
                                      ((some fname)
                                       (mt (getProp fItem "type")
                                         ((none) (err "typeRecord field missing type"))
                                         ((some tVal)
                                          (mt (parseAstType tVal)
                                            ((err e) (err e))
                                            ((ok t) (ok (listAppend fs (list (pair fname t)))))))))))))
                               (ok (list)) rawFields))]
          (mt fieldsRes
            ((ok fs) (ok (a/typeRecord fs)))
            ((err e) (err e)))))
       ((= k "typeFn")
        (let [(rawParams (optionOr (getArray val "paramTypes") (list)))
              (paramsRes (fold (fn [(acc (Result (List a/AstType) String)) (item j/Json)] -> (Result (List a/AstType) String)
                                 (mt acc
                                   ((err e) (err e))
                                   ((ok ts)
                                    (mt (parseAstType item)
                                      ((err e) (err e))
                                      ((ok t) (ok (listAppend ts (list t))))))))
                               (ok (list)) rawParams))]
          (mt paramsRes
            ((err e) (err e))
            ((ok pts)
             (mt (getProp val "retType")
               ((none) (err "typeFn missing retType"))
               ((some rVal)
                (mt (parseAstType rVal)
                  ((err e) (err e))
                  ((ok rt) (ok (a/typeFn pts rt))))))))))
       (else (err (str "Unknown type kind: " k)))))
    ((none)
     (mt val
       ((j/jstr s) (ok (a/typeNamed s)))
       (_ (err "Unrecognized type json")))))

fn typeFieldToJson f: (Pair String a/AstType) -> j/Json
  (j/jobj (list (pair "name" (j/jstr (pairFirst f)))
                (pair "type" (typeToJson (pairSecond f)))))

fn typeToJson t: a/AstType -> j/Json
  (mt t
    ((a/typeNamed name) (j/jobj (list (pair "kind" (j/jstr "typeNamed")) (pair "name" (j/jstr name)))))
    ((a/typeTuple elements)
     (j/jobj (list (pair "kind" (j/jstr "typeTuple"))
                   (pair "elements" (j/jarr (map typeToJson elements))))))
    ((a/typeRecord fields)
     (j/jobj (list (pair "kind" (j/jstr "typeRecord"))
                   (pair "fields" (j/jarr (map typeFieldToJson fields))))))
    ((a/typeFn paramTypes retType)
     (j/jobj (list (pair "kind" (j/jstr "typeFn"))
                   (pair "paramTypes" (j/jarr (map typeToJson paramTypes)))
                   (pair "retType" (typeToJson retType))))))

fn parseAstMatchArm val: j/Json -> (Result a/AstMatchArm String)
  (mt (getProp val "pat")
    ((none) (err "matchArm missing pat"))
    ((some pVal)
     (mt (parseAstPattern pVal)
       ((err e) (err e))
       ((ok pat)
        (mt (getProp val "body")
          ((none) (err "matchArm missing body"))
          ((some bVal)
           (mt (parseAstExpr bVal)
             ((err e) (err e))
             ((ok body) (ok (a/AstMatchArm :pat pat :body body))))))))))

fn matchArmToJson arm: a/AstMatchArm -> j/Json
  (j/jobj (list (pair "pat" (patternToJson arm.pat))
                (pair "body" (exprToJson arm.body))))

fn parseLetBinding val: j/Json -> (Result (Pair a/AstPattern a/AstExpr) String)
  (mt val
    ((j/jobj _)
     (mt (getProp val "pat")
       ((none) (err "LetBinding missing pat"))
       ((some pVal)
        (mt (parseAstPattern pVal)
          ((err e) (err e))
          ((ok pat)
           (mt (getProp val "val")
             ((none) (err "LetBinding missing val"))
             ((some vVal)
              (mt (parseAstExpr vVal)
                ((err e) (err e))
                ((ok expr) (ok (pair pat expr)))))))))))
    ((j/jarr items)
     (if (>= (listLength items) 2)
       (let [(pVal (listGet items 0)) (vVal (listGet items 1))]
         (mt pVal
           ((some pv)
            (mt (parseAstPattern pv)
              ((err e) (err e))
              ((ok pat)
               (mt vVal
                 ((some vv)
                  (mt (parseAstExpr vv)
                    ((err e) (err e))
                    ((ok expr) (ok (pair pat expr)))))
                 (_ (err "LetBinding val missing"))))))
           (_ (err "LetBinding pat missing"))))
       (err "LetBinding array too short")))
    (_ (err "LetBinding must be object or array")))

fn letBindingToJson b: (Pair a/AstPattern a/AstExpr) -> j/Json
  (j/jobj (list (pair "pat" (patternToJson (pairFirst b)))
                (pair "val" (exprToJson (pairSecond b)))))

fn parseCondClause val: j/Json -> (Result (Pair a/AstExpr (List a/AstExpr)) String)
  (mt (getProp val "test")
    ((none) (err "CondClause missing test"))
    ((some tVal)
     (mt (parseAstExpr tVal)
       ((err e) (err e))
       ((ok testExpr)
        (let [(bodyRaw (optionOr (getArray val "body") (list)))
              (bodyRes (fold (fn [(acc (Result (List a/AstExpr) String)) (item j/Json)] -> (Result (List a/AstExpr) String)
                               (mt acc
                                 ((err e) (err e))
                                 ((ok es)
                                  (mt (parseAstExpr item)
                                    ((err e) (err e))
                                    ((ok e) (ok (listAppend es (list e))))))))
                             (ok (list)) bodyRaw))]
          (mt bodyRes
            ((ok bList) (ok (pair testExpr bList)))
            ((err e) (err e))))))))

fn condClauseToJson cl: (Pair a/AstExpr (List a/AstExpr)) -> j/Json
  (j/jobj (list (pair "test" (exprToJson (pairFirst cl)))
                (pair "body" (j/jarr (map exprToJson (pairSecond cl))))))

fn parseRecordFieldExpr val: j/Json -> (Result (Pair String a/AstExpr) String)
  (mt (getString val "name")
    ((none) (err "RecordField missing name"))
    ((some fname)
     (mt (getProp val "val")
       ((none) (err "RecordField missing val"))
       ((some vVal)
        (mt (parseAstExpr vVal)
          ((err e) (err e))
          ((ok expr) (ok (pair fname expr))))))))

fn recordFieldToJson f: (Pair String a/AstExpr) -> j/Json
  (j/jobj (list (pair "name" (j/jstr (pairFirst f)))
                (pair "val" (exprToJson (pairSecond f)))))

fn parseAstExpr val: j/Json -> (Result a/AstExpr String)
  (mt (getKind val)
    ((some k)
     (cond
       ((= k "exprLit")
        (mt (getProp val "lit")
          ((some lVal)
           (mt (parseAstLit lVal)
             ((ok lit) (ok (a/exprLit lit)))
             ((err e) (err e))))
          ((none) (err "exprLit missing lit"))))
       ((= k "exprIdent")
        (mt (getString val "name")
          ((some n) (ok (a/exprIdent n)))
          ((none) (err "exprIdent missing name"))))
       ((= k "exprMember")
        (mt (getProp val "target")
          ((none) (err "exprMember missing target"))
          ((some tVal)
           (mt (parseAstExpr tVal)
             ((err e) (err e))
             ((ok target)
              (mt (getString val "field")
                ((none) (err "exprMember missing field"))
                ((some fld) (ok (a/exprMember target fld)))))))))
       ((= k "exprCall")
        (mt (getProp val "func")
          ((none) (err "exprCall missing func"))
          ((some fVal)
           (mt (parseAstExpr fVal)
             ((err e) (err e))
             ((ok func)
              (let [(argsRaw (optionOr (getArray val "args") (list)))
                    (argsRes (fold (fn [(acc (Result (List a/AstExpr) String)) (item j/Json)] -> (Result (List a/AstExpr) String)
                                     (mt acc
                                       ((err e) (err e))
                                       ((ok es)
                                        (mt (parseAstExpr item)
                                          ((err e) (err e))
                                          ((ok e) (ok (listAppend es (list e))))))))
                                   (ok (list)) argsRaw))]
                (mt argsRes
                  ((ok args) (ok (a/exprCall func args)))
                  ((err e) (err e)))))))))
       ((= k "exprLet")
        (let [(bindingsRaw (optionOr (getArray val "bindings") (list)))
              (bodyRaw (optionOr (getArray val "body") (list)))
              (bRes (fold (fn [(acc (Result (List (Pair a/AstPattern a/AstExpr)) String)) (item j/Json)] -> (Result (List (Pair a/AstPattern a/AstExpr)) String)
                            (mt acc
                              ((err e) (err e))
                              ((ok bs)
                               (mt (parseLetBinding item)
                                 ((err e) (err e))
                                 ((ok b) (ok (listAppend bs (list b))))))))
                          (ok (list)) bindingsRaw))
              (bodyRes (fold (fn [(acc (Result (List a/AstExpr) String)) (item j/Json)] -> (Result (List a/AstExpr) String)
                               (mt acc
                                 ((err e) (err e))
                                 ((ok es)
                                  (mt (parseAstExpr item)
                                    ((err e) (err e))
                                    ((ok e) (ok (listAppend es (list e))))))))
                             (ok (list)) bodyRaw))]
          (mt bRes
            ((err e) (err e))
            ((ok bindings)
             (mt bodyRes
               ((err e) (err e))
               ((ok body) (ok (a/exprLet bindings body))))))))
       ((= k "exprIf")
        (mt (getProp val "cond")
          ((none) (err "exprIf missing cond"))
          ((some cVal)
           (mt (parseAstExpr cVal)
             ((err e) (err e))
             ((ok c)
              (mt (getProp val "thenBranch")
                ((none) (err "exprIf missing thenBranch"))
                ((some tVal)
                 (mt (parseAstExpr tVal)
                   ((err e) (err e))
                   ((ok tb)
                    (mt (getProp val "elseBranch")
                      ((none) (err "exprIf missing elseBranch"))
                      ((some elVal)
                       (mt (parseAstExpr elVal)
                         ((err e) (err e))
                         ((ok elb) (ok (a/exprIf c tb elb)))))))))))))))
       ((= k "exprMatch")
        (mt (getProp val "target")
          ((none) (err "exprMatch missing target"))
          ((some tVal)
           (mt (parseAstExpr tVal)
             ((err e) (err e))
             ((ok target)
              (let [(armsRaw (optionOr (getArray val "arms") (list)))
                    (armsRes (fold (fn [(acc (Result (List a/AstMatchArm) String)) (item j/Json)] -> (Result (List a/AstMatchArm) String)
                                     (mt acc
                                       ((err e) (err e))
                                       ((ok as)
                                        (mt (parseAstMatchArm item)
                                          ((err e) (err e))
                                          ((ok arm) (ok (listAppend as (list arm))))))))
                                   (ok (list)) armsRaw))]
                (mt armsRes
                  ((ok arms) (ok (a/exprMatch target arms)))
                  ((err e) (err e)))))))))
       ((= k "exprTry")
        (mt (getProp val "inner")
          ((none) (err "exprTry missing inner"))
          ((some iVal)
           (mt (parseAstExpr iVal)
             ((ok inner) (ok (a/exprTry inner)))
             ((err e) (err e))))))
       ((= k "exprBlock")
        (let [(exprsRaw (optionOr (getArray val "exprs") (list)))
              (exprsRes (fold (fn [(acc (Result (List a/AstExpr) String)) (item j/Json)] -> (Result (List a/AstExpr) String)
                                (mt acc
                                  ((err e) (err e))
                                  ((ok es)
                                   (mt (parseAstExpr item)
                                     ((err e) (err e))
                                     ((ok e) (ok (listAppend es (list e))))))))
                              (ok (list)) exprsRaw))]
          (mt exprsRes
            ((ok es) (ok (a/exprBlock es)))
            ((err e) (err e)))))
       ((= k "exprRecord")
        (let [(fieldsRaw (optionOr (getArray val "fields") (list)))
              (fieldsRes (fold (fn [(acc (Result (List (Pair String a/AstExpr)) String)) (item j/Json)] -> (Result (List (Pair String a/AstExpr)) String)
                                 (mt acc
                                   ((err e) (err e))
                                   ((ok fs)
                                    (mt (parseRecordFieldExpr item)
                                      ((err e) (err e))
                                      ((ok f) (ok (listAppend fs (list f))))))))
                               (ok (list)) fieldsRaw))
              (tokensRaw (optionOr (getArray val "rawTokens") (list)))
              (tokensRes (fold (fn [(acc (Result (List a/AstExpr) String)) (item j/Json)] -> (Result (List a/AstExpr) String)
                                 (mt acc
                                   ((err e) (err e))
                                   ((ok ts)
                                    (mt (parseAstExpr item)
                                      ((err e) (err e))
                                      ((ok t) (ok (listAppend ts (list t))))))))
                               (ok (list)) tokensRaw))]
          (mt fieldsRes
            ((err e) (err e))
            ((ok fs)
             (mt tokensRes
               ((err e) (err e))
               ((ok ts)
                (if (and (listEmpty? ts) (not (listEmpty? fs)))
                  (let [(synthesized (fold (fn [(acc (List a/AstExpr)) (f (Pair String a/AstExpr))] -> (List a/AstExpr)
                                             (listAppend acc (list (a/exprIdent (str ":" (pairFirst f))) (pairSecond f))))
                                           (list) fs))]
                    (ok (a/exprRecord fs synthesized)))
                  (ok (a/exprRecord fs ts)))))))))
       ((= k "exprCond")
        (let [(clausesRaw (optionOr (getArray val "clauses") (list)))
              (clausesRes (fold (fn [(acc (Result (List (Pair a/AstExpr (List a/AstExpr))) String)) (item j/Json)] -> (Result (List (Pair a/AstExpr (List a/AstExpr))) String)
                                  (mt acc
                                    ((err e) (err e))
                                    ((ok cls)
                                     (mt (parseCondClause item)
                                       ((err e) (err e))
                                       ((ok cl) (ok (listAppend cls (list cl))))))))
                                (ok (list)) clausesRaw))]
          (mt clausesRes
            ((ok cls) (ok (a/exprCond cls)))
            ((err e) (err e)))))
       ((= k "exprLambda")
        (let [(paramsRaw (optionOr (getArray val "params") (list)))
              (paramsRes (fold (fn [(acc (Result (List a/Param) String)) (item j/Json)] -> (Result (List a/Param) String)
                                 (mt acc
                                   ((err e) (err e))
                                   ((ok ps)
                                    (mt (parseParam item)
                                      ((err e) (err e))
                                      ((ok p) (ok (listAppend ps (list p))))))))
                               (ok (list)) paramsRaw))
              (retType (getString val "retType"))
              (bodyRaw (optionOr (getArray val "body") (list)))
              (bodyRes (fold (fn [(acc (Result (List a/AstExpr) String)) (item j/Json)] -> (Result (List a/AstExpr) String)
                               (mt acc
                                 ((err e) (err e))
                                 ((ok es)
                                  (mt (parseAstExpr item)
                                    ((err e) (err e))
                                    ((ok e) (ok (listAppend es (list e))))))))
                              (ok (list)) bodyRaw))]
          (mt paramsRes
            ((err e) (err e))
            ((ok ps)
             (mt bodyRes
               ((err e) (err e))
               ((ok body) (ok (a/exprLambda ps retType body (rd/makeList (list))))))))))
       ((= k "exprInterpolation")
        (let [(partsRaw (optionOr (getArray val "parts") (list)))
              (partsRes (fold (fn [(acc (Result (List a/AstExpr) String)) (item j/Json)] -> (Result (List a/AstExpr) String)
                                (mt acc
                                  ((err e) (err e))
                                  ((ok ps)
                                   (mt (parseAstExpr item)
                                     ((err e) (err e))
                                     ((ok p) (ok (listAppend ps (list p))))))))
                              (ok (list)) partsRaw))]
          (mt partsRes
            ((ok ps) (ok (a/exprInterpolation ps)))
            ((err e) (err e)))))
       (else (err (str "Unknown expression kind: " k)))))
    ((none)
     (mt (parseAstLit val)
       ((ok lit) (ok (a/exprLit lit)))
       ((err _)
        (mt val
          ((j/jstr s) (ok (a/exprIdent s)))
          (_ (err "Unrecognized expression json")))))))

fn exprToJson expr: a/AstExpr -> j/Json
  (mt expr
    ((a/exprLit lit) (j/jobj (list (pair "kind" (j/jstr "exprLit")) (pair "lit" (litToJson lit)))))
    ((a/exprIdent name) (j/jobj (list (pair "kind" (j/jstr "exprIdent")) (pair "name" (j/jstr name)))))
    ((a/exprMember target field)
     (j/jobj (list (pair "kind" (j/jstr "exprMember"))
                   (pair "target" (exprToJson target))
                   (pair "field" (j/jstr field)))))
    ((a/exprCall func args)
     (j/jobj (list (pair "kind" (j/jstr "exprCall"))
                   (pair "func" (exprToJson func))
                   (pair "args" (j/jarr (map exprToJson args))))))
    ((a/exprLet bindings body)
     (j/jobj (list (pair "kind" (j/jstr "exprLet"))
                   (pair "bindings" (j/jarr (map letBindingToJson bindings)))
                   (pair "body" (j/jarr (map exprToJson body))))))
    ((a/exprIf cond thenBranch elseBranch)
     (j/jobj (list (pair "kind" (j/jstr "exprIf"))
                   (pair "cond" (exprToJson cond))
                   (pair "thenBranch" (exprToJson thenBranch))
                   (pair "elseBranch" (exprToJson elseBranch)))))
    ((a/exprMatch target arms)
     (j/jobj (list (pair "kind" (j/jstr "exprMatch"))
                   (pair "target" (exprToJson target))
                   (pair "arms" (j/jarr (map matchArmToJson arms))))))
    ((a/exprTry inner)
     (j/jobj (list (pair "kind" (j/jstr "exprTry"))
                   (pair "inner" (exprToJson inner)))))
    ((a/exprBlock exprs)
     (j/jobj (list (pair "kind" (j/jstr "exprBlock"))
                   (pair "exprs" (j/jarr (map exprToJson exprs))))))
    ((a/exprRecord fields rawTokens)
     (j/jobj (list (pair "kind" (j/jstr "exprRecord"))
                   (pair "fields" (j/jarr (map recordFieldToJson fields)))
                   (pair "rawTokens" (j/jarr (map exprToJson rawTokens))))))
    ((a/exprCond clauses)
     (j/jobj (list (pair "kind" (j/jstr "exprCond"))
                   (pair "clauses" (j/jarr (map condClauseToJson clauses))))))
    ((a/exprLambda params retType body _)
     (let [(retJson (mt retType ((some r) (j/jstr r)) ((none) (j/jnull))))]
       (j/jobj (list (pair "kind" (j/jstr "exprLambda"))
                     (pair "params" (j/jarr (map paramToJson params)))
                     (pair "retType" retJson)
                     (pair "body" (j/jarr (map exprToJson body)))))))
    ((a/exprInterpolation parts)
     (j/jobj (list (pair "kind" (j/jstr "exprInterpolation"))
                   (pair "parts" (j/jarr (map exprToJson parts)))))))

fn parseSchemaNode val: j/Json -> (Result a/SchemaNode String)
  (mt (getString val "name")
    ((none) (err "SchemaNode missing name"))
    ((some name)
     (let [(tv (optionOr (getStringList val "typeVars") (list)))
           (rawFields (optionOr (getArray val "fields") (list)))
           (fRes (fold (fn [(acc (Result (List a/AstField) String)) (item j/Json)] -> (Result (List a/AstField) String)
                         (mt acc
                           ((err e) (err e))
                           ((ok fs)
                            (mt (parseAstField item)
                              ((err e) (err e))
                              ((ok f) (ok (listAppend fs (list f))))))))
                       (ok (list)) rawFields))
           (jc (getString val "jsonCase"))]
       (mt fRes
         ((err e) (err e))
         ((ok fields) (ok (a/SchemaNode :name name :typeVars tv :fields fields :jsonCase jc)))))))

fn schemaToJson s: a/SchemaNode -> j/Json
  (let [(jcJson (mt s.jsonCase ((some jc) (j/jstr jc)) ((none) (j/jnull))))]
    (j/jobj (list (pair "name" (j/jstr s.name))
                  (pair "typeVars" (j/jarr (map (fn [(tv String)] -> j/Json (j/jstr tv)) s.typeVars)))
                  (pair "fields" (j/jarr (map fieldToJson s.fields)))
                  (pair "jsonCase" jcJson))))

fn parseEnumNode val: j/Json -> (Result a/EnumNode String)
  (mt (getString val "name")
    ((none) (err "EnumNode missing name"))
    ((some name)
     (let [(tv (optionOr (getStringList val "typeVars") (list)))
           (rawCases (optionOr (getArray val "cases") (list)))
           (cRes (fold (fn [(acc (Result (List a/EnumCase) String)) (item j/Json)] -> (Result (List a/EnumCase) String)
                         (mt acc
                           ((err e) (err e))
                           ((ok cs)
                            (mt (parseEnumCase item)
                              ((err e) (err e))
                              ((ok c) (ok (listAppend cs (list c))))))))
                       (ok (list)) rawCases))]
       (mt cRes
         ((err e) (err e))
         ((ok cases) (ok (a/EnumNode :name name :typeVars tv :cases cases)))))))

fn enumToJson e: a/EnumNode -> j/Json
  (j/jobj (list (pair "name" (j/jstr e.name))
                (pair "typeVars" (j/jarr (map (fn [(tv String)] -> j/Json (j/jstr tv)) e.typeVars)))
                (pair "cases" (j/jarr (map enumCaseToJson e.cases)))))

fn parseDefunNode val: j/Json -> (Result a/DefunNode String)
  (mt (getString val "name")
    ((none) (err "DefunNode missing name"))
    ((some name)
     (mt (getArray val "params")
       ((none) (err "DefunNode missing params"))
       ((some rawParams)
        (mt (getString val "retType")
          ((none) (err "DefunNode missing retType"))
          ((some retType)
           (let [(tv (optionOr (getStringList val "typeVars") (list)))
                 (isExp (optionOr (getBool val "isExported") false))
                 (eff (optionOr (getBool val "effect") false))
                 (pRes (fold (fn [(acc (Result (List a/Param) String)) (item j/Json)] -> (Result (List a/Param) String)
                               (mt acc
                                 ((err e) (err e))
                                 ((ok ps)
                                  (mt (parseParam item)
                                    ((err e) (err e))
                                    ((ok p) (ok (listAppend ps (list p))))))))
                             (ok (list)) rawParams))
                 (doc (optionOr (getString val "docstring") ""))
                 (rawBody (optionOr (getArray val "body") (list)))
                 (bodyRes (fold (fn [(acc (Result (List rd/SExpr) String)) (item j/Json)] -> (Result (List rd/SExpr) String)
                                  (mt acc
                                    ((err e) (err e))
                                    ((ok bs)
                                     (mt (parseAstExpr item)
                                       ((err e) (err e))
                                       ((ok expr) (ok (listAppend bs (list (cv/lower expr)))))))))
                                (ok (list)) rawBody))]
             (mt pRes
               ((err e) (err e))
               ((ok params)
                (mt bodyRes
                  ((err e) (err e))
                  ((ok body)
                   (ok (a/DefunNode :name name
                                    :typeVars tv
                                    :isExported isExp
                                    :effect eff
                                    :params params
                                    :retType retType
                                    :docstring doc
                                    :body body
                                    :bodyPos (list))))))))))))))

fn defunToJson d: a/DefunNode -> j/Json
  (let [(bodyExprs (map (fn [(b rd/SExpr)] -> j/Json (exprToJson (cv/lift b))) d.body))]
    (j/jobj (list (pair "name" (j/jstr d.name))
                  (pair "typeVars" (j/jarr (map (fn [(tv String)] -> j/Json (j/jstr tv)) d.typeVars)))
                  (pair "isExported" (j/jbool d.isExported))
                  (pair "effect" (j/jbool d.effect))
                  (pair "params" (j/jarr (map paramToJson d.params)))
                  (pair "retType" (j/jstr d.retType))
                  (pair "docstring" (j/jstr d.docstring))
                  (pair "body" (j/jarr bodyExprs)))))

fn parseModuleNode val: j/Json -> (Result a/ModuleNode String)
  (mt (getString val "path")
    ((none) (err "ModuleNode missing path"))
    ((some path)
     (let [(doc (optionOr (getString val "docstring") ""))
           (exp (optionOr (getStringList val "exported") (list)))
           (rawImp (optionOr (getArray val "imports") (list)))
           (impRes (fold (fn [(acc (Result (List (Pair String String)) String)) (item j/Json)] -> (Result (List (Pair String String)) String)
                           (mt acc
                             ((err e) (err e))
                             ((ok imps)
                              (mt (parseImportEntry item)
                                ((err e) (err e))
                                ((ok p) (ok (listAppend imps (list p))))))))
                         (ok (list)) rawImp))
           (rawDefs (optionOr (getArray val "defs") (list)))
           (defsRes (fold (fn [(acc (Result (List a/TopForm) String)) (item j/Json)] -> (Result (List a/TopForm) String)
                            (mt acc
                              ((err e) (err e))
                              ((ok dfs)
                               (mt (parseTopForm item)
                                 ((err e) (err e))
                                 ((ok tf) (ok (listAppend dfs (list tf))))))))
                          (ok (list)) rawDefs))]
       (mt impRes
         ((err e) (err e))
         ((ok imports)
          (mt defsRes
            ((err e) (err e))
            ((ok defs)
             (ok (a/ModuleNode :path path
                               :docstring doc
                               :exported exp
                               :imports imports
                               :defs defs)))))))))

fn moduleToJson m: a/ModuleNode -> j/Json
  (j/jobj (list (pair "path" (j/jstr m.path))
                (pair "docstring" (j/jstr m.docstring))
                (pair "exported" (j/jarr (map (fn [(s String)] -> j/Json (j/jstr s)) m.exported)))
                (pair "imports" (j/jarr (map importToJson m.imports)))
                (pair "defs" (j/jarr (map topFormToJson m.defs)))))

fn parseExprPosNode val: j/Json -> (Result a/PosForm String)
  (mt (getProp val "expr")
    ((none) (err "Missing expr for topExpr"))
    ((some exprVal)
     (mt (parseAstExpr exprVal)
       ((err e) (err e))
       ((ok expr) (ok (a/PosForm :expr (cv/lower expr) :line (optionOr (getInt val "line") 0) :col (optionOr (getInt val "col") 0)))))))

fn parseTopForm val: j/Json -> (Result a/TopForm String)
  (let [(nodeOpt (getProp val "node"))
        (target (optionOr nodeOpt val))]
    (mt (getKind val)
      ((some k)
       (cond
         ((= k "topModule")
          (mt (parseModuleNode target)
            ((ok m) (ok (a/topModule m)))
            ((err e) (err e))))
         ((= k "topSchema")
          (mt (parseSchemaNode target)
            ((ok s) (ok (a/topSchema s)))
            ((err e) (err e))))
         ((= k "topEnum")
          (mt (parseEnumNode target)
            ((ok en) (ok (a/topEnum en)))
            ((err e) (err e))))
         ((= k "topDefun")
          (mt (parseDefunNode target)
            ((ok d) (ok (a/topDefun d)))
            ((err e) (err e))))
         ((= k "topExpr")
          (mt (parseExprPosNode (optionOr (getProp val "pos") val))
            ((ok p) (ok (a/topExpr p)))
            ((err e) (err e))))
         (else (err (str "Unknown top form kind: " k)))))
      ((none)
       (cond
         ((some? (getString target "path"))
          (mt (parseModuleNode target)
            ((ok m) (ok (a/topModule m)))
            ((err e) (err e))))
         ((some? (getArray target "cases"))
          (mt (parseEnumNode target)
            ((ok en) (ok (a/topEnum en)))
            ((err e) (err e))))
         ((and (some? (getString target "name")) (some? (getArray target "fields")))
          (mt (parseSchemaNode target)
            ((ok s) (ok (a/topSchema s)))
            ((err e) (err e))))
         ((and (some? (getString target "name")) (some? (getString target "retType")))
          (mt (parseDefunNode target)
            ((ok d) (ok (a/topDefun d)))
            ((err e) (err e))))
         (else (err "Unrecognized top form json"))))))

fn topFormToJson tf: a/TopForm -> j/Json
  (mt tf
    ((a/topModule m)
     (j/jobj (list (pair "kind" (j/jstr "topModule"))
                   (pair "node" (moduleToJson m)))))
    ((a/topSchema s)
     (j/jobj (list (pair "kind" (j/jstr "topSchema"))
                   (pair "node" (schemaToJson s)))))
    ((a/topEnum e)
     (j/jobj (list (pair "kind" (j/jstr "topEnum"))
                   (pair "node" (enumToJson e)))))
    ((a/topDefun d)
     (j/jobj (list (pair "kind" (j/jstr "topDefun"))
                   (pair "node" (defunToJson d)))))
    ((a/topExpr p)
     (j/jobj (list (pair "kind" (j/jstr "topExpr"))
                   (pair "pos" (j/jobj (list (pair "expr" (exprToJson (cv/lift p.expr)))
                                             (pair "line" (j/jint p.line))
                                             (pair "col" (j/jint p.col)))))))))

fn topFormsToJson forms: (List a/TopForm) -> j/Json
  (j/jarr (map topFormToJson forms))

fn renderTopForm tf: a/TopForm -> String
  (mt tf
    ((a/topModule m)
     (if (listEmpty? m.defs)
       (a/renderNode tf)
       (ap/printAstModule m)))
    ((a/topDefun _) (ap/printTopForm tf))
    ((a/topSchema _) (ap/printTopForm tf))
    ((a/topEnum _) (ap/printTopForm tf))
    ((a/topExpr _) (ap/printTopForm tf)))

fn topFormToJsonString tf: a/TopForm -> String
  (j/jsonEmit (topFormToJson tf))

fn moduleToJsonString m: a/ModuleNode -> String
  (j/jsonEmit (moduleToJson m))

fn exprToJsonString expr: a/AstExpr -> String
  (j/jsonEmit (exprToJson expr))

fn topFormsToJsonString forms: (List a/TopForm) -> String
  (j/jsonEmit (topFormsToJson forms))

fn fromJsonTopForm jsonStr: String -> (Result a/TopForm String)
  (mt (j/jsonParse jsonStr)
    ((err e) (err (str "JSON parse error: " e)))
    ((ok j) (parseTopForm j)))

fn fromJsonModule jsonStr: String -> (Result a/ModuleNode String)
  (mt (j/jsonParse jsonStr)
    ((err e) (err (str "JSON parse error: " e)))
    ((ok j)
     (mt (getProp j "node")
       ((some nVal) (parseModuleNode nVal))
       ((none) (parseModuleNode j)))))

fn fromJsonExpr jsonStr: String -> (Result a/AstExpr String)
  (mt (j/jsonParse jsonStr)
    ((err e) (err (str "JSON parse error: " e)))
    ((ok j) (parseAstExpr j)))

fn fromJsonTopForms jsonStr: String -> (Result (List a/TopForm) String)
  (mt (j/jsonParse jsonStr)
    ((err e) (err (str "JSON parse error: " e)))
    ((ok parsedVal)
     (mt parsedVal
       ((j/jarr items)
        (let [(res (fold (fn [(acc (Result (List a/TopForm) String)) (item j/Json)] -> (Result (List a/TopForm) String)
                           (mt acc
                             ((err e) (err e))
                             ((ok tfs)
                              (mt (parseTopForm item)
                                ((err e) (err e))
                                ((ok tf) (ok (listAppend tfs (list tf))))))))
                         (ok (list)) items))]
          res))
       (_
        (mt (parseTopForm parsedVal)
          ((ok tf) (ok (list tf)))
          ((err e) (err e)))))))

fn fromJsonToAsl jsonStr: String -> (Result String String)
  (mt (j/jsonParse jsonStr)
    ((err e) (err (str "JSON parse error: " e)))
    ((ok parsedVal)
     (mt parsedVal
       ((j/jarr items)
        (let [(formsRes (fold (fn [(acc (Result (List a/TopForm) String)) (item j/Json)] -> (Result (List a/TopForm) String)
                                (mt acc
                                  ((err e) (err e))
                                  ((ok tfs)
                                   (mt (parseTopForm item)
                                     ((err e) (err e))
                                     ((ok tf) (ok (listAppend tfs (list tf))))))))
                              (ok (list)) items))]
          (mt formsRes
            ((err e) (err e))
            ((ok forms)
             (let [(rendered (map renderTopForm forms))]
               (ok (stringJoin rendered "\n\n")))))))
       (_
        (mt (parseTopForm parsedVal)
          ((ok tf) (ok (renderTopForm tf)))
          ((err _)
           (mt (parseModuleNode parsedVal)
             ((ok m) (ok (ap/printAstModule m)))
             ((err _)
              (mt (parseAstExpr parsedVal)
                ((ok expr) (ok (ap/printAst expr)))
                ((err e) (err (str "Could not parse ASL JSON: " e))))))))))))

