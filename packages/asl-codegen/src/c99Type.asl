(module asl-codegen/c99Type
  :d "ISO C99 Type System Mapping, Memory Layout & Tagged Union Architecture."
  :x [c99PrimitiveType
      c99TypeStr
      emitCDefschema
      emitCDefenum
      emitCStringType
      emitCOptionType
      emitCSliceType
      emitCPairType
      emitCMapType
      emitCResultType
      emitResultConstructors
      collectInsts
      collectInstsFromAnnotation
      emitInstTypedef
      emitInstTypedefs
      emitInstTypedefsFromUniq
      emitInstForwardDecls
      emitInstForwardDeclsFromUniq
      emitInstAccessors
      emitInstAccessorsFromUniq
      collectAllInsts
      dedupeInsts
      c99FromType
      c99TypeName
      c99FieldIdent
      c99UpperIdent
      isC99Keyword?
      isC99NativeType?]
  :i [(ast :a a) (asl-checker/types :a ty) (c99Mangle :a m)])

(df isC99Keyword? [(id String)] -> Bool
  :d "Checks if identifier collides with an ISO C99 reserved keyword."
  (list-contains?
    (list "auto" "break" "case" "char" "const" "continue" "default" "do"
          "double" "else" "enum" "extern" "float" "for" "goto" "if"
          "inline" "int" "long" "register" "restrict" "return" "short" "signed"
          "sizeof" "static" "struct" "switch" "typedef" "union" "unsigned" "void"
          "volatile" "while" "_Bool" "_Complex" "_Imaginary"
          "main" "exit" "abort" "index" "stdin" "stdout" "stderr" "errno" "assert" "offsetof" "NULL" "EOF" "SEEK_SET" "SEEK_CUR" "SEEK_END" "BUFSIZ")
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

(df isC99ReservedMacro? [(id String)] -> Bool
  :d "Checks if an identifier is required by ISO C99 to be a macro, which makes it unusable as a struct member: glibc spells stdout as a self-referential macro and survives by luck, musl spells it (stdout) and a member access becomes a syntax error."
  (list-contains?
    (list "stdin" "stdout" "stderr" "errno" "assert" "offsetof" "NULL"
          "EOF" "SEEK_SET" "SEEK_CUR" "SEEK_END" "BUFSIZ")
    id))

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
    (if (or (isC99Keyword? snaked) (isC99ReservedMacro? snaked))
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
      ((or (= name "Any") (= canon "Any")) (some "void*"))
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
            ((= name "Result")
             (if (>= (list-length args) 2)
                 (let [(o (c99FromType (option-or (list-get args 0) (ty/tyCon "Unit" (list) (none) (none)))))
                       (e (c99FromType (option-or (list-get args 1) (ty/tyCon "Unit" (list) (none) (none)))))]
                   (str "AslResult_" (sanitizeCIdent o) "_" (sanitizeCIdent e)))
                 "AslResult"))
            ((= name "Map")
             (if (>= (list-length args) 2)
                 (let [(k (c99FromType (option-or (list-get args 0) (ty/tyCon "Unit" (list) (none) (none)))))
                       (v (c99FromType (option-or (list-get args 1) (ty/tyCon "Unit" (list) (none) (none)))))]
                   (str "AslMap_" (sanitizeCIdent k) "_" (sanitizeCIdent v)))
                 "AslMap_void_void"))
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
             (if (or (string-starts-with? trimmed "AslOption_")
                     (or (string-starts-with? trimmed "AslSlice_")
                         (or (string-starts-with? trimmed "AslPair_")
                             (or (string-starts-with? trimmed "AslMap_")
                                 (string-starts-with? trimmed "AslResult_")))))
                 trimmed
                 (if (string-ends-with? trimmed "*")
                     trimmed
                     (c99FromType (ty/parseTypeStr trimmed (list)))))))))))

(df emitCStringType [] -> String
  :d "Emits standard ISO C99 string slice typedef."
  "#ifndef ASL_STRING_T_DEFINED\n#define ASL_STRING_T_DEFINED\ntypedef struct {\n    const char* data;\n    size_t len;\n} asl_string_t;\n#endif\n")

