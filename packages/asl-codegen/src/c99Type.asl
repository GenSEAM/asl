(module asl-codegen/c99Type :x [c99PrimitiveType c99TypeStr emitCDefschema emitCDefenum emitCStringType emitCOptionType emitCSliceType emitCPairType emitCMapType emitCResultType emitResultConstructors collectInsts collectInstsFromAnnotation emitInstTypedef emitInstTypedefs emitInstTypedefsFromUniq emitInstForwardDecls emitInstForwardDeclsFromUniq emitInstAccessors emitInstAccessorsFromUniq collectAllInsts dedupeInsts c99FromType c99TypeName c99FieldIdent c99UpperIdent isC99Keyword? isC99NativeType?] :i [(ast :a a) (asl-checker/types :a ty) (c99Mangle :a m)])

fn isC99Keyword? id: String -> Bool
  (listContains? (list "auto" "break" "case" "char" "const" "continue" "default" "do" "double" "else" "enum" "extern" "float" "for" "goto" "if" "inline" "int" "long" "register" "restrict" "return" "short" "signed" "sizeof" "static" "struct" "switch" "typedef" "union" "unsigned" "void" "volatile" "while" "_Bool" "_Complex" "_Imaginary" "main" "exit" "abort" "index" "stdin" "stdout" "stderr" "errno" "assert" "offsetof" "NULL" "EOF" "SEEK_SET" "SEEK_CUR" "SEEK_END" "BUFSIZ") id)

fn isC99NativeType? s: String -> Bool
  (listContains? (list "int64_t" "int32_t" "int16_t" "int8_t" "uint64_t" "uint32_t" "uint16_t" "uint8_t" "double" "float" "bool" "void" "size_t" "asl_string_t" "const char*" "char*" "char" "int" "long" "short" "unsigned int") s)

fn isC99ReservedMacro? id: String -> Bool
  (listContains? (list "stdin" "stdout" "stderr" "errno" "assert" "offsetof" "NULL" "EOF" "SEEK_SET" "SEEK_CUR" "SEEK_END" "BUFSIZ") id)

fn c99FieldIdent s: String -> String
  (let [(sLen (stringLength s)) (base1 (if (and (> sLen 1) (stringEndsWith? s "?")) (if (stringStartsWith? s "is-") (m/sliceOr s 0 (- sLen 1) "") (str "is-" (m/sliceOr s 0 (- sLen 1) ""))) s)) (len1 (stringLength base1)) (base2 (if (and (> len1 1) (stringEndsWith? base1 "!")) (str (m/sliceOr base1 0 (- len1 1) "") "-mut") base1)) (snaked (stringReplace (stringReplace base2 "-" "_") "/" "_"))] (if (or (isC99Keyword? snaked) (isC99ReservedMacro? snaked)) (str "asl_" snaked) snaked))

fn c99UpperIdent s: String -> String
  (let [(sLen (stringLength s)) (base1 (if (and (> sLen 1) (stringEndsWith? s "?")) (m/sliceOr s 0 (- sLen 1) "") s)) (len1 (stringLength base1)) (base2 (if (and (> len1 1) (stringEndsWith? base1 "!")) (m/sliceOr base1 0 (- len1 1) "") base1)) (s3 (stringReplace base2 "-" "_")) (s4 (stringReplace s3 "." "_")) (s5 (stringReplace s4 "/" "_"))] (stringUpper s5))

fn c99TypeName s: String -> String
  (cond ((or (= s "Int64") (= s "I64") (= s "Int")) "int64_t") ((or (= s "Int32") (= s "I32")) "int32_t") ((or (= s "Float64") (= s "F64") (= s "Float") (= s "Num")) "double") ((or (= s "Float32") (= s "F32")) "float") ((= s "Bool") "bool") ((or (= s "Unit") (= s "void")) "void") ((or (= s "String") (= s "Str")) "asl_string_t") (else (let [(pascal (m/pascalIdent s))] (if (stringStartsWith? pascal "Asl") pascal (str "Asl" pascal)))))

fn sanitizeCIdent s: String -> String
  (let [(s1 (stringReplace s "*" "_ptr")) (s2 (stringReplace s1 " " "_")) (s3 (stringReplace s2 "-" "_")) (s4 (stringReplace s3 "(" "")) (s5 (stringReplace s4 ")" ""))] s5)

fn c99PrimitiveType name: String -> (Option String)
  (let [(canon (ty/resolveTypeAlias name))] (cond ((or (= name "Int64") (= name "I64") (= name "Int") (= canon "Int64")) (some "int64_t")) ((or (= name "Int32") (= name "I32") (= canon "Int32")) (some "int32_t")) ((or (= name "Float32") (= name "F32")) (some "float")) ((or (= name "Float64") (= name "F64") (= name "Float") (= name "Num") (= canon "Float64")) (some "double")) ((or (= name "Bool") (= canon "Bool")) (some "bool")) ((or (= name "Unit") (= canon "Unit")) (some "void")) ((or (= name "Any") (= canon "Any")) (some "void*")) ((or (= name "String") (= name "Str") (= canon "String")) (some "asl_string_t")) (else (none))))

