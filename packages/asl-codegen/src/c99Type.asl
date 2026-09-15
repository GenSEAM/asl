(module asl-codegen/c99Type
  :d "ISO C99 Type System Mapping, Memory Layout & Tagged Union Architecture."
  :x [c99PrimitiveType
      c99TypeStr
      emitCDefschema
      emitCDefenum
      emitCStringType
      emitCOptionType
      emitCSliceType
      c99TypeName
      c99FieldIdent
      c99UpperIdent
      isC99Keyword?
      isC99NativeType?]
  :i [(ast :a a) (asl-checker/types :a ty) (mangle :a m)])

(df isC99Keyword? [(id String)] -> Bool
  :d "Checks if identifier collides with an ISO C99 reserved keyword."
  (list-contains?
    (list "auto" "break" "case" "char" "const" "continue" "default" "do"
          "double" "else" "enum" "extern" "float" "for" "goto" "if"
          "inline" "int" "long" "register" "restrict" "return" "short" "signed"
          "sizeof" "static" "struct" "switch" "typedef" "union" "unsigned" "void"
          "volatile" "while" "_Bool" "_Complex" "_Imaginary")
    id))

(df isC99NativeType? [(s String)] -> Bool
  :d "Checks if string is already a canonical C99 native type or standard typedef."
  (list-contains?
    (list "int64_t" "int32_t" "int16_t" "int8_t"
          "uint64_t" "uint32_t" "uint16_t" "uint8_t"
          "double" "float" "bool" "void" "size_t"
          "asl_string_t" "const char*" "char*" "char"
          "int" "long" "short" "unsigned int")
    s))

(df c99FieldIdent [(s String)] -> String
  :d "Sanitizes an ASL field name into a safe ISO C99 snake_case identifier."
  (let [(sLen (string-length s))
        (base1 (if (and (> sLen 1) (string-ends-with? s "?"))
                   (if (string-starts-with? s "is-")
                       (m/sliceOr s 0 (- sLen 1) "")
                       (str "is-" (m/sliceOr s 0 (- sLen 1) "")))
                   s))
        (len1 (string-length base1))
        (base2 (if (and (> len1 1) (string-ends-with? base1 "!"))
                   (str (m/sliceOr base1 0 (- len1 1) "") "-mut")
                   base1))
        (snaked (string-replace (string-replace base2 "-" "_") "/" "_"))]
    (if (isC99Keyword? snaked)
        (str "asl_" snaked)
        snaked)))

(df c99UpperIdent [(s String)] -> String
  :d "Converts an identifier to canonical uppercase C constant token."
  (let [(sLen (string-length s))
        (base1 (if (and (> sLen 1) (string-ends-with? s "?"))
                   (m/sliceOr s 0 (- sLen 1) "")
                   s))
        (len1 (string-length base1))
        (base2 (if (and (> len1 1) (string-ends-with? base1 "!"))
                   (m/sliceOr base1 0 (- len1 1) "")
                   base1))
        (s3 (string-replace base2 "-" "_"))
        (s4 (string-replace s3 "." "_"))
        (s5 (string-replace s4 "/" "_"))]
    (string-upper s5)))

(df c99TypeName [(s String)] -> String
  :d "Converts ASL schema or enum name to PascalCase with Asl prefix."
  (let [(pascal (m/pascalIdent s))]
    (if (string-starts-with? pascal "Asl")
        pascal
        (str "Asl" pascal))))

(df sanitizeCIdent [(s String)] -> String
  :d "Sanitizes composite type name for inclusion in struct/typedef identifier."
  (let [(s1 (string-replace s "*" "_ptr"))
        (s2 (string-replace s1 " " "_"))
        (s3 (string-replace s2 "-" "_"))
        (s4 (string-replace s3 "(" ""))
        (s5 (string-replace s4 ")" ""))]
    s5))

(df c99PrimitiveType [(name String)] -> (Option String)
  :d "Maps primitive Core ASL types to ISO C99 fixed-width and primitive types."
  (let [(canon (ty/resolveTypeAlias name))]
    (cond
      ((or (= name "Int64") (= name "I64") (= name "Int") (= canon "Int64")) (some "int64_t"))
      ((or (= name "Int32") (= name "I32") (= canon "Int32")) (some "int32_t"))
      ((or (= name "Float32") (= name "F32")) (some "float"))
      ((or (= name "Float64") (= name "F64") (= name "Float") (= name "Num") (= canon "Float64")) (some "double"))
      ((or (= name "Bool") (= canon "Bool")) (some "bool"))
      ((or (= name "Unit") (= canon "Unit")) (some "void"))
      ((or (= name "String") (= name "Str") (= canon "String")) (some "asl_string_t"))
      (:else (none)))))