(df guardTypedef [(name String) (body String)] -> String
  :d "Wraps a container typedef in an include guard so the host runtime header and the emitter can both provide it."
  (str "#ifndef " name "_DEFINED\n#define " name "_DEFINED\n" body "#endif\n"))

(df emitCOptionType [(innerType String)] -> String
  :d "Emits an ISO C99 Option container typedef as a tagged union, matching the representation the match lowering reads."
  (let [(cTy (c99TypeStr innerType))
        (optName (str "AslOption_" (sanitizeCIdent cTy)))]
    (if (= cTy "void")
        (str "#ifndef " optName "_DEFINED\n#define " optName "_DEFINED\n#ifndef " optName "_FWD_DEFINED\n#define " optName "_FWD_DEFINED\nstruct " optName "_s;\ntypedef struct " optName "_s " optName ";\n#endif\nstruct " optName "_s {\n    bool tag;\n};\n#endif\n")
        (str "#ifndef " optName "_DEFINED\n#define " optName "_DEFINED\n#ifndef " optName "_FWD_DEFINED\n#define " optName "_FWD_DEFINED\nstruct " optName "_s;\ntypedef struct " optName "_s " optName ";\n#endif\nstruct " optName "_s {\n    bool tag;\n    union {\n        " cTy " some;\n    } data;\n};\n#endif\n"))))

(df emitCSliceType [(elemType String)] -> String
  :d "Emits an ISO C99 List/Slice container typedef for a given element type."
  (let [(cTy (c99TypeStr elemType))
        (sliceName (str "AslSlice_" (sanitizeCIdent cTy)))]
    (guardTypedef sliceName
      (if (= cTy "void")
          (str "typedef struct {\n    const void* items;\n    size_t count;\n} " sliceName ";\n")
          (str "typedef struct {\n    " cTy "* items;\n    size_t count;\n} " sliceName ";\n")))))

(df emitCPairType [(firstType String) (secondType String)] -> String
  :d "Emits an ISO C99 Pair container typedef for a given pair of component types."
  (let [(aTy (c99TypeStr firstType))
        (bTy (c99TypeStr secondType))
        (pairName (str "AslPair_" (sanitizeCIdent aTy) "_" (sanitizeCIdent bTy)))]
    (str "#ifndef " pairName "_DEFINED\n#define " pairName "_DEFINED\n#ifndef " pairName "_FWD_DEFINED\n#define " pairName "_FWD_DEFINED\nstruct " pairName "_s;\ntypedef struct " pairName "_s " pairName ";\n#endif\nstruct " pairName "_s {\n    " aTy " first;\n    " bTy " second;\n};\n#endif\n")))

(df emitCMapType [(keyType String) (valType String)] -> String
  :d "Emits an ISO C99 Map container typedef as a flat association vector of key and value pairs."
  (let [(kTy (c99TypeStr keyType))
        (vTy (c99TypeStr valType))
        (pairName (str "AslPair_" (sanitizeCIdent kTy) "_" (sanitizeCIdent vTy)))
        (mapName (str "AslMap_" (sanitizeCIdent kTy) "_" (sanitizeCIdent vTy)))]
    (str "#ifndef " mapName "_DEFINED\n#define " mapName "_DEFINED\n#ifndef " mapName "_FWD_DEFINED\n#define " mapName "_FWD_DEFINED\nstruct " mapName "_s;\ntypedef struct " mapName "_s " mapName ";\n#endif\nstruct " mapName "_s {\n    " pairName "* entries;\n    size_t count;\n};\n#endif\n")))

(df emitCResultType [(okType String) (errType String)] -> String
  :d "Emits an ISO C99 Result container typedef as a tagged union, so a Result can carry a value of any type instead of the type-erased void* the host header offered."
  (let [(oTy (c99TypeStr okType))
        (eTy (c99TypeStr errType))
        (resName (str "AslResult_" (sanitizeCIdent oTy) "_" (sanitizeCIdent eTy)))
        (okMember (if (= oTy "void") "" (str "        " oTy " ok;\n")))
        (errMember (if (= eTy "void") "" (str "        " eTy " err;\n")))]
    (if (and (= oTy "void") (= eTy "void"))
        (str "#ifndef " resName "_DEFINED\n#define " resName "_DEFINED\n#ifndef " resName "_FWD_DEFINED\n#define " resName "_FWD_DEFINED\nstruct " resName "_s;\ntypedef struct " resName "_s " resName ";\n#endif\nstruct " resName "_s {\n    bool tag;\n};\n#endif\n")
        (str "#ifndef " resName "_DEFINED\n#define " resName "_DEFINED\n#ifndef " resName "_FWD_DEFINED\n#define " resName "_FWD_DEFINED\nstruct " resName "_s;\ntypedef struct " resName "_s " resName ";\n#endif\nstruct " resName "_s {\n    bool tag;\n    union {\n" okMember errMember "    } data;\n};\n#endif\n"))))