fn c99FromType t: ty/Type -> String
  (mt t ((ty/tyVar id kind) (cond ((= kind "int") "int64_t") ((= kind "num") "double") (else "void*"))) ((ty/tyFun params ret) "void*") ((ty/tyCon name args modOpt shownOpt) (let [(prim (c99PrimitiveType name))] (mt prim ((some p) p) ((none) (cond ((= name "Option") (if (> (listLength args) 0) (let [(inner (c99FromType (optionOr (listGet args 0) (ty/tyCon "Unit" (list) (none) (none)))))] (str "AslOption_" (sanitizeCIdent inner))) "AslOption_void")) ((= name "List") (if (> (listLength args) 0) (let [(inner (c99FromType (optionOr (listGet args 0) (ty/tyCon "Unit" (list) (none) (none)))))] (str "AslSlice_" (sanitizeCIdent inner))) "AslSlice_void")) ((= name "Pair") (if (>= (listLength args) 2) (let [(a (c99FromType (optionOr (listGet args 0) (ty/tyCon "Unit" (list) (none) (none))))) (b (c99FromType (optionOr (listGet args 1) (ty/tyCon "Unit" (list) (none) (none)))))] (str "AslPair_" (sanitizeCIdent a) "_" (sanitizeCIdent b))) "AslPair_void_void")) ((= name "Result") (if (>= (listLength args) 2) (let [(o (c99FromType (optionOr (listGet args 0) (ty/tyCon "Unit" (list) (none) (none))))) (e (c99FromType (optionOr (listGet args 1) (ty/tyCon "Unit" (list) (none) (none)))))] (str "AslResult_" (sanitizeCIdent o) "_" (sanitizeCIdent e))) "AslResult")) ((= name "Map") (if (>= (listLength args) 2) (let [(k (c99FromType (optionOr (listGet args 0) (ty/tyCon "Unit" (list) (none) (none))))) (v (c99FromType (optionOr (listGet args 1) (ty/tyCon "Unit" (list) (none) (none)))))] (str "AslMap_" (sanitizeCIdent k) "_" (sanitizeCIdent v))) "AslMap_void_void")) (else (c99TypeName name))))))))

fn c99TypeStr s: String -> String
  (let [(trimmed (stringTrim s))] (if (isC99NativeType? trimmed) trimmed (let [(prim (c99PrimitiveType trimmed))] (mt prim ((some p) p) ((none) (if (or (stringStartsWith? trimmed "AslOption_") (or (stringStartsWith? trimmed "AslSlice_") (or (stringStartsWith? trimmed "AslPair_") (or (stringStartsWith? trimmed "AslMap_") (stringStartsWith? trimmed "AslResult_"))))) trimmed (if (stringEndsWith? trimmed "*") trimmed (c99FromType (ty/parseTypeStr trimmed (list))))))))))

fn emitCStringType -> String
  "#ifndef ASL_STRING_T_DEFINED\n#define ASL_STRING_T_DEFINED\ntypedef struct {\n    const char* data;\n    size_t len;\n} asl_string_t;\n#endif\n"

fn guardTypedef name: String body: String -> String
  (str "#ifndef " name "_DEFINED\n#define " name "_DEFINED\n" body "#endif\n")

fn emitCOptionType innerType: String -> String
  (let [(cTy (c99TypeStr innerType)) (optName (str "AslOption_" (sanitizeCIdent cTy)))] (if (= cTy "void") (str "#ifndef " optName "_DEFINED\n#define " optName "_DEFINED\n#ifndef " optName "_FWD_DEFINED\n#define " optName "_FWD_DEFINED\nstruct " optName "_s;\ntypedef struct " optName "_s " optName ";\n#endif\nstruct " optName "_s {\n    bool tag;\n};\n#endif\n") (str "#ifndef " optName "_DEFINED\n#define " optName "_DEFINED\n#ifndef " optName "_FWD_DEFINED\n#define " optName "_FWD_DEFINED\nstruct " optName "_s;\ntypedef struct " optName "_s " optName ";\n#endif\nstruct " optName "_s {\n    bool tag;\n    union {\n        " cTy " some;\n    } data;\n};\n#endif\n")))

fn emitCSliceType elemType: String -> String
  (let [(cTy (c99TypeStr elemType)) (sliceName (str "AslSlice_" (sanitizeCIdent cTy)))] (guardTypedef sliceName (if (= cTy "void") (str "typedef struct {\n    const void* items;\n    size_t count;\n} " sliceName ";\n") (str "typedef struct {\n    " cTy "* items;\n    size_t count;\n} " sliceName ";\n"))))

fn emitCPairType firstType: String secondType: String -> String
  (let [(aTy (c99TypeStr firstType)) (bTy (c99TypeStr secondType)) (pairName (str "AslPair_" (sanitizeCIdent aTy) "_" (sanitizeCIdent bTy)))] (str "#ifndef " pairName "_DEFINED\n#define " pairName "_DEFINED\n#ifndef " pairName "_FWD_DEFINED\n#define " pairName "_FWD_DEFINED\nstruct " pairName "_s;\ntypedef struct " pairName "_s " pairName ";\n#endif\nstruct " pairName "_s {\n    " aTy " first;\n    " bTy " second;\n};\n#endif\n"))