(df c99FromType [(t ty/Type)] -> String
  :d "Lowers a parsed ASL Type AST into its canonical ISO C99 type representation."
  (mt t
    ((ty/tyVar id kind)
     (cond
       ((= kind "int") "int64_t")
       ((= kind "num") "double")
       (:else "void*")))
    ((ty/tyFun params ret)
     "void*")
    ((ty/tyCon name args modOpt shownOpt)
     (let [(prim (c99PrimitiveType name))]
       (mt prim
         ((some p) p)
         ((none)
          (cond
            ((= name "Option")
             (if (> (list-length args) 0)
                 (let [(inner (c99FromType (option-or (list-get args 0) (ty/tyCon "Unit" (list) (none) (none)))))]
                   (str "AslOption_" (sanitizeCIdent inner)))
                 "AslOption_void"))
            ((= name "List")
             (if (> (list-length args) 0)
                 (let [(inner (c99FromType (option-or (list-get args 0) (ty/tyCon "Unit" (list) (none) (none)))))]
                   (str "AslSlice_" (sanitizeCIdent inner)))
                 "AslSlice_void"))
            ((= name "Pair")
             (if (>= (list-length args) 2)
                 (let [(a (c99FromType (option-or (list-get args 0) (ty/tyCon "Unit" (list) (none) (none)))))
                       (b (c99FromType (option-or (list-get args 1) (ty/tyCon "Unit" (list) (none) (none)))))]
                   (str "AslPair_" (sanitizeCIdent a) "_" (sanitizeCIdent b)))
                 "AslPair_void_void"))
            (:else
             (c99TypeName name)))))))))

(df c99TypeStr [(s String)] -> String
  :d "Maps an ASL type annotation string or native C type into canonical ISO C99 type."
  (let [(trimmed (string-trim s))]
    (if (isC99NativeType? trimmed)
        trimmed
        (let [(prim (c99PrimitiveType trimmed))]
          (mt prim
            ((some p) p)
            ((none)
             (if (string-starts-with? trimmed "AslOption_")
                 trimmed
                 (if (string-starts-with? trimmed "AslSlice_")
                     trimmed
                     (if (string-ends-with? trimmed "*")
                         trimmed
                         (c99FromType (ty/parseTypeStr trimmed (list))))))))))))

(df emitCStringType [] -> String
  :d "Emits standard ISO C99 string slice typedef."
  "#ifndef ASL_STRING_T_DEFINED\n#define ASL_STRING_T_DEFINED\ntypedef struct {\n    const char* data;\n    size_t len;\n} asl_string_t;\n#endif\n")

(df emitCOptionType [(innerType String)] -> String
  :d "Emits an ISO C99 Option container typedef for a given inner type."
  (let [(cTy (c99TypeStr innerType))
        (optName (str "AslOption_" (sanitizeCIdent cTy)))]
    (str "typedef struct {\n    bool hasValue;\n    " cTy " value;\n} " optName ";\n")))

(df emitCSliceType [(elemType String)] -> String
  :d "Emits an ISO C99 List/Slice container typedef for a given element type."
  (let [(cTy (c99TypeStr elemType))
        (sliceName (str "AslSlice_" (sanitizeCIdent cTy)))]
    (str "typedef struct {\n    const " cTy "* items;\n    size_t count;\n} " sliceName ";\n")))

(df hasEmptyFieldNameStep [(fields (List a/AstField)) (idx Int64) (len Int64)] -> Bool
  :d "Checks if any schema field has empty name."
  (if (>= idx len)
      false
      (let [(f (option-or (list-get fields idx) (a/AstField :name "" :type "Unit")))]
        (if (= (string-trim (.-name f)) "")
            true
            (hasEmptyFieldNameStep fields (+ idx 1) len)))))