(df emitResultConstructors [(okType String) (errType String)] -> String
  :d "Emits the per-instantiation Result constructors, because a generic ok or err cannot be written once in ISO C99 without discarding its argument."
  (let [(oTy (c99TypeStr okType))
        (eTy (c99TypeStr errType))
        (resName (str "AslResult_" (sanitizeCIdent oTy) "_" (sanitizeCIdent eTy)))]
    (str (if (= oTy "void")
             (str "static inline " resName " asl_ok_" resName "(void) {\n    " resName " r;\n    r.tag = ASL_TAG_OK;\n    return r;\n}\n")
             (str "static inline " resName " asl_ok_" resName "(" oTy " v) {\n    " resName " r;\n    r.tag = ASL_TAG_OK;\n    r.data.ok = v;\n    return r;\n}\n"))
         (if (= eTy "void")
             (str "static inline " resName " asl_err_" resName "(void) {\n    " resName " r;\n    r.tag = ASL_TAG_ERR;\n    return r;\n}\n")
             (str "static inline " resName " asl_err_" resName "(" eTy " v) {\n    " resName " r;\n    r.tag = ASL_TAG_ERR;\n    r.data.err = v;\n    return r;\n}\n")))))

(df isContainerCon? [(name String)] -> Bool
  :d "Checks whether a type constructor is a generic container needing an emitted instantiation typedef."
  (or (= name "Option") (or (= name "List") (or (= name "Pair") (or (= name "Map") (= name "Result"))))))

(df mapEntryPair [(args (List ty/Type))] -> ty/Type
  :d "Builds the Pair instantiation a Map's entry vector is made of, so the pair typedef is registered before the map."
  (let [(unitTy (ty/tyCon "Unit" (list) (none) (none)))
        (k (option-or (list-get args 0) unitTy))
        (v (option-or (list-get args 1) unitTy))]
    (ty/tyCon "Pair" (list k v) (none) (none))))

(df collectInstStep [(args (List ty/Type)) (idx Int64) (len Int64) (acc (List ty/Type))] -> (List ty/Type)
  :d "Folds instantiation collection across a constructor argument list."
  (if (>= idx len)
      acc
      (let [(a (option-or (list-get args idx) (ty/tyCon "Unit" (list) (none) (none))))
            (acc2 (collectInsts a acc))]
        (collectInstStep args (+ idx 1) len acc2))))

(df collectInsts [(t ty/Type) (acc (List ty/Type))] -> (List ty/Type)
  :d "Collects generic container instantiations from a type, components before composites so emission order is dependency order."
  (mt t
    ((ty/tyVar id kind) acc)
    ((ty/tyFun params ret) acc)
    ((ty/tyCon name args modOpt shownOpt)
     (let [(acc2 (collectInstStep args 0 (list-length args) acc))
           (acc3 (if (and (= name "Map") (>= (list-length args) 2))
                     (list-append acc2 (list (mapEntryPair args)))
                     acc2))
           (acc4 (if (and (= name "List") (>= (list-length args) 1))
                     (list-append acc3 (list (ty/tyCon "Option" (list (option-or (list-get args 0) (ty/tyCon "Unit" (list) (none) (none)))) (none) (none))
                                             (ty/tyCon "Option" (list t) (none) (none))))
                     acc3))]
       (if (isContainerCon? name)
           (list-append acc4 (list t))
           acc4)))))

(df collectInstsFromAnnotation [(annotation String) (acc (List ty/Type))] -> (List ty/Type)
  :d "Parses a type annotation and collects the container instantiations it mentions."
  (let [(trimmed (string-trim annotation))]
    (if (or (= trimmed "") (isC99NativeType? trimmed))
        acc
        (collectInsts (ty/parseTypeStr trimmed (list)) acc))))