fn emitCMapType keyType: String valType: String -> String
  (let [(kTy (c99TypeStr keyType)) (vTy (c99TypeStr valType)) (pairName (str "AslPair_" (sanitizeCIdent kTy) "_" (sanitizeCIdent vTy))) (mapName (str "AslMap_" (sanitizeCIdent kTy) "_" (sanitizeCIdent vTy)))] (str "#ifndef " mapName "_DEFINED\n#define " mapName "_DEFINED\n#ifndef " mapName "_FWD_DEFINED\n#define " mapName "_FWD_DEFINED\nstruct " mapName "_s;\ntypedef struct " mapName "_s " mapName ";\n#endif\nstruct " mapName "_s {\n    " pairName "* entries;\n    size_t count;\n};\n#endif\n"))

fn emitCResultType okType: String errType: String -> String
  (let [(oTy (c99TypeStr okType)) (eTy (c99TypeStr errType)) (resName (str "AslResult_" (sanitizeCIdent oTy) "_" (sanitizeCIdent eTy))) (okMember (if (= oTy "void") "" (str "        " oTy " ok;\n"))) (errMember (if (= eTy "void") "" (str "        " eTy " err;\n")))] (if (and (= oTy "void") (= eTy "void")) (str "#ifndef " resName "_DEFINED\n#define " resName "_DEFINED\n#ifndef " resName "_FWD_DEFINED\n#define " resName "_FWD_DEFINED\nstruct " resName "_s;\ntypedef struct " resName "_s " resName ";\n#endif\nstruct " resName "_s {\n    bool tag;\n};\n#endif\n") (str "#ifndef " resName "_DEFINED\n#define " resName "_DEFINED\n#ifndef " resName "_FWD_DEFINED\n#define " resName "_FWD_DEFINED\nstruct " resName "_s;\ntypedef struct " resName "_s " resName ";\n#endif\nstruct " resName "_s {\n    bool tag;\n    union {\n" okMember errMember "    } data;\n};\n#endif\n")))

fn emitResultConstructors okType: String errType: String -> String
  (let [(oTy (c99TypeStr okType)) (eTy (c99TypeStr errType)) (resName (str "AslResult_" (sanitizeCIdent oTy) "_" (sanitizeCIdent eTy)))] (str (if (= oTy "void") (str "static inline " resName " asl_ok_" resName "(void) {\n    " resName " r;\n    r.tag = ASL_TAG_OK;\n    return r;\n}\n") (str "static inline " resName " asl_ok_" resName "(" oTy " v) {\n    " resName " r;\n    r.tag = ASL_TAG_OK;\n    r.data.ok = v;\n    return r;\n}\n")) (if (= eTy "void") (str "static inline " resName " asl_err_" resName "(void) {\n    " resName " r;\n    r.tag = ASL_TAG_ERR;\n    return r;\n}\n") (str "static inline " resName " asl_err_" resName "(" eTy " v) {\n    " resName " r;\n    r.tag = ASL_TAG_ERR;\n    r.data.err = v;\n    return r;\n}\n"))))

fn isContainerCon? name: String -> Bool
  (or (= name "Option") (or (= name "List") (or (= name "Pair") (or (= name "Map") (= name "Result")))))

fn mapEntryPair args: (List ty/Type) -> ty/Type
  (let [(unitTy (ty/tyCon "Unit" (list) (none) (none))) (k (optionOr (listGet args 0) unitTy)) (v (optionOr (listGet args 1) unitTy))] (ty/tyCon "Pair" (list k v) (none) (none)))

fn collectInstStep args: (List ty/Type) idx: Int64 len: Int64 acc: (List ty/Type) -> (List ty/Type)
  (if (>= idx len) acc (let [(a (optionOr (listGet args idx) (ty/tyCon "Unit" (list) (none) (none)))) (acc2 (collectInsts a acc))] (collectInstStep args (+ idx 1) len acc2)))

fn collectInsts t: ty/Type acc: (List ty/Type) -> (List ty/Type)
  (mt t ((ty/tyVar id kind) acc) ((ty/tyFun params ret) acc) ((ty/tyCon name args modOpt shownOpt) (let [(acc2 (collectInstStep args 0 (listLength args) acc)) (acc3 (if (and (= name "Map") (>= (listLength args) 2)) (listAppend acc2 (list (mapEntryPair args))) acc2)) (acc4 (if (and (= name "List") (>= (listLength args) 1)) (listAppend acc3 (list (ty/tyCon "Option" (list (optionOr (listGet args 0) (ty/tyCon "Unit" (list) (none) (none)))) (none) (none)) (ty/tyCon "Option" (list t) (none) (none)))) acc3))] (if (isContainerCon? name) (listAppend acc4 (list t)) acc4))))