(df emitSchemaFieldLinesStep [(rawName String) (typeName String) (fields (List a/AstField)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Emits schema field declarations."
  (if (>= idx len)
      acc
      (let [(f (option-or (list-get fields idx) (a/AstField :name "" :type "Unit")))
            (fName (c99FieldIdent (.-name f)))
            (rawTy (.-type f))
            (fTy (if (or (= rawTy rawName) (= rawTy typeName))
                     (str "struct " typeName "_s*")
                     (c99TypeStr rawTy)))
            (line (str "    " fTy " " fName ";\n"))]
        (emitSchemaFieldLinesStep rawName typeName fields (+ idx 1) len (list-append acc (list line))))))

(df hasEmptyCaseNameStep [(cases (List a/EnumCase)) (idx Int64) (len Int64)] -> Bool
  :d "Checks if any enum case has empty name."
  (if (>= idx len)
      false
      (let [(c (option-or (list-get cases idx) (a/EnumCase :name "" :fields (list))))]
        (if (= (string-trim (.-name c)) "")
            true
            (hasEmptyCaseNameStep cases (+ idx 1) len)))))

(df emitTagConstantsStep [(upperEnum String) (cases (List a/EnumCase)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Generates tag constant identifiers for enum cases."
  (if (>= idx len)
      acc
      (let [(c (option-or (list-get cases idx) (a/EnumCase :name "" :fields (list))))
            (cName (str "ASL_" upperEnum "_" (c99UpperIdent (.-name c))))]
        (emitTagConstantsStep upperEnum cases (+ idx 1) len (list-append acc (list cName))))))

(df formatTagLine [(constName String)] -> String
  :d "Formats single enum tag enum line."
  (str "    " constName))

(df filterCasesWithFieldsStep [(cases (List a/EnumCase)) (idx Int64) (len Int64) (acc (List a/EnumCase))] -> (List a/EnumCase)
  :d "Filters enum cases having one or more fields."
  (if (>= idx len)
      acc
      (let [(c (option-or (list-get cases idx) (a/EnumCase :name "" :fields (list))))]
        (if (> (list-length (.-fields c)) 0)
            (filterCasesWithFieldsStep cases (+ idx 1) len (list-append acc (list c)))
            (filterCasesWithFieldsStep cases (+ idx 1) len acc)))))

(df emitEnumCaseParamLinesStep [(rawName String) (typeName String) (params (List a/Param)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Emits enum case struct field declarations."
  (if (>= idx len)
      acc
      (let [(p (option-or (list-get params idx) (a/Param :name "" :type "Unit")))
            (pName (c99FieldIdent (.-name p)))
            (rawTy (.-type p))
            (pTy (if (or (= rawTy rawName) (= rawTy typeName))
                     (str "struct " typeName "_s*")
                     (c99TypeStr rawTy)))
            (line (str "        " pTy " " pName ";\n"))]
        (emitEnumCaseParamLinesStep rawName typeName params (+ idx 1) len (list-append acc (list line))))))

(df emitEnumCaseMemberLinesStep [(rawName String) (typeName String) (cases (List a/EnumCase)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Emits enum union member structs."
  (if (>= idx len)
      acc
      (let [(c (option-or (list-get cases idx) (a/EnumCase :name "" :fields (list))))
            (caseMemberName (c99FieldIdent (.-name c)))
            (pList (.-fields c))
            (fieldLines (emitEnumCaseParamLinesStep rawName typeName pList 0 (list-length pList) (list)))
            (structStr (str "    struct {\n" (string-join fieldLines "") "    } " caseMemberName ";\n"))]
        (emitEnumCaseMemberLinesStep rawName typeName cases (+ idx 1) len (list-append acc (list structStr))))))

(df emitCDefschema [(s a/SchemaNode)] -> String
  :d "Serializes an AST SchemaNode into an ISO C99 struct typedef."
  (let [(rawName (string-trim (.-name s)))
        (fields (.-fields s))
        (fLen (list-length fields))
        (hasEmptyName? (= rawName ""))
        (hasEmptyFieldName? (hasEmptyFieldNameStep fields 0 fLen))]
    (if (or hasEmptyName? hasEmptyFieldName?)
        ""
        (let [(typeName (c99TypeName rawName))
              (bodyStrs (if (<= fLen 0)
                            "    char _unused;\n"
                            (string-join (emitSchemaFieldLinesStep rawName typeName fields 0 fLen (list)) "")))]
          (str "typedef struct " typeName "_s {\n" bodyStrs "} " typeName ";\n")))))

(df emitCaseTagAlias [(upperEnum String) (c a/EnumCase)] -> String
  :d "Emits tag alias for an enum case."
  (let [(cUpper (c99UpperIdent (.-name c)))
        (tagConst (str "ASL_" upperEnum "_" cUpper))
        (tagAlias (str "ASL_TAG_" cUpper))]
    (str "#ifndef " tagAlias "\n#define " tagAlias " " tagConst "\n#endif\n")))

(df emitCaseTagAliasesStep [(upperEnum String) (cases (List a/EnumCase)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Accumulates tag aliases for all enum cases."
  (if (>= idx len)
      acc
      (let [(c (option-or (list-get cases idx) (a/EnumCase :name "" :fields (list))))
            (alias (emitCaseTagAlias upperEnum c))]
        (emitCaseTagAliasesStep upperEnum cases (+ idx 1) len (list-append acc (list alias))))))

(df emitConstructorParamsStep [(rawName String) (typeName String) (params (List a/Param)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Formats parameter list for enum case constructor."
  (if (>= idx len)
      acc
      (let [(p (option-or (list-get params idx) (a/Param :name "" :type "Unit")))
            (pName (c99FieldIdent (.-name p)))
            (rawTy (.-type p))
            (pTy (if (or (= rawTy rawName) (= rawTy typeName))
                     (str "struct " typeName "_s*")
                     (c99TypeStr rawTy)))
            (entry (str pTy " " pName))]
        (emitConstructorParamsStep rawName typeName params (+ idx 1) len (list-append acc (list entry))))))

(df emitConstructorAssignsStep [(cMember String) (params (List a/Param)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Formats payload field assignments for enum case constructor."
  (if (>= idx len)
      acc
      (let [(p (option-or (list-get params idx) (a/Param :name "" :type "Unit")))
            (pName (c99FieldIdent (.-name p)))
            (line (str "    _res.data." cMember "." pName " = " pName ";\n"))]
        (emitConstructorAssignsStep cMember params (+ idx 1) len (list-append acc (list line))))))

(df emitCaseConstructor [(upperEnum String) (rawName String) (typeName String) (c a/EnumCase)] -> String
  :d "Emits a static inline constructor function for an enum case."
  (let [(rawCaseName (.-name c))
        (fnName (c99FieldIdent rawCaseName))
        (cUpper (c99UpperIdent rawCaseName))
        (tagConst (str "ASL_" upperEnum "_" cUpper))
        (pList (.-fields c))
        (pLen (list-length pList))
        (cMember (c99FieldIdent rawCaseName))]
    (if (<= pLen 0)
        (str "static inline " typeName " " fnName "(void) {\n    " typeName " _res;\n    memset(&_res, 0, sizeof(_res));\n    _res.tag = " tagConst ";\n    return _res;\n}\n\n")
        (let [(paramStr (string-join (emitConstructorParamsStep rawName typeName pList 0 pLen (list)) ", "))
              (assignLines (emitConstructorAssignsStep cMember pList 0 pLen (list)))]
          (str "static inline " typeName " " fnName "(" paramStr ") {\n    " typeName " _res;\n    memset(&_res, 0, sizeof(_res));\n    _res.tag = " tagConst ";\n" (string-join assignLines "") "    return _res;\n}\n\n")))))

(df emitCaseConstructorsStep [(upperEnum String) (rawName String) (typeName String) (cases (List a/EnumCase)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Accumulates constructor functions for all enum cases."
  (if (>= idx len)
      acc
      (let [(c (option-or (list-get cases idx) (a/EnumCase :name "" :fields (list))))
            (ctor (emitCaseConstructor upperEnum rawName typeName c))]
        (emitCaseConstructorsStep upperEnum rawName typeName cases (+ idx 1) len (list-append acc (list ctor))))))

(df emitCDefenum [(e a/EnumNode)] -> String
  :d "Serializes an AST EnumNode into an ISO C99 tagged union architecture."
  (let [(rawName (string-trim (.-name e)))
        (cases (.-cases e))
        (cLen (list-length cases))
        (hasEmptyName? (= rawName ""))
        (hasEmptyCaseName? (hasEmptyCaseNameStep cases 0 cLen))]
    (if (or hasEmptyName? (or hasEmptyCaseName? (<= cLen 0)))
        ""
        (let [(typeName (c99TypeName rawName))
              (upperEnum (c99UpperIdent rawName))
              (tagEnumName (str typeName "Tag"))
              (dataUnionName (str typeName "Data"))
              (tagConstants (emitTagConstantsStep upperEnum cases 0 cLen (list)))
              (tagLines (map formatTagLine tagConstants))
              (tagSection (str "typedef enum {\n" (string-join tagLines ",\n") "\n} " tagEnumName ";\n\n"))
              (casesWithFields (filterCasesWithFieldsStep cases 0 cLen (list)))
              (cwfLen (list-length casesWithFields))
              (unionBody (if (<= cwfLen 0)
                             "    char _unused;\n"
                             (string-join (emitEnumCaseMemberLinesStep rawName typeName casesWithFields 0 cwfLen (list)) "")))
              (unionSection (str "typedef union {\n" unionBody "} " dataUnionName ";\n\n"))
              (tagAliases (string-join (emitCaseTagAliasesStep upperEnum cases 0 cLen (list)) ""))
              (constructors (string-join (emitCaseConstructorsStep upperEnum rawName typeName cases 0 cLen (list)) ""))
              (structSection (str "typedef struct " typeName "_s {\n    " tagEnumName " tag;\n    " dataUnionName " data;\n} " typeName ";\n\n"))]
          (str tagSection tagAliases "\n" unionSection structSection constructors)))))