(df emitInstTypedef [(t ty/Type)] -> String
  :d "Emits the guarded typedef for one collected container instantiation."
  (mt t
    ((ty/tyVar id kind) "")
    ((ty/tyFun params ret) "")
    ((ty/tyCon name args modOpt shownOpt)
     (let [(unitTy (ty/tyCon "Unit" (list) (none) (none)))]
       (cond
         ((= name "Option") (emitCOptionType (c99FromType (option-or (list-get args 0) unitTy))))
         ((= name "List") (emitCSliceType (c99FromType (option-or (list-get args 0) unitTy))))
         ((= name "Pair") (emitCPairType (c99FromType (option-or (list-get args 0) unitTy))
                                         (c99FromType (option-or (list-get args 1) unitTy))))
         ((= name "Result") (emitCResultType (c99FromType (option-or (list-get args 0) unitTy))
                                            (c99FromType (option-or (list-get args 1) unitTy))))
         ((= name "Map") (emitCMapType (c99FromType (option-or (list-get args 0) unitTy))
                                       (c99FromType (option-or (list-get args 1) unitTy))))
         (:else ""))))))

(df dedupeInstsStep [(insts (List ty/Type)) (idx Int64) (len Int64) (seen (Map String Bool)) (acc (List ty/Type))] -> (List ty/Type)
  :d "Drops repeated instantiations by emitted C name while preserving first-seen order."
  (if (>= idx len)
      (list-reverse acc)
      (let [(t (option-or (list-get insts idx) (ty/tyCon "Unit" (list) (none) (none))))
            (cname (c99FromType t))]
        (if (map-has? seen cname)
            (dedupeInstsStep insts (+ idx 1) len seen acc)
            (dedupeInstsStep insts (+ idx 1) len (map-set seen cname true) (list-cons t acc))))))

(df dedupeInsts [(insts (List ty/Type))] -> (List ty/Type)
  :d "Deduplicates collected instantiations by their emitted C type name."
  (dedupeInstsStep insts 0 (list-length insts) (map-empty) (list)))

(df collectParamInsts [(ps (List a/Param)) (idx Int64) (len Int64) (acc (List ty/Type))] -> (List ty/Type)
  :d "Collects container instantiations mentioned by a parameter list."
  (if (>= idx len)
      acc
      (let [(p (option-or (list-get ps idx) (a/Param :name "" :type "Unit")))]
        (collectParamInsts ps (+ idx 1) len (collectInstsFromAnnotation (.-type p) acc)))))

(df collectFieldInsts [(fs (List a/AstField)) (idx Int64) (len Int64) (acc (List ty/Type))] -> (List ty/Type)
  :d "Collects container instantiations mentioned by a schema field list."
  (if (>= idx len)
      acc
      (let [(f (option-or (list-get fs idx) (a/AstField :name "" :type "Unit" :docstring "" :default (none) :json (none))))]
        (collectFieldInsts fs (+ idx 1) len (collectInstsFromAnnotation (.-type f) acc)))))

(df collectCaseInsts [(cs (List a/EnumCase)) (idx Int64) (len Int64) (acc (List ty/Type))] -> (List ty/Type)
  :d "Collects container instantiations mentioned by enum case payloads."
  (if (>= idx len)
      acc
      (let [(c (option-or (list-get cs idx) (a/EnumCase :name "" :fields (list) :docstring "")))
            (acc2 (collectParamInsts (.-fields c) 0 (list-length (.-fields c)) acc))]
        (collectCaseInsts cs (+ idx 1) len acc2))))

(df collectFormInsts [(forms (List a/TopForm)) (idx Int64) (len Int64) (acc (List ty/Type))] -> (List ty/Type)
  :d "Collects every container instantiation reachable from the top-level forms of a translation unit."
  (if (>= idx len)
      acc
      (let [(form (option-or (list-get forms idx) (a/topModule (a/ModuleNode :path "" :docstring "" :exported (list) :imports (list) :defs (list)))))
            (acc2 (mt form
                    ((a/topModule node) acc)
                    ((a/topSchema node) (collectFieldInsts (.-fields node) 0 (list-length (.-fields node)) acc))
                    ((a/topEnum node) (collectCaseInsts (.-cases node) 0 (list-length (.-cases node)) acc))
                    ((a/topDefun node)
                     (let [(withParams (collectParamInsts (.-params node) 0 (list-length (.-params node)) acc))]
                       (collectInstsFromAnnotation (.-retType node) withParams)))))]
        (collectFormInsts forms (+ idx 1) len acc2))))