fn collectInstsFromAnnotation annotation: String acc: (List ty/Type) -> (List ty/Type)
  (let [(trimmed (stringTrim annotation))] (if (or (= trimmed "") (isC99NativeType? trimmed)) acc (collectInsts (ty/parseTypeStr trimmed (list)) acc)))

fn emitInstTypedef t: ty/Type -> String
  (mt t ((ty/tyVar id kind) "") ((ty/tyFun params ret) "") ((ty/tyCon name args modOpt shownOpt) (let [(unitTy (ty/tyCon "Unit" (list) (none) (none)))] (cond ((= name "Option") (emitCOptionType (c99FromType (optionOr (listGet args 0) unitTy)))) ((= name "List") (emitCSliceType (c99FromType (optionOr (listGet args 0) unitTy)))) ((= name "Pair") (emitCPairType (c99FromType (optionOr (listGet args 0) unitTy)) (c99FromType (optionOr (listGet args 1) unitTy)))) ((= name "Result") (emitCResultType (c99FromType (optionOr (listGet args 0) unitTy)) (c99FromType (optionOr (listGet args 1) unitTy)))) ((= name "Map") (emitCMapType (c99FromType (optionOr (listGet args 0) unitTy)) (c99FromType (optionOr (listGet args 1) unitTy)))) (else "")))))

fn dedupeInstsStep insts: (List ty/Type) idx: Int64 len: Int64 seen: (Map String Bool) acc: (List ty/Type) -> (List ty/Type)
  (if (>= idx len) (listReverse acc) (let [(t (optionOr (listGet insts idx) (ty/tyCon "Unit" (list) (none) (none)))) (cname (c99FromType t))] (if (mapHas? seen cname) (dedupeInstsStep insts (+ idx 1) len seen acc) (dedupeInstsStep insts (+ idx 1) len (mapSet seen cname true) (cons t acc)))))

fn dedupeInsts insts: (List ty/Type) -> (List ty/Type)
  (dedupeInstsStep insts 0 (listLength insts) (mapEmpty) (list))

fn collectParamInsts ps: (List a/Param) idx: Int64 len: Int64 acc: (List ty/Type) -> (List ty/Type)
  (if (>= idx len) acc (let [(p (optionOr (listGet ps idx) (a/Param :name "" :type "Unit")))] (collectParamInsts ps (+ idx 1) len (collectInstsFromAnnotation p.type acc))))

fn collectFieldInsts fs: (List a/AstField) idx: Int64 len: Int64 acc: (List ty/Type) -> (List ty/Type)
  (if (>= idx len) acc (let [(f (optionOr (listGet fs idx) (a/AstField :name "" :type "Unit" :docstring "" :default (none) :json (none))))] (collectFieldInsts fs (+ idx 1) len (collectInstsFromAnnotation f.type acc))))

fn collectCaseInsts cs: (List a/EnumCase) idx: Int64 len: Int64 acc: (List ty/Type) -> (List ty/Type)
  (if (>= idx len) acc (let [(c (optionOr (listGet cs idx) (a/EnumCase :name "" :fields (list) :docstring ""))) (acc2 (collectParamInsts c.fields 0 (listLength c.fields) acc))] (collectCaseInsts cs (+ idx 1) len acc2)))

fn collectFormInsts forms: (List a/TopForm) idx: Int64 len: Int64 acc: (List ty/Type) -> (List ty/Type)
  (if (>= idx len) acc (let [(form (optionOr (listGet forms idx) (a/topModule (a/ModuleNode :path "" :docstring "" :exported (list) :imports (list) :defs (list))))) (acc2 (mt form ((a/topModule node) acc) ((a/topSchema node) (collectFieldInsts node.fields 0 (listLength node.fields) acc)) ((a/topEnum node) (collectCaseInsts node.cases 0 (listLength node.cases) acc)) ((a/topDefun node) (let [(withParams (collectParamInsts node.params 0 (listLength node.params) acc))] (collectInstsFromAnnotation node.retType withParams))) ((a/topExpr _) acc)))] (collectFormInsts forms (+ idx 1) len acc2)))

fn collectAllInsts forms: (List a/TopForm) -> (List ty/Type)
  (collectFormInsts forms 0 (listLength forms) (list))

