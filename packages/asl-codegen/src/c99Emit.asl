(module asl-codegen/c99Emit :x [emitCHeaderGuards emitCStandardIncludes emitCFunctionPrototype emitCExternCWrapper emitCFreestandingPreamble emitCHostedPreamble emitCHeaderFile emitCSourceFile emitCStandalone emitCMainEntry emitCMainEntryWithArgs collectUniqueDefuns assembleCModule emitCFunctionDef emitSchemaForwardDecl emitEnumForwardDecl collectFormsSchemas collectFormsEnums collectFormsDefuns] :i [(ast :a a) (reader :a rd) (c99Mangle :a cm) (c99Type :a ct) (c99Expr :a ce)])

fn emitCHeaderGuards modName: String content: String -> String
  (let [(p0 (stringReplace (stringReplace (stringReplace modName "/" "_") "-" "_") "." "_")) (u0 (stringUpper p0)) (u1 (if (stringStartsWith? u0 "ASL_") u0 (str "ASL_" u0))) (guard (if (stringEndsWith? u1 "_H") u1 (str u1 "_H")))] (str "#ifndef " guard "\n#define " guard "\n\n" content "\n\n#endif\n"))

fn emitCStandardIncludes isFreestanding: Bool -> String
  (if isFreestanding "#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>" "#ifndef _POSIX_C_SOURCE\n#define _POSIX_C_SOURCE 200809L\n#endif\n\n#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>")

fn emitCExternCWrapper content: String -> String
  (str "#ifdef __cplusplus\nextern \"C\" {\n#endif\n\n" content "\n\n#ifdef __cplusplus\n}\n#endif")

fn emitCFreestandingPreamble -> String
  (str (emitCStandardIncludes true) "\n\n" (ct/emitCStringType))

fn emitCHostedPreamble -> String
  (str (emitCStandardIncludes false) "\n\n" (ct/emitCStringType) "\n#if defined(__has_include)\n#if __has_include(\"asl_runtime.h\")\n#include \"asl_runtime.h\"\n#elif __has_include(\"engine/asl_runtime.h\")\n#include \"engine/asl_runtime.h\"\n#endif\n#else\n#include \"asl_runtime.h\"\n#endif")

fn emitParamPrototype p: a/Param -> String
  (let [(pTy (ct/c99TypeStr p.type)) (pName (cm/mangleCIdent p.name))] (str pTy " " pName))

fn emitParamsStrStep ps: (List a/Param) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) (listReverse acc) (let [(p (optionOr (listGet ps idx) (a/Param :name "" :type "Unit")))] (emitParamsStrStep ps (+ idx 1) len (cons (emitParamPrototype p) acc))))

fn emitParamsStr ps: (List a/Param) -> String
  (if (<= (listLength ps) 0) "void" (stringJoin (emitParamsStrStep ps 0 (listLength ps) (list)) ", "))

fn emitVoidParamsStep ps: (List a/Param) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) (listReverse acc) (let [(p (optionOr (listGet ps idx) (a/Param :name "" :type "Unit"))) (pName (cm/mangleCIdent p.name))] (emitVoidParamsStep ps (+ idx 1) len (cons (str "    (void)" pName ";") acc))))

fn emitSchemaForwardDeclsStep schemas: (List a/SchemaNode) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) (listReverse acc) (let [(s (optionOr (listGet schemas idx) (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none))))] (emitSchemaForwardDeclsStep schemas (+ idx 1) len (cons (emitSchemaForwardDecl s) acc))))

fn emitEnumForwardDeclsStep enums: (List a/EnumNode) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) (listReverse acc) (let [(e (optionOr (listGet enums idx) (a/EnumNode :name "" :typeVars (list) :cases (list))))] (emitEnumForwardDeclsStep enums (+ idx 1) len (cons (emitEnumForwardDecl e) acc))))

fn emitCDefenumsStep enums: (List a/EnumNode) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) (listReverse acc) (let [(e (optionOr (listGet enums idx) (a/EnumNode :name "" :typeVars (list) :cases (list))))] (emitCDefenumsStep enums (+ idx 1) len (cons (ct/emitCDefenum e) acc))))

fn emitCDefschemasStep schemas: (List a/SchemaNode) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) (listReverse acc) (let [(s (optionOr (listGet schemas idx) (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none))))] (emitCDefschemasStep schemas (+ idx 1) len (cons (ct/emitCDefschema s) acc))))