(df collectAllInsts [(forms (List a/TopForm))] -> (List ty/Type)
  :d "Collects every container instantiation reachable from forms."
  (collectFormInsts forms 0 (list-length forms) (list)))

(df emitSliceAccessors [(elemC String)] -> String
  :d "Emits the per-instantiation container operations a generic accessor needs, because ISO C99 has no way to express one over all element types."
  (let [(sliceName (str "AslSlice_" (sanitizeCIdent elemC)))
        (optName (str "AslOption_" (sanitizeCIdent elemC)))]
    (str "#ifndef asl_list_get_" sliceName "_DEFINED\n#define asl_list_get_" sliceName "_DEFINED\n"
         "static inline " optName " asl_list_get_" sliceName "(" sliceName " s, int64_t i) {\n"
         "    " optName " o;\n"
         "    if (i < 0 || (size_t)i >= s.count) { o.tag = ASL_TAG_NONE; return o; }\n"
         "    o.tag = ASL_TAG_SOME;\n"
         "    o.data.some = s.items[i];\n"
         "    return o;\n"
         "}\n"
         "#endif\n"
         "#ifndef asl_list_head_" sliceName "_DEFINED\n#define asl_list_head_" sliceName "_DEFINED\n"
         "static inline " optName " asl_list_head_" sliceName "(" sliceName " s) {\n"
         "    return asl_list_get_" sliceName "(s, 0);\n"
         "}\n"
         "#endif\n"
         "#ifndef asl_list_tail_" sliceName "_DEFINED\n#define asl_list_tail_" sliceName "_DEFINED\n"
         "static inline AslOption_" (sanitizeCIdent sliceName) " asl_list_tail_" sliceName "(" sliceName " s) {\n"
         "    AslOption_" (sanitizeCIdent sliceName) " o;\n"
         "    " sliceName " r;\n"
         "    if (s.count == 0) { o.tag = ASL_TAG_NONE; return o; }\n"
         "    r.items = s.items + 1;\n"
         "    r.count = s.count - 1;\n"
         "    o.tag = ASL_TAG_SOME;\n"
         "    o.data.some = r;\n"
         "    return o;\n"
         "}\n"
         "#endif\n"
         "static inline " elemC " asl_option_or_" optName "(" optName " o, " elemC " d) {\n"
         "    if (o.tag == ASL_TAG_SOME) { return o.data.some; }\n"
         "    return d;\n"
         "}\n"
         "static inline " optName " asl_some_" optName "(" elemC " v) {\n"
         "    " optName " o;\n"
         "    o.tag = ASL_TAG_SOME;\n"
         "    o.data.some = v;\n"
         "    return o;\n"
         "}\n"
         "static inline " optName " asl_none_" optName "(void) {\n"
         "    " optName " o;\n"
         "    o.tag = ASL_TAG_NONE;\n"
         "    return o;\n"
         "}\n")))