fn emitSliceAccessors elemC: String -> String
  (let [(sliceName (str "AslSlice_" (sanitizeCIdent elemC))) (optName (str "AslOption_" (sanitizeCIdent elemC)))] (str "#ifndef asl_list_get_" sliceName "_DEFINED\n#define asl_list_get_" sliceName "_DEFINED\n" "static inline " optName " asl_list_get_" sliceName "(" sliceName " s, int64_t i) {\n" "    " optName " o;\n" "    if (i < 0 || (size_t)i >= s.count) { o.tag = ASL_TAG_NONE; return o; }\n" "    o.tag = ASL_TAG_SOME;\n" "    o.data.some = s.items[i];\n" "    return o;\n" "}\n" "#endif\n" "#ifndef asl_list_head_" sliceName "_DEFINED\n#define asl_list_head_" sliceName "_DEFINED\n" "static inline " optName " asl_list_head_" sliceName "(" sliceName " s) {\n" "    return asl_list_get_" sliceName "(s, 0);\n" "}\n" "#endif\n" "#ifndef asl_list_tail_" sliceName "_DEFINED\n#define asl_list_tail_" sliceName "_DEFINED\n" "static inline AslOption_" (sanitizeCIdent sliceName) " asl_list_tail_" sliceName "(" sliceName " s) {\n" "    AslOption_" (sanitizeCIdent sliceName) " o;\n" "    " sliceName " r;\n" "    if (s.count == 0) { o.tag = ASL_TAG_NONE; return o; }\n" "    r.items = s.items + 1;\n" "    r.count = s.count - 1;\n" "    o.tag = ASL_TAG_SOME;\n" "    o.data.some = r;\n" "    return o;\n" "}\n" "#endif\n" "static inline " elemC " asl_option_or_" optName "(" optName " o, " elemC " d) {\n" "    if (o.tag == ASL_TAG_SOME) { return o.data.some; }\n" "    return d;\n" "}\n" "static inline " optName " asl_some_" optName "(" elemC " v) {\n" "    " optName " o;\n" "    o.tag = ASL_TAG_SOME;\n" "    o.data.some = v;\n" "    return o;\n" "}\n" "static inline " optName " asl_none_" optName "(void) {\n" "    " optName " o;\n" "    o.tag = ASL_TAG_NONE;\n" "    return o;\n" "}\n"))

fn emitMapAccessors keyC: String valC: String -> String
  (let [(mapName (str "AslMap_" (sanitizeCIdent keyC) "_" (sanitizeCIdent valC))) (pairName (str "AslPair_" (sanitizeCIdent keyC) "_" (sanitizeCIdent valC))) (optVal (str "AslOption_" (sanitizeCIdent valC))) (sliceVal (str "AslSlice_" (sanitizeCIdent valC))) (sliceKey (str "AslSlice_" (sanitizeCIdent keyC))) (isKeyStr (= keyC "asl_string_t")) (eqExpr (if isKeyStr "asl_string_eq(m.entries[i].first, key)" "m.entries[i].first == key"))] (str "#ifndef asl_map_get_" mapName "_DEFINED\n#define asl_map_get_" mapName "_DEFINED\n" "static inline " optVal " asl_map_get_" mapName "(" mapName " m, " keyC " key) {\n" "    " optVal " o;\n" "    for (size_t i = 0; i < m.count; ++i) {\n" "        if (" eqExpr ") { o.tag = ASL_TAG_SOME; o.data.some = m.entries[i].second; return o; }\n" "    }\n" "    o.tag = ASL_TAG_NONE; return o;\n" "}\n" "#endif\n" "#ifndef asl_map_has_" mapName "_DEFINED\n#define asl_map_has_" mapName "_DEFINED\n" "static inline bool asl_map_has_" mapName "(" mapName " m, " keyC " key) {\n" "    for (size_t i = 0; i < m.count; ++i) {\n" "        if (" eqExpr ") return true;\n" "    }\n" "    return false;\n" "}\n" "#endif\n" "#ifndef asl_map_values_" mapName "_DEFINED\n#define asl_map_values_" mapName "_DEFINED\n" "static inline " sliceVal " asl_map_values_" mapName "(" mapName " m) {\n" "    " sliceVal " s;\n" "    s.count = m.count;\n" "    if (m.count == 0 || m.entries == NULL) { s.items = NULL; return s; }\n" "    s.items = (" valC "*)malloc(sizeof(" valC ") * m.count);\n" "    for (size_t i = 0; i < m.count; ++i) { s.items[i] = m.entries[i].second; }\n" "    return s;\n" "}\n" "#endif\n" "#ifndef asl_map_keys_" mapName "_DEFINED\n#define asl_map_keys_" mapName "_DEFINED\n" "static inline " sliceKey " asl_map_keys_" mapName "(" mapName " m) {\n" "    " sliceKey " s;\n" "    s.count = m.count;\n" "    if (m.count == 0 || m.entries == NULL) { s.items = NULL; return s; }\n" "    s.items = (" keyC "*)malloc(sizeof(" keyC ") * m.count);\n" "    for (size_t i = 0; i < m.count; ++i) { s.items[i] = m.entries[i].first; }\n" "    return s;\n" "}\n" "#endif\n" "#ifndef asl_map_set_" mapName "_DEFINED\n#define asl_map_set_" mapName "_DEFINED\n" "static inline " mapName " asl_map_set_" mapName "(" mapName " m, " keyC " key, " valC " val) {\n" "    for (size_t i = 0; i < m.count; ++i) {\n" "        if (" eqExpr ") {\n" "            " pairName "* ent = (" pairName "*)malloc(sizeof(" pairName ") * m.count);\n" "            memcpy(ent, m.entries, sizeof(" pairName ") * m.count);\n" "            ent[i].second = val;\n" "            " mapName " r; r.entries = ent; r.count = m.count; return r;\n" "        }\n" "    }\n" "    size_t nc = m.count + 1;\n" "    " pairName "* ent = (" pairName "*)malloc(sizeof(" pairName ") * nc);\n" "    if (m.count > 0 && m.entries != NULL) { memcpy(ent, m.entries, sizeof(" pairName ") * m.count); }\n" "    ent[m.count].first = key; ent[m.count].second = val;\n" "    " mapName " r; r.entries = ent; r.count = nc; return r;\n" "}\n" "#endif\n"))