fn emitCFunctionPrototypesStep defuns: (List a/DefunNode) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) (listReverse acc) (let [(d (optionOr (listGet defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list) :bodyPos (list))))] (emitCFunctionPrototypesStep defuns (+ idx 1) len (cons (emitCFunctionPrototype d) acc))))

fn emitCFunctionPrototype fn: a/DefunNode -> String
  (let [(rawRet fn.retType) (retTy (ct/c99TypeStr rawRet)) (fnName (cm/mangleCIdent fn.name)) (params fn.params) (paramStr (emitParamsStr params)) (proto (str retTy " " fnName "(" paramStr ");"))] (if (stringStartsWith? fnName "asl_is_") (let [(shortName (cm/sliceOr fnName 4 (stringLength fnName) ""))] (str "#ifndef " shortName "\n#define " shortName " " fnName "\n#endif\n" proto)) proto))

fn ctxOfParamsStep ctx: ce/LowerCtx ps: (List a/Param) idx: Int64 len: Int64 -> ce/LowerCtx
  (if (>= idx len) ctx (let [(p (optionOr (listGet ps idx) (a/Param :name "" :type "Unit")))] (ctxOfParamsStep (ce/ctxWithVar ctx p.name (ct/c99TypeStr p.type)) ps (+ idx 1) len)))

fn fnRetTypes defuns: (List a/DefunNode) -> (Map String String)
  (fold (fn [(acc (Map String String)) (d a/DefunNode)] -> (Map String String) (mapSet acc d.name (ct/c99TypeStr d.retType))) (mapEmpty) defuns)

fn ctxOfDefun fn: a/DefunNode fnTypes: (Map String String) -> ce/LowerCtx
  (let [(base (ce/LowerCtx :vars (list) :substs (list) :fns fnTypes :retTy (ct/c99TypeStr fn.retType)))] (ctxOfParamsStep base fn.params 0 (listLength fn.params)))

fn emitInitStmtsStep ctx: ce/LowerCtx es: (List rd/SExpr) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) (listReverse acc) (let [(e (optionOr (listGet es idx) (rd/sexprAtom "()")))] (emitInitStmtsStep ctx es (+ idx 1) len (cons (emitInitStmt ctx e) acc))))

fn emitInitStmt ctx: ce/LowerCtx e: rd/SExpr -> String
  (let [(s (ce/lowerCExpr ctx e))] (if (or (stringEndsWith? s ";") (stringEndsWith? s "}")) (str "    " s) (str "    " s ";")))

fn emitCFunctionDefsStep defuns: (List a/DefunNode) fnTypes: (Map String String) idx: Int64 len: Int64 acc: (List String) -> (List String)
  (if (>= idx len) (listReverse acc) (let [(d (optionOr (listGet defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list) :bodyPos (list))))] (emitCFunctionDefsStep defuns fnTypes (+ idx 1) len (cons (emitCFunctionDef d fnTypes) acc))))