(df emitMapAccessors [(keyC String) (valC String)] -> String
  :d "Emits typed map operations for a specific key and value type."
  (let [(mapName (str "AslMap_" (sanitizeCIdent keyC) "_" (sanitizeCIdent valC)))
        (pairName (str "AslPair_" (sanitizeCIdent keyC) "_" (sanitizeCIdent valC)))
        (optVal (str "AslOption_" (sanitizeCIdent valC)))
        (sliceVal (str "AslSlice_" (sanitizeCIdent valC)))
        (sliceKey (str "AslSlice_" (sanitizeCIdent keyC)))
        (isKeyStr (= keyC "asl_string_t"))
        (eqExpr (if isKeyStr "asl_string_eq(m.entries[i].first, key)" "m.entries[i].first == key"))]
    (str
      "#ifndef asl_map_get_" mapName "_DEFINED\n#define asl_map_get_" mapName "_DEFINED\n"
      "static inline " optVal " asl_map_get_" mapName "(" mapName " m, " keyC " key) {\n"
      "    " optVal " o;\n"
      "    for (size_t i = 0; i < m.count; ++i) {\n"
      "        if (" eqExpr ") { o.tag = ASL_TAG_SOME; o.data.some = m.entries[i].second; return o; }\n"
      "    }\n"
      "    o.tag = ASL_TAG_NONE; return o;\n"
      "}\n"
      "#endif\n"
      "#ifndef asl_map_has_" mapName "_DEFINED\n#define asl_map_has_" mapName "_DEFINED\n"
      "static inline bool asl_map_has_" mapName "(" mapName " m, " keyC " key) {\n"
      "    for (size_t i = 0; i < m.count; ++i) {\n"
      "        if (" eqExpr ") return true;\n"
      "    }\n"
      "    return false;\n"
      "}\n"
      "#endif\n"
      "#ifndef asl_map_values_" mapName "_DEFINED\n#define asl_map_values_" mapName "_DEFINED\n"
      "static inline " sliceVal " asl_map_values_" mapName "(" mapName " m) {\n"
      "    " sliceVal " s;\n"
      "    s.count = m.count;\n"
      "    if (m.count == 0 || m.entries == NULL) { s.items = NULL; return s; }\n"
      "    s.items = (" valC "*)malloc(sizeof(" valC ") * m.count);\n"
      "    for (size_t i = 0; i < m.count; ++i) { s.items[i] = m.entries[i].second; }\n"
      "    return s;\n"
      "}\n"
      "#endif\n"
      "#ifndef asl_map_keys_" mapName "_DEFINED\n#define asl_map_keys_" mapName "_DEFINED\n"
      "static inline " sliceKey " asl_map_keys_" mapName "(" mapName " m) {\n"
      "    " sliceKey " s;\n"
      "    s.count = m.count;\n"
      "    if (m.count == 0 || m.entries == NULL) { s.items = NULL; return s; }\n"
      "    s.items = (" keyC "*)malloc(sizeof(" keyC ") * m.count);\n"
      "    for (size_t i = 0; i < m.count; ++i) { s.items[i] = m.entries[i].first; }\n"
      "    return s;\n"
      "}\n"
      "#endif\n"
      "#ifndef asl_map_set_" mapName "_DEFINED\n#define asl_map_set_" mapName "_DEFINED\n"
      "static inline " mapName " asl_map_set_" mapName "(" mapName " m, " keyC " key, " valC " val) {\n"
      "    for (size_t i = 0; i < m.count; ++i) {\n"
      "        if (" eqExpr ") {\n"
      "            " pairName "* ent = (" pairName "*)malloc(sizeof(" pairName ") * m.count);\n"
      "            memcpy(ent, m.entries, sizeof(" pairName ") * m.count);\n"
      "            ent[i].second = val;\n"
      "            " mapName " r; r.entries = ent; r.count = m.count; return r;\n"
      "        }\n"
      "    }\n"
      "    size_t nc = m.count + 1;\n"
      "    " pairName "* ent = (" pairName "*)malloc(sizeof(" pairName ") * nc);\n"
      "    if (m.count > 0 && m.entries != NULL) { memcpy(ent, m.entries, sizeof(" pairName ") * m.count); }\n"
      "    ent[m.count].first = key; ent[m.count].second = val;\n"
      "    " mapName " r; r.entries = ent; r.count = nc; return r;\n"
      "}\n"
      "#endif\n")))

(df isSliceInst? [(t ty/Type)] -> Bool
  :d "Checks whether an instantiation is a pointer-backed container (List or Map)."
  (mt t
    ((ty/tyVar id kind) false)
    ((ty/tyFun params ret) false)
    ((ty/tyCon name args modOpt shownOpt) (or (= name "List") (= name "Map")))))

(df emitInstTypedefsStep [(insts (List ty/Type)) (idx Int64) (len Int64) (wantSlices Bool) (acc (List String))] -> (List String)
  :d "Renders the deduplicated instantiation typedefs of one wave in dependency order."
  (if (>= idx len)
      acc
      (let [(t (option-or (list-get insts idx) (ty/tyCon "Unit" (list) (none) (none))))
            (line (if (= (isSliceInst? t) wantSlices) (emitInstTypedef t) ""))]
        (emitInstTypedefsStep insts (+ idx 1) len wantSlices
                              (if (= line "") acc (list-append acc (list line)))))))