fn isSliceInst? t: ty/Type -> Bool
  (mt t ((ty/tyVar id kind) false) ((ty/tyFun params ret) false) ((ty/tyCon name args modOpt shownOpt) (or (= name "List") (= name "Map"))))

fn emitInstTypedefsStep insts: (List ty/Type) idx: Int64 len: Int64 wantSlices: Bool acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(t (optionOr (listGet insts idx) (ty/tyCon "Unit" (list) (none) (none)))) (line (if (= (isSliceInst? t) wantSlices) (emitInstTypedef t) ""))] (emitInstTypedefsStep insts (+ idx 1) len wantSlices (if (= line "") acc (listAppend acc (list line))))))

fn emitInstForwardDecl t: ty/Type -> String
  (mt t ((ty/tyVar id kind) "") ((ty/tyFun params ret) "") ((ty/tyCon name args modOpt shownOpt) (let [(cTy (c99FromType t))] (if (or (stringStartsWith? cTy "AslPair_") (or (stringStartsWith? cTy "AslMap_") (or (stringStartsWith? cTy "AslOption_") (stringStartsWith? cTy "AslResult_")))) (str "#ifndef " cTy "_DEFINED\n#ifndef " cTy "_FWD_DEFINED\n#define " cTy "_FWD_DEFINED\nstruct " cTy "_s;\ntypedef struct " cTy "_s " cTy ";\n#endif\n#endif\n") ""))))

fn emitInstForwardDeclsStep insts: (List ty/Type) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(t (optionOr (listGet insts idx) (ty/tyCon "Unit" (list) (none) (none)))) (decl (emitInstForwardDecl t))] (emitInstForwardDeclsStep insts (+ idx 1) len (if (= decl "") acc (listAppend acc (list decl))))))

fn emitInstForwardDeclsFromUniq uniq: (List ty/Type) -> String
  (let [(lines (emitInstForwardDeclsStep uniq 0 (listLength uniq) (list)))] (stringJoin lines ""))

fn emitInstForwardDecls forms: (List a/TopForm) -> String
  (let [(raw (collectFormInsts forms 0 (listLength forms) (list))) (uniq (dedupeInsts raw))] (emitInstForwardDeclsFromUniq uniq))

fn emitInstAccessorsStep insts: (List ty/Type) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(t (optionOr (listGet insts idx) (ty/tyCon "Unit" (list) (none) (none)))) (unitTy (ty/tyCon "Unit" (list) (none) (none))) (line (mt t ((ty/tyVar i k) "") ((ty/tyFun p r) "") ((ty/tyCon n args m s) (cond ((= n "List") (let [(elemC (c99FromType (optionOr (listGet args 0) unitTy)))] (if (= elemC "void") "" (emitSliceAccessors elemC)))) ((and (= n "Map") (>= (listLength args) 2)) (emitMapAccessors (c99FromType (optionOr (listGet args 0) unitTy)) (c99FromType (optionOr (listGet args 1) unitTy)))) ((and (= n "Result") (>= (listLength args) 2)) (emitResultConstructors (c99FromType (optionOr (listGet args 0) unitTy)) (c99FromType (optionOr (listGet args 1) unitTy)))) (else "")))))] (emitInstAccessorsStep insts (+ idx 1) len (if (= line "") acc (listAppend acc (list line))))))

fn emitInstAccessorsFromUniq uniq: (List ty/Type) -> String
  (let [(lines (emitInstAccessorsStep uniq 0 (listLength uniq) (list)))] (stringJoin lines ""))

fn emitInstAccessors forms: (List a/TopForm) -> String
  (let [(raw (collectFormInsts forms 0 (listLength forms) (list))) (uniq (dedupeInsts raw))] (emitInstAccessorsFromUniq uniq))

fn emitInstTypedefsFromUniq uniq: (List ty/Type) wantSlices: Bool -> String
  (let [(lines (emitInstTypedefsStep uniq 0 (listLength uniq) wantSlices (list)))] (stringJoin lines ""))

fn emitInstTypedefs forms: (List a/TopForm) wantSlices: Bool -> String
  (let [(raw (collectFormInsts forms 0 (listLength forms) (list))) (uniq (dedupeInsts raw))] (emitInstTypedefsFromUniq uniq wantSlices))

fn hasEmptyFieldNameStep fields: (List a/AstField) idx: Int64 len: Int64 -> Bool
  (if (>= idx len) false (let [(f (optionOr (listGet fields idx) (a/AstField :name "" :type "Unit" :docstring "" :default (none) :json (none))))] (if (= (stringTrim f.name) "") true (hasEmptyFieldNameStep fields (+ idx 1) len))))