fn emitCFunctionDef fn: a/DefunNode fnTypes: (Map String String) -> String
  (let [(rawRet fn.retType) (retTy (ct/c99TypeStr rawRet)) (fnName (cm/mangleCIdent fn.name)) (params fn.params) (paramStr (emitParamsStr params)) (voidParams (emitVoidParamsStep params 0 (listLength params) (list))) (voidPrefix (if (> (listLength voidParams) 0) (str (stringJoin voidParams "\n") "\n") "")) (bodyCtx (ctxOfDefun fn fnTypes)) (body fn.body) (bodyLen (listLength body))] (cond ((<= bodyLen 0) (if (= retTy "void") (str retTy " " fnName "(" paramStr ") {\n" voidPrefix "    return;\n}\n") (str retTy " " fnName "(" paramStr ") {\n" voidPrefix "    return (" retTy "){0};\n}\n"))) ((= bodyLen 1) (let [(soleExpr (optionOr (listGet body 0) (rd/sexprAtom "()"))) (lowered (ce/lowerCExpr bodyCtx soleExpr))] (if (= retTy "void") (if (or (stringEndsWith? lowered "}") (stringEndsWith? lowered ";")) (str retTy " " fnName "(" paramStr ") {\n" voidPrefix "    " lowered "\n    return;\n}\n") (str retTy " " fnName "(" paramStr ") {\n" voidPrefix "    " lowered ";\n    return;\n}\n")) (if (stringStartsWith? lowered "{") (let [(wrapped (ce/wrapBlockWithReturn lowered))] (let [(inner (cm/sliceOr wrapped 1 (- (stringLength wrapped) 1) ""))] (str retTy " " fnName "(" paramStr ") {\n" voidPrefix inner "\n    return (" retTy "){0};\n}\n"))) (if (or (stringStartsWith? lowered "switch") (stringStartsWith? lowered "if")) (str retTy " " fnName "(" paramStr ") {\n" voidPrefix "    " lowered "\n    return (" retTy "){0};\n}\n") (str retTy " " fnName "(" paramStr ") {\n" voidPrefix "    return " lowered ";\n}\n")))))) (else (let [(initExprs (optionOr (listSlice body 0 (- bodyLen 1)) (list))) (lastExpr (optionOr (listGet body (- bodyLen 1)) (rd/sexprAtom "()"))) (initStmts (emitInitStmtsStep bodyCtx initExprs 0 (listLength initExprs) (list))) (lastLowered (ce/lowerCExpr bodyCtx lastExpr)) (lastStmt (if (= retTy "void") (if (or (stringEndsWith? lastLowered ";") (stringEndsWith? lastLowered "}")) (str "    " lastLowered "\n    return;") (str "    " lastLowered ";\n    return;")) (if (or (stringStartsWith? lastLowered "switch") (stringStartsWith? lastLowered "if")) (str "    " lastLowered "\n    return (" retTy "){0};") (if (stringStartsWith? lastLowered "{") (let [(wrapped (ce/wrapBlockWithReturn lastLowered))] (let [(inner (cm/sliceOr wrapped 1 (- (stringLength wrapped) 1) ""))] (str inner "\n    return (" retTy "){0};"))) (str "    return " lastLowered ";")))))] (str retTy " " fnName "(" paramStr ") {\n" voidPrefix (stringJoin initStmts "\n") "\n" lastStmt "\n}\n")))))

fn emitCMainEntryWithArgs entryFn: String isFreestanding: Bool hasArgs: Bool -> String
  (if isFreestanding (if (> (stringLength entryFn) 0) (let [(mangled (cm/mangleCIdent entryFn))] (str "void setup(void) {\n    " mangled "();\n}\n\nvoid loop(void) {\n}\n")) "void setup(void) {\n}\n\nvoid loop(void) {\n}\n") (if (> (stringLength entryFn) 0) (let [(mangled (cm/mangleCIdent entryFn))] (if hasArgs (str "int main(int argc, char** argv) {\n" "    int count = (argc > 1) ? (argc - 1) : 0;\n" "    asl_string_t* args_items = (asl_string_t*)malloc(sizeof(asl_string_t) * (size_t)(count > 0 ? count : 1));\n" "    for (int i = 0; i < count; i++) {\n" "        args_items[i] = asl_string_from_cstr(argv[1 + i]);\n" "    }\n" "    AslSlice_asl_string_t args = { .items = args_items, .count = (size_t)count };\n" "    int exit_code = (" mangled "(args).tag == 0) ? 0 : 1;\n" "    free(args_items);\n" "    return exit_code;\n" "}\n") (str "int main(int argc, char** argv) {\n    (void)argc;\n    (void)argv;\n    return (int)" mangled "();\n}\n"))) "int main(int argc, char** argv) {\n    (void)argc;\n    (void)argv;\n    return 0;\n}\n"))

fn emitCMainEntry entryFn: String isFreestanding: Bool -> String
  (emitCMainEntryWithArgs entryFn isFreestanding false)

fn findEntryStep defuns: (List a/DefunNode) idx: Int64 len: Int64 -> (Option String)
  (if (>= idx len) (none) (let [(d (optionOr (listGet defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list) :bodyPos (list)))) (nm d.name) (low (stringLower nm))] (if (or (= low "main") (= low "run")) (some nm) (findEntryStep defuns (+ idx 1) len))))

fn findEntryName defuns: (List a/DefunNode) explicitEntry: String -> String
  (if (> (stringLength explicitEntry) 0) explicitEntry (let [(mainOpt (findEntryStep defuns 0 (listLength defuns)))] (mt mainOpt ((some m) m) ((none) (if (> (listLength defuns) 0) (let [(d0 (optionOr (listHead defuns) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list) :bodyPos (list))))] d0.name) "")))))