(df emitInstForwardDecl [(t ty/Type)] -> String
  :d "Emits forward declaration for an instantiation struct."
  (mt t
    ((ty/tyVar id kind) "")
    ((ty/tyFun params ret) "")
    ((ty/tyCon name args modOpt shownOpt)
     (let [(cTy (c99FromType t))]
       (if (or (string-starts-with? cTy "AslPair_")
               (or (string-starts-with? cTy "AslMap_")
                   (or (string-starts-with? cTy "AslOption_")
                       (string-starts-with? cTy "AslResult_"))))
           (str "#ifndef " cTy "_DEFINED\n#ifndef " cTy "_FWD_DEFINED\n#define " cTy "_FWD_DEFINED\nstruct " cTy "_s;\ntypedef struct " cTy "_s " cTy ";\n#endif\n#endif\n")
           "")))))

(df emitInstForwardDeclsStep [(insts (List ty/Type)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Emits forward declarations for all generic containers."
  (if (>= idx len)
      acc
      (let [(t (option-or (list-get insts idx) (ty/tyCon "Unit" (list) (none) (none))))
            (decl (emitInstForwardDecl t))]
        (emitInstForwardDeclsStep insts (+ idx 1) len
                                  (if (= decl "") acc (list-append acc (list decl)))))))

(df emitInstForwardDeclsFromUniq [(uniq (List ty/Type))] -> String
  :d "Emits forward declarations for pre-deduplicated generic containers."
  (let [(lines (emitInstForwardDeclsStep uniq 0 (list-length uniq) (list)))]
    (string-join lines "")))

(df emitInstForwardDecls [(forms (List a/TopForm))] -> String
  :d "Emits forward declarations for all generic containers reachable from top-level forms."
  (let [(raw (collectFormInsts forms 0 (list-length forms) (list)))
        (uniq (dedupeInsts raw))]
    (emitInstForwardDeclsFromUniq uniq)))

(df emitInstAccessorsStep [(insts (List ty/Type)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Renders the per-instantiation container accessors for every collected slice."
  (if (>= idx len)
      acc
      (let [(t (option-or (list-get insts idx) (ty/tyCon "Unit" (list) (none) (none))))
            (unitTy (ty/tyCon "Unit" (list) (none) (none)))
            (line (mt t
                    ((ty/tyVar i k) "")
                    ((ty/tyFun p r) "")
                    ((ty/tyCon n args m s)
                     (cond
                       ((= n "List")
                        (let [(elemC (c99FromType (option-or (list-get args 0) unitTy)))]
                          (if (= elemC "void") "" (emitSliceAccessors elemC))))
                       ((and (= n "Map") (>= (list-length args) 2))
                        (emitMapAccessors (c99FromType (option-or (list-get args 0) unitTy))
                                          (c99FromType (option-or (list-get args 1) unitTy))))
                       ((and (= n "Result") (>= (list-length args) 2))
                        (emitResultConstructors (c99FromType (option-or (list-get args 0) unitTy))
                                                (c99FromType (option-or (list-get args 1) unitTy))))
                       (:else "")))))]
        (emitInstAccessorsStep insts (+ idx 1) len
                               (if (= line "") acc (list-append acc (list line)))))))

(df emitInstAccessorsFromUniq [(uniq (List ty/Type))] -> String
  :d "Emits container operations for pre-deduplicated generic containers."
  (let [(lines (emitInstAccessorsStep uniq 0 (list-length uniq) (list)))]
    (string-join lines "")))

(df emitInstAccessors [(forms (List a/TopForm))] -> String
  :d "Emits the container operations that cannot be written once in ISO C99 and so must exist per instantiation."
  (let [(raw (collectFormInsts forms 0 (list-length forms) (list)))
        (uniq (dedupeInsts raw))]
    (emitInstAccessorsFromUniq uniq)))

(df emitInstTypedefsFromUniq [(uniq (List ty/Type)) (wantSlices Bool)] -> String
  :d "Emits one wave of generic container typedefs from pre-deduplicated instantiations."
  (let [(lines (emitInstTypedefsStep uniq 0 (list-length uniq) wantSlices (list)))]
    (string-join lines "")))

(df emitInstTypedefs [(forms (List a/TopForm)) (wantSlices Bool)] -> String
  :d "Emits one wave of generic container typedefs: slices store elements behind a pointer so they precede the record definitions, while Option and Pair store by value and must follow them."
  (let [(raw (collectFormInsts forms 0 (list-length forms) (list)))
        (uniq (dedupeInsts raw))]
    (emitInstTypedefsFromUniq uniq wantSlices)))

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

(df emitSchemaFieldTypedefs [(fields (List a/AstField))] -> String
  :d "Emits container typedefs for any field types needed by a schema."
  (let [(insts (collectFieldInsts fields 0 (list-length fields) (list)))
        (uniq (dedupeInsts insts))
        (lines (emitInstTypedefsStep uniq 0 (list-length uniq) false (list)))]
    (string-join lines "")))

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
          (str "#ifndef " typeName "_DEFINED\n#define " typeName "_DEFINED\n#ifndef " typeName "_FWD_DEFINED\n#define " typeName "_FWD_DEFINED\nstruct " typeName "_s;\ntypedef struct " typeName "_s " typeName ";\n#endif\nstruct " typeName "_s {\n" bodyStrs "};\n#endif\n")))))

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
                     typeName
                     (c99TypeStr rawTy)))
            (entry (str pTy " " pName))]
        (emitConstructorParamsStep rawName typeName params (+ idx 1) len (list-append acc (list entry))))))