fn emitSchemaFieldLinesStep rawName: String typeName: String fields: (List a/AstField) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(f (optionOr (listGet fields idx) (a/AstField :name "" :type "Unit" :docstring "" :default (none) :json (none)))) (fName (c99FieldIdent f.name)) (rawTy f.type) (fTy (if (or (= rawTy rawName) (= rawTy typeName)) (str "struct " typeName "_s*") (c99TypeStr rawTy))) (line (str "    " fTy " " fName ";\n"))] (emitSchemaFieldLinesStep rawName typeName fields (+ idx 1) len (listAppend acc (list line)))))

fn hasEmptyCaseNameStep cases: (List a/EnumCase) idx: Int64 len: Int64 -> Bool
  (if (>= idx len) false (let [(c (optionOr (listGet cases idx) (a/EnumCase :name "" :fields (list) :docstring "")))] (if (= (stringTrim c.name) "") true (hasEmptyCaseNameStep cases (+ idx 1) len))))

fn emitTagConstantsStep upperEnum: String cases: (List a/EnumCase) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(c (optionOr (listGet cases idx) (a/EnumCase :name "" :fields (list) :docstring ""))) (cName (str "ASL_" upperEnum "_" (c99UpperIdent c.name)))] (emitTagConstantsStep upperEnum cases (+ idx 1) len (listAppend acc (list cName)))))

fn formatTagLine constName: String -> String
  (str "    " constName)

fn filterCasesWithFieldsStep cases: (List a/EnumCase) idx: Int64 len: Int64 acc: (List a/EnumCase) -> (List a/EnumCase)
  (if (>= idx len) acc (let [(c (optionOr (listGet cases idx) (a/EnumCase :name "" :fields (list) :docstring "")))] (if (> (listLength c.fields) 0) (filterCasesWithFieldsStep cases (+ idx 1) len (listAppend acc (list c))) (filterCasesWithFieldsStep cases (+ idx 1) len acc))))

fn emitEnumCaseParamLinesStep rawName: String typeName: String params: (List a/Param) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(p (optionOr (listGet params idx) (a/Param :name "" :type "Unit"))) (pName (c99FieldIdent p.name)) (rawTy p.type) (pTy (if (or (= rawTy rawName) (= rawTy typeName)) (str "struct " typeName "_s*") (c99TypeStr rawTy))) (line (str "        " pTy " " pName ";\n"))] (emitEnumCaseParamLinesStep rawName typeName params (+ idx 1) len (listAppend acc (list line)))))

fn emitEnumCaseMemberLinesStep rawName: String typeName: String cases: (List a/EnumCase) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(c (optionOr (listGet cases idx) (a/EnumCase :name "" :fields (list) :docstring ""))) (caseMemberName (c99FieldIdent c.name)) (pList c.fields) (fieldLines (emitEnumCaseParamLinesStep rawName typeName pList 0 (listLength pList) (list))) (structStr (str "    struct {\n" (stringJoin fieldLines "") "    } " caseMemberName ";\n"))] (emitEnumCaseMemberLinesStep rawName typeName cases (+ idx 1) len (listAppend acc (list structStr)))))

fn emitSchemaFieldTypedefs fields: (List a/AstField) -> String
  (let [(insts (collectFieldInsts fields 0 (listLength fields) (list))) (uniq (dedupeInsts insts)) (lines (emitInstTypedefsStep uniq 0 (listLength uniq) false (list)))] (stringJoin lines ""))

fn emitCDefschema s: a/SchemaNode -> String
  (let [(rawName (stringTrim s.name)) (fields s.fields) (fLen (listLength fields)) (hasEmptyName? (= rawName "")) (hasEmptyFieldName? (hasEmptyFieldNameStep fields 0 fLen))] (if (or hasEmptyName? hasEmptyFieldName?) "" (let [(typeName (c99TypeName rawName)) (bodyStrs (if (<= fLen 0) "    char _unused;\n" (stringJoin (emitSchemaFieldLinesStep rawName typeName fields 0 fLen (list)) "")))] (str "#ifndef " typeName "_DEFINED\n#define " typeName "_DEFINED\n#ifndef " typeName "_FWD_DEFINED\n#define " typeName "_FWD_DEFINED\nstruct " typeName "_s;\ntypedef struct " typeName "_s " typeName ";\n#endif\nstruct " typeName "_s {\n" bodyStrs "};\n#endif\n"))))

fn emitCaseTagAlias upperEnum: String c: a/EnumCase -> String
  (let [(cUpper (c99UpperIdent c.name)) (tagConst (str "ASL_" upperEnum "_" cUpper)) (tagAlias (str "ASL_TAG_" cUpper))] (str "#ifndef " tagAlias "\n#define " tagAlias " " tagConst "\n#endif\n"))

fn emitCaseTagAliasesStep upperEnum: String cases: (List a/EnumCase) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(c (optionOr (listGet cases idx) (a/EnumCase :name "" :fields (list) :docstring ""))) (alias (emitCaseTagAlias upperEnum c))] (emitCaseTagAliasesStep upperEnum cases (+ idx 1) len (listAppend acc (list alias)))))