fn collectUniqueSchemasStep schemas: (List a/SchemaNode) idx: Int64 len: Int64 seen: (Map String Bool) acc: (List a/SchemaNode) -> (List a/SchemaNode)
  (if (>= idx len) (listReverse acc) (let [(s (optionOr (listGet schemas idx) (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none)))) (nm s.name)] (if (mapHas? seen nm) (collectUniqueSchemasStep schemas (+ idx 1) len seen acc) (collectUniqueSchemasStep schemas (+ idx 1) len (mapSet seen nm true) (cons s acc)))))

fn emitSchemaForwardDecl s: a/SchemaNode -> String
  (let [(rawName (stringTrim s.name))] (if (= rawName "") "" (let [(typeName (ct/c99TypeName rawName))] (str "#ifndef " typeName "_FWD_DEFINED\n#define " typeName "_FWD_DEFINED\nstruct " typeName "_s;\ntypedef struct " typeName "_s " typeName ";\n#endif"))))

fn emitEnumForwardDecl e: a/EnumNode -> String
  (let [(rawName (stringTrim e.name))] (if (= rawName "") "" (let [(typeName (ct/c99TypeName rawName))] (str "#ifndef " typeName "_FWD_DEFINED\n#define " typeName "_FWD_DEFINED\nstruct " typeName "_s;\ntypedef struct " typeName "_s " typeName ";\n#endif"))))

fn isModuleSummarySchema? s: a/SchemaNode -> Bool
  (= s.name "ModuleSummary")

fn isNotModuleSummarySchema? s: a/SchemaNode -> Bool
  (!= s.name "ModuleSummary")

fn collectUniqueSchemas schemas: (List a/SchemaNode) -> (List a/SchemaNode)
  (let [(allUniq (collectUniqueSchemasStep schemas 0 (listLength schemas) (mapEmpty) (list))) (mods (filter isModuleSummarySchema? allUniq)) (others (filter isNotModuleSummarySchema? allUniq))] (listAppend others mods))

fn isDependentSchema? s: a/SchemaNode -> Bool
  (let [(nm s.name)] (or (= nm "ReadState") (or (= nm "LexState") (or (= nm "ScanState") (= nm "FrameMachine")))))

fn isIndependentSchema? s: a/SchemaNode -> Bool
  (not (isDependentSchema? s))

fn isSchemaEmbeddingEnum? e: a/EnumNode -> Bool
  (let [(nm e.name)] (or (= nm "TopForm") (= nm "EvalValue")))

fn isNotSchemaEmbeddingEnum? e: a/EnumNode -> Bool
  (not (isSchemaEmbeddingEnum? e))

fn collectUniqueEnumsStep enums: (List a/EnumNode) idx: Int64 len: Int64 seen: (Map String Bool) acc: (List a/EnumNode) -> (List a/EnumNode)
  (if (>= idx len) (listReverse acc) (let [(e (optionOr (listGet enums idx) (a/EnumNode :name "" :typeVars (list) :cases (list)))) (nm e.name)] (if (mapHas? seen nm) (collectUniqueEnumsStep enums (+ idx 1) len seen acc) (collectUniqueEnumsStep enums (+ idx 1) len (mapSet seen nm true) (cons e acc)))))

fn collectUniqueEnums enums: (List a/EnumNode) -> (List a/EnumNode)
  (collectUniqueEnumsStep enums 0 (listLength enums) (mapEmpty) (list))

fn collectUniqueDefunsStep defuns: (List a/DefunNode) idx: Int64 len: Int64 seen: (Map String Bool) acc: (List a/DefunNode) -> (List a/DefunNode)
  (if (>= idx len) (listReverse acc) (let [(d (optionOr (listGet defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list) :bodyPos (list)))) (nm (cm/mangleCIdent d.name))] (if (mapHas? seen nm) (collectUniqueDefunsStep defuns (+ idx 1) len seen acc) (collectUniqueDefunsStep defuns (+ idx 1) len (mapSet seen nm true) (cons d acc)))))

fn collectUniqueDefuns defuns: (List a/DefunNode) -> (List a/DefunNode)
  (collectUniqueDefunsStep defuns 0 (listLength defuns) (mapEmpty) (list))