(df emitConstructorAssignsStep [(rawName String) (typeName String) (cMember String) (params (List a/Param)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Formats payload field assignments for enum case constructor."
  (if (>= idx len)
      acc
      (let [(p (option-or (list-get params idx) (a/Param :name "" :type "Unit")))
            (pName (c99FieldIdent (.-name p)))
            (rawTy (.-type p))
            (line (if (or (= rawTy rawName) (= rawTy typeName))
                      (str "    _res.data." cMember "." pName " = (struct " typeName "_s*)malloc(sizeof(struct " typeName "_s));\n    *_res.data." cMember "." pName " = " pName ";\n")
                      (str "    _res.data." cMember "." pName " = " pName ";\n")))]
        (emitConstructorAssignsStep rawName typeName cMember params (+ idx 1) len (list-append acc (list line))))))

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
              (assignLines (emitConstructorAssignsStep rawName typeName cMember pList 0 pLen (list)))]
          (str "static inline " typeName " " fnName "(" paramStr ") {\n    " typeName " _res;\n    memset(&_res, 0, sizeof(_res));\n    _res.tag = " tagConst ";\n" (string-join assignLines "") "    return _res;\n}\n\n")))))

(df emitCaseConstructorsStep [(upperEnum String) (rawName String) (typeName String) (cases (List a/EnumCase)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Accumulates constructor functions for all enum cases."
  (if (>= idx len)
      acc
      (let [(c (option-or (list-get cases idx) (a/EnumCase :name "" :fields (list))))
            (ctor (emitCaseConstructor upperEnum rawName typeName c))]
        (emitCaseConstructorsStep upperEnum rawName typeName cases (+ idx 1) len (list-append acc (list ctor))))))

(df emitEnumCaseTypedefs [(cases (List a/EnumCase))] -> String
  :d "Emits container typedefs for any payload field types needed by an enum."
  (let [(insts (collectCaseInsts cases 0 (list-length cases) (list)))
        (uniq (dedupeInsts insts))
        (lines (emitInstTypedefsStep uniq 0 (list-length uniq) false (list)))]
    (string-join lines "")))

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
              (structSection (str "#ifndef " typeName "_DEFINED\n#define " typeName "_DEFINED\n#ifndef " typeName "_FWD_DEFINED\n#define " typeName "_FWD_DEFINED\nstruct " typeName "_s;\ntypedef struct " typeName "_s " typeName ";\n#endif\nstruct " typeName "_s {\n    " tagEnumName " tag;\n    " dataUnionName " data;\n};\n#endif\n\n"))]
          (str tagSection tagAliases "\n" unionSection structSection constructors)))))