fn emitConstructorParamsStep rawName: String typeName: String params: (List a/Param) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(p (optionOr (listGet params idx) (a/Param :name "" :type "Unit"))) (pName (c99FieldIdent p.name)) (rawTy p.type) (pTy (if (or (= rawTy rawName) (= rawTy typeName)) typeName (c99TypeStr rawTy))) (entry (str pTy " " pName))] (emitConstructorParamsStep rawName typeName params (+ idx 1) len (listAppend acc (list entry)))))

fn emitConstructorAssignsStep rawName: String typeName: String cMember: String params: (List a/Param) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(p (optionOr (listGet params idx) (a/Param :name "" :type "Unit"))) (pName (c99FieldIdent p.name)) (rawTy p.type) (line (if (or (= rawTy rawName) (= rawTy typeName)) (str "    _res.data." cMember "." pName " = (struct " typeName "_s*)malloc(sizeof(struct " typeName "_s));\n    *_res.data." cMember "." pName " = " pName ";\n") (str "    _res.data." cMember "." pName " = " pName ";\n")))] (emitConstructorAssignsStep rawName typeName cMember params (+ idx 1) len (listAppend acc (list line)))))

fn emitCaseConstructor upperEnum: String rawName: String typeName: String c: a/EnumCase -> String
  (let [(rawCaseName c.name) (fnName (c99FieldIdent rawCaseName)) (cUpper (c99UpperIdent rawCaseName)) (tagConst (str "ASL_" upperEnum "_" cUpper)) (pList c.fields) (pLen (listLength pList)) (cMember (c99FieldIdent rawCaseName))] (if (<= pLen 0) (str "static inline __attribute__((unused)) " typeName " " fnName "(void) {\n    " typeName " _res;\n    memset(&_res, 0, sizeof(_res));\n    _res.tag = " tagConst ";\n    return _res;\n}\n\n") (let [(paramStr (stringJoin (emitConstructorParamsStep rawName typeName pList 0 pLen (list)) ", ")) (assignLines (emitConstructorAssignsStep rawName typeName cMember pList 0 pLen (list)))] (str "static inline __attribute__((unused)) " typeName " " fnName "(" paramStr ") {\n    " typeName " _res;\n    memset(&_res, 0, sizeof(_res));\n    _res.tag = " tagConst ";\n" (stringJoin assignLines "") "    return _res;\n}\n\n"))))

fn emitCaseConstructorsStep upperEnum: String rawName: String typeName: String cases: (List a/EnumCase) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) acc (let [(c (optionOr (listGet cases idx) (a/EnumCase :name "" :fields (list) :docstring ""))) (ctor (emitCaseConstructor upperEnum rawName typeName c))] (emitCaseConstructorsStep upperEnum rawName typeName cases (+ idx 1) len (listAppend acc (list ctor)))))

fn emitEnumCaseTypedefs cases: (List a/EnumCase) -> String
  (let [(insts (collectCaseInsts cases 0 (listLength cases) (list))) (uniq (dedupeInsts insts)) (lines (emitInstTypedefsStep uniq 0 (listLength uniq) false (list)))] (stringJoin lines ""))

fn emitCDefenum e: a/EnumNode -> String
  (let [(rawName (stringTrim e.name)) (cases e.cases) (cLen (listLength cases)) (hasEmptyName? (= rawName "")) (hasEmptyCaseName? (hasEmptyCaseNameStep cases 0 cLen))] (if (or hasEmptyName? (or hasEmptyCaseName? (<= cLen 0))) "" (let [(typeName (c99TypeName rawName)) (upperEnum (c99UpperIdent rawName)) (tagEnumName (str typeName "Tag")) (dataUnionName (str typeName "Data")) (tagConstants (emitTagConstantsStep upperEnum cases 0 cLen (list))) (tagLines (map formatTagLine tagConstants)) (tagSection (str "typedef enum {\n" (stringJoin tagLines ",\n") "\n} " tagEnumName ";\n\n")) (casesWithFields (filterCasesWithFieldsStep cases 0 cLen (list))) (cwfLen (listLength casesWithFields)) (unionBody (if (<= cwfLen 0) "    char _unused;\n" (stringJoin (emitEnumCaseMemberLinesStep rawName typeName casesWithFields 0 cwfLen (list)) ""))) (unionSection (str "typedef union {\n" unionBody "} " dataUnionName ";\n\n")) (tagAliases (stringJoin (emitCaseTagAliasesStep upperEnum cases 0 cLen (list)) "")) (constructors (stringJoin (emitCaseConstructorsStep upperEnum rawName typeName cases 0 cLen (list)) "")) (structSection (str "#ifndef " typeName "_DEFINED\n#define " typeName "_DEFINED\n#ifndef " typeName "_FWD_DEFINED\n#define " typeName "_FWD_DEFINED\nstruct " typeName "_s;\ntypedef struct " typeName "_s " typeName ";\n#endif\nstruct " typeName "_s {\n    " tagEnumName " tag;\n    " dataUnionName " data;\n};\n#endif\n\n"))] (str tagSection tagAliases "\n" unionSection structSection constructors))))