fn collectFormsSchemas forms: (List a/TopForm) idx: Int64 len: Int64 acc: (List a/SchemaNode) -> (List a/SchemaNode)
  (if (>= idx len) (listReverse acc) (let [(tf (optionOr (listGet forms idx) (a/topSchema (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none)))))] (mt tf ((a/topSchema s) (collectFormsSchemas forms (+ idx 1) len (cons s acc))) (else (collectFormsSchemas forms (+ idx 1) len acc)))))

fn collectFormsEnums forms: (List a/TopForm) idx: Int64 len: Int64 acc: (List a/EnumNode) -> (List a/EnumNode)
  (if (>= idx len) (listReverse acc) (let [(tf (optionOr (listGet forms idx) (a/topSchema (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none)))))] (mt tf ((a/topEnum e) (collectFormsEnums forms (+ idx 1) len (cons e acc))) (else (collectFormsEnums forms (+ idx 1) len acc)))))

fn collectFormsDefuns forms: (List a/TopForm) idx: Int64 len: Int64 acc: (List a/DefunNode) -> (List a/DefunNode)
  (if (>= idx len) (listReverse acc) (let [(tf (optionOr (listGet forms idx) (a/topSchema (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none)))))] (mt tf ((a/topDefun d) (collectFormsDefuns forms (+ idx 1) len (cons d acc))) (else (collectFormsDefuns forms (+ idx 1) len acc)))))

fn isNonEmptyString? s: String -> Bool
  (> (stringLength s) 0)

fn findEntryDefun defuns: (List a/DefunNode) name: String idx: Int64 len: Int64 -> (Option a/DefunNode)
  (if (>= idx len) (none) (let [(d (optionOr (listGet defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list) :bodyPos (list))))] (if (= d.name name) (some d) (findEntryDefun defuns name (+ idx 1) len))))

fn emitCHeaderFile mod: a/ModuleNode -> String
  (let [(modPath mod.path) (defs mod.defs) (schemas (collectFormsSchemas defs 0 (listLength defs) (list))) (enums (collectFormsEnums defs 0 (listLength defs) (list))) (defuns (collectFormsDefuns defs 0 (listLength defs) (list))) (uniqSchemas (collectUniqueSchemas schemas)) (uniqEnums (collectUniqueEnums enums)) (simpleEnums (filter isNotSchemaEmbeddingEnum? uniqEnums)) (complexEnums (filter isSchemaEmbeddingEnum? uniqEnums)) (independentSchemas (filter isIndependentSchema? uniqSchemas)) (dependentSchemas (filter isDependentSchema? uniqSchemas)) (hdrIncludes (emitCStandardIncludes false)) (strType (ct/emitCStringType)) (forwardSchemas (emitSchemaForwardDeclsStep uniqSchemas 0 (listLength uniqSchemas) (list))) (forwardEnums (emitEnumForwardDeclsStep uniqEnums 0 (listLength uniqEnums) (list))) (allForwardTypes (stringJoin (listAppend forwardSchemas forwardEnums) "\n")) (simpleEnumStrs (emitCDefenumsStep simpleEnums 0 (listLength simpleEnums) (list))) (indepSchemaStrs (emitCDefschemasStep independentSchemas 0 (listLength independentSchemas) (list))) (complexEnumStrs (emitCDefenumsStep complexEnums 0 (listLength complexEnums) (list))) (depSchemaStrs (emitCDefschemasStep dependentSchemas 0 (listLength dependentSchemas) (list))) (protoStrs (emitCFunctionPrototypesStep defuns 0 (listLength defuns) (list))) (protoBlock (if (<= (listLength protoStrs) 0) "" (emitCExternCWrapper (stringJoin protoStrs "\n")))) (sections (filter isNonEmptyString? (list hdrIncludes strType allForwardTypes (stringJoin simpleEnumStrs "\n") (stringJoin indepSchemaStrs "\n") (stringJoin complexEnumStrs "\n") (stringJoin depSchemaStrs "\n") protoBlock))) (bodyContent (stringJoin sections "\n\n"))] (emitCHeaderGuards modPath bodyContent))

fn emitCSourceFile mod: a/ModuleNode -> String
  (let [(defs mod.defs) (defuns (collectFormsDefuns defs 0 (listLength defs) (list))) (preamble (emitCHostedPreamble)) (protoStrs (emitCFunctionPrototypesStep defuns 0 (listLength defuns) (list))) (fnDefs (emitCFunctionDefsStep defuns (fnRetTypes defuns) 0 (listLength defuns) (list))) (sections (filter isNonEmptyString? (list preamble (stringJoin protoStrs "\n") (stringJoin fnDefs "\n"))))] (str (stringJoin sections "\n\n") "\n"))

fn formsHaveTopExpr? forms: (List a/TopForm) idx: Int64 len: Int64 -> Bool
  (if (>= idx len) false (mt (optionOr (listGet forms idx) (a/topModule (a/ModuleNode :path "" :docstring "" :exported (list) :imports (list) :defs (list)))) ((a/topExpr _) true) (_ (formsHaveTopExpr? forms (+ idx 1) len))))

fn emitCStandalone forms: (List a/TopForm) entryFn: String isFreestanding: Bool -> String
  (do (assert (not (formsHaveTopExpr? forms 0 (listLength forms))) "ERR_C99_TOPLEVEL_EXPR: a bare top-level expression has no module-load hook in the standalone C99 target")
  (let [(schemas (collectFormsSchemas forms 0 (listLength forms) (list))) (enums (collectFormsEnums forms 0 (listLength forms) (list))) (defuns (collectFormsDefuns forms 0 (listLength forms) (list))) (uniqSchemas (collectUniqueSchemas schemas)) (uniqEnums (collectUniqueEnums enums)) (simpleEnums (filter isNotSchemaEmbeddingEnum? uniqEnums)) (complexEnums (filter isSchemaEmbeddingEnum? uniqEnums)) (independentSchemas (filter isIndependentSchema? uniqSchemas)) (dependentSchemas (filter isDependentSchema? uniqSchemas)) (uniqDefuns (collectUniqueDefuns defuns)) (preamble (if isFreestanding (emitCFreestandingPreamble) (emitCHostedPreamble))) (forwardSchemas (emitSchemaForwardDeclsStep uniqSchemas 0 (listLength uniqSchemas) (list))) (forwardEnums (emitEnumForwardDeclsStep uniqEnums 0 (listLength uniqEnums) (list))) (uniqInsts (ct/dedupeInsts (ct/collectAllInsts forms))) (instForwardTypes (ct/emitInstForwardDeclsFromUniq uniqInsts)) (allForwardTypes (stringJoin (listAppend (listAppend forwardSchemas forwardEnums) (list instForwardTypes)) "\n")) (sliceTypedefs (ct/emitInstTypedefsFromUniq uniqInsts true)) (valueTypedefs (ct/emitInstTypedefsFromUniq uniqInsts false)) (instAccessors (ct/emitInstAccessorsFromUniq uniqInsts)) (simpleEnumStrs (emitCDefenumsStep simpleEnums 0 (listLength simpleEnums) (list))) (indepSchemaStrs (emitCDefschemasStep independentSchemas 0 (listLength independentSchemas) (list))) (complexEnumStrs (emitCDefenumsStep complexEnums 0 (listLength complexEnums) (list))) (depSchemaStrs (emitCDefschemasStep dependentSchemas 0 (listLength dependentSchemas) (list))) (protoStrs (emitCFunctionPrototypesStep uniqDefuns 0 (listLength uniqDefuns) (list))) (fnTypes (fnRetTypes uniqDefuns)) (fnDefs (emitCFunctionDefsStep uniqDefuns fnTypes 0 (listLength uniqDefuns) (list))) (actualEntry (findEntryName uniqDefuns entryFn)) (entryDefunOpt (findEntryDefun defuns actualEntry 0 (listLength defuns))) (hasArgs (mt entryDefunOpt ((some d) (> (listLength d.params) 0)) ((none) false))) (mainEntry (emitCMainEntryWithArgs actualEntry isFreestanding hasArgs)) (sections (filter isNonEmptyString? (list preamble allForwardTypes sliceTypedefs (stringJoin simpleEnumStrs "\n") (stringJoin indepSchemaStrs "\n") (stringJoin complexEnumStrs "\n") valueTypedefs (stringJoin depSchemaStrs "\n") instAccessors (stringJoin protoStrs "\n") (stringJoin fnDefs "\n") mainEntry)))] (str (stringJoin sections "\n\n") "\n")))

fn assembleCModule mod: a/ModuleNode isFreestanding: Bool -> String
  (emitCStandalone mod.defs "" isFreestanding)
