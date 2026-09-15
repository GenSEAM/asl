(module asl-codegen/c99Emit
  :d "Translation unit assembly, multi-lens projection, and dual execution presets for ISO C99."
  :x [emitCHeaderGuards
      emitCStandardIncludes
      emitCFunctionPrototype
      emitCExternCWrapper
      emitCFreestandingPreamble
      emitCHostedPreamble
      emitCHeaderFile
      emitCSourceFile
      emitCStandalone
      emitCMainEntry
      emitCMainEntryWithArgs
      collectUniqueDefuns
      assembleCModule
      emitCFunctionDef
      emitSchemaForwardDecl]
  :i [(ast :a a) (reader :a rd) (c99Mangle :a cm) (c99Type :a ct) (c99Expr :a ce)])

(df emitCHeaderGuards [(modName String) (content String)] -> String
  :d "Wraps C header content with canonical preprocessor include guards."
  (let [(p0 (string-replace (string-replace (string-replace modName "/" "_") "-" "_") "." "_"))
        (u0 (string-upper p0))
        (u1 (if (string-starts-with? u0 "ASL_") u0 (str "ASL_" u0)))
        (guard (if (string-ends-with? u1 "_H") u1 (str u1 "_H")))]
    (str "#ifndef " guard "\n#define " guard "\n\n" content "\n\n#endif\n")))

(df emitCStandardIncludes [(isFreestanding Bool)] -> String
  :d "Emits ISO C99 standard header includes based on freestanding or hosted execution preset."
  (if isFreestanding
      "#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>"
      "#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>"))

(df emitCExternCWrapper [(content String)] -> String
  :d "Wraps declarations in extern C block when compiled under C++ compilers."
  (str "#ifdef __cplusplus\nextern \"C\" {\n#endif\n\n" content "\n\n#ifdef __cplusplus\n}\n#endif"))

(df emitCFreestandingPreamble [] -> String
  :d "Emits standard freestanding C99 headers and fundamental type definitions."
  (str (emitCStandardIncludes true) "\n\n" (ct/emitCStringType)))

(df emitCHostedPreamble [] -> String
  :d "Emits standard hosted POSIX/CLI C99 headers and fundamental type definitions."
  (str (emitCStandardIncludes false) "\n\n" (ct/emitCStringType) "\n#if defined(__has_include)\n#if __has_include(\"asl_runtime.h\")\n#include \"asl_runtime.h\"\n#elif __has_include(\"engine/asl_runtime.h\")\n#include \"engine/asl_runtime.h\"\n#endif\n#else\n#include \"asl_runtime.h\"\n#endif"))

(df emitParamPrototype [(p a/Param)] -> String
  :d "Formats single C function parameter."
  (let [(pTy (ct/c99TypeStr (.-type p)))
        (pName (cm/mangleCIdent (.-name p)))]
    (str pTy " " pName)))

(df emitCFunctionPrototype [(fn a/DefunNode)] -> String
  :d "Formats an ISO C99 forward function prototype declaration."
  (let [(rawRet (.-retType fn))
        (retTy (ct/c99TypeStr rawRet))
        (fnName (cm/mangleCIdent (.-name fn)))
        (params (.-params fn))
        (paramStr (if (<= (list-length params) 0)
                      "void"
                      (string-join (map emitParamPrototype params) ", ")))
        (proto (str retTy " " fnName "(" paramStr ");"))]
    (if (string-starts-with? fnName "asl_is_")
        (let [(shortName (cm/sliceOr fnName 4 (string-length fnName) ""))]
          (str "#ifndef " shortName "\n#define " shortName " " fnName "\n#endif\n" proto))
        proto)))

(df emitInitStmt [(e rd/SExpr)] -> String
  :d "Formats an intermediate SExpr as a C statement."
  (let [(s (ce/lowerCExpr e))]
    (if (or (string-ends-with? s ";") (string-ends-with? s "}"))
        (str "    " s)
        (str "    " s ";"))))

(df emitCFunctionDef [(fn a/DefunNode)] -> String
  :d "Lowers a typed defun AST node into an ISO C99 function implementation."
  (let [(rawRet (.-retType fn))
        (retTy (ct/c99TypeStr rawRet))
        (fnName (cm/mangleCIdent (.-name fn)))
        (params (.-params fn))
        (paramStr (if (<= (list-length params) 0)
                      "void"
                      (string-join (map emitParamPrototype params) ", ")))
        (body (.-body fn))
        (bodyLen (list-length body))]
    (cond
      ((<= bodyLen 0)
       (if (= retTy "void")
           (str retTy " " fnName "(" paramStr ") {\n    return;\n}\n")
           (str retTy " " fnName "(" paramStr ") {\n    return (" retTy "){0};\n}\n")))
      ((= bodyLen 1)
       (let [(soleExpr (option-or (list-get body 0) (rd/sexprAtom "()")))
             (lowered (ce/lowerCExpr soleExpr))]
         (if (= retTy "void")
             (if (or (string-ends-with? lowered "}") (string-ends-with? lowered ";"))
                 (str retTy " " fnName "(" paramStr ") {\n    " lowered "\n    return;\n}\n")
                 (str retTy " " fnName "(" paramStr ") {\n    " lowered ";\n    return;\n}\n"))
             (if (string-starts-with? lowered "{")
                 (if (or (string-starts-with? lowered "return") (or (string-starts-with? lowered "switch") (string-starts-with? lowered "{")))
                     (let [(inner (cm/sliceOr lowered 1 (- (string-length lowered) 1) ""))]
                       (str retTy " " fnName "(" paramStr ") {\n" inner "\n    return (" retTy "){0};\n}\n"))
                     (str retTy " " fnName "(" paramStr ") {\n    return (" lowered ");\n}\n"))
                 (if (string-starts-with? lowered "switch")
                     (str retTy " " fnName "(" paramStr ") {\n    " lowered "\n    return (" retTy "){0};\n}\n")
                     (if (string-starts-with? lowered "if")
                         (str retTy " " fnName "(" paramStr ") {\n    " lowered "\n    return (" retTy "){0};\n}\n")
                         (if (string-starts-with? lowered "if (")
                         (str retTy " " fnName "(" paramStr ") {\n    " lowered "\n    return (" retTy "){0};\n}\n")
                         (str retTy " " fnName "(" paramStr ") {\n    return " lowered ";\n}\n"))))))))
      (:else
       (let [(initExprs (option-or (list-slice body 0 (- bodyLen 1)) (list)))
             (lastExpr (option-or (list-get body (- bodyLen 1)) (rd/sexprAtom "()")))
             (initStmts (map emitInitStmt initExprs))
             (lastLowered (ce/lowerCExpr lastExpr))
             (lastStmt (if (= retTy "void")
                           (if (or (string-ends-with? lastLowered ";") (string-ends-with? lastLowered "}"))
                               (str "    " lastLowered "\n    return;")
                               (str "    " lastLowered ";\n    return;"))
                           (if (string-starts-with? lastLowered "switch")
                               (str "    " lastLowered "\n    return (" retTy "){0};")
                               (if (string-starts-with? lastLowered "{")
                                   (if (or (string-starts-with? lastLowered "return") (or (string-starts-with? lastLowered "switch") (string-starts-with? lastLowered "{")))
                                       (let [(inner (cm/sliceOr lastLowered 1 (- (string-length lastLowered) 1) ""))]
                                         (str inner "\n    return (" retTy "){0};"))
                                       (str "    return (" lastLowered ");"))
                                   (str "    return " lastLowered ";")))))]
         (str retTy " " fnName "(" paramStr ") {\n"
              (string-join initStmts "\n") "\n"
              lastStmt "\n}\n"))))))

(df emitCMainEntryWithArgs [(entryFn String) (isFreestanding Bool) (hasArgs Bool)] -> String
  :d "Emits ISO C99 main entrypoint for hosted CLI mode or setup/loop for freestanding preset."
  (if isFreestanding
      (if (> (string-length entryFn) 0)
          (let [(mangled (cm/mangleCIdent entryFn))]
            (str "void setup(void) {\n    " mangled "();\n}\n\nvoid loop(void) {\n}\n"))
          "void setup(void) {\n}\n\nvoid loop(void) {\n}\n")
      (if (> (string-length entryFn) 0)
          (let [(mangled (cm/mangleCIdent entryFn))]
            (if hasArgs
                (str "int main(int argc, char** argv) {\n"
                     "    int count = (argc > 1) ? (argc - 1) : 0;\n"
                     "    asl_string_t* args_items = (asl_string_t*)malloc(sizeof(asl_string_t) * (size_t)(count > 0 ? count : 1));\n"
                     "    for (int i = 0; i < count; i++) {\n"
                     "        args_items[i] = asl_string_from_cstr(argv[1 + i]);\n"
                     "    }\n"
                     "    AslSlice_asl_string_t args = { .items = args_items, .count = (size_t)count };\n"
                     "    AslResult res = " mangled "(args);\n"
                     "    free(args_items);\n"
                     "    return (res.tag == ASL_RESULT_OK) ? 0 : 1;\n"
                     "}\n")
                (str "int main(int argc, char** argv) {\n    (void)argc;\n    (void)argv;\n    return (int)" mangled "();\n}\n")))
          "int main(int argc, char** argv) {\n    (void)argc;\n    (void)argv;\n    return 0;\n}\n")))

(df emitCMainEntry [(entryFn String) (isFreestanding Bool)] -> String
  :d "Emits ISO C99 main entrypoint for hosted CLI mode or setup/loop for freestanding preset."
  (emitCMainEntryWithArgs entryFn isFreestanding false))

(df findEntryStep [(defuns (List a/DefunNode)) (idx Int64) (len Int64)] -> (Option String)
  :d "Finds main or run entrypoint in defuns list."
  (if (>= idx len)
      (none)
      (let [(d (option-or (list-get defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list))))
            (nm (.-name d))
            (low (string-lower nm))]
        (if (or (= low "main") (= low "run"))
            (some nm)
            (findEntryStep defuns (+ idx 1) len)))))

(df findEntryName [(defuns (List a/DefunNode)) (explicitEntry String)] -> String
  :d "Resolves the target entrypoint function name from explicit argument or heuristic discovery."
  (if (> (string-length explicitEntry) 0)
      explicitEntry
      (let [(mainOpt (findEntryStep defuns 0 (list-length defuns)))]
        (mt mainOpt
          ((some m) m)
          ((none)
           (if (> (list-length defuns) 0)
               (let [(d0 (option-or (list-head defuns) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list))))]
                 (.-name d0))
               ""))))))

(df collectUniqueSchemasStep [(schemas (List a/SchemaNode)) (idx Int64) (len Int64) (seen (List String)) (acc (List a/SchemaNode))] -> (List a/SchemaNode)
  :d "Accumulates unique schemas."
  (if (>= idx len)
      acc
      (let [(s (option-or (list-get schemas idx) (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none))))
            (nm (.-name s))]
        (if (list-contains? seen nm)
            (collectUniqueSchemasStep schemas (+ idx 1) len seen acc)
            (collectUniqueSchemasStep schemas (+ idx 1) len (list-append seen (list nm)) (list-append acc (list s)))))))

(df emitSchemaForwardDecl [(s a/SchemaNode)] -> String
  :d "Emits an ISO C99 forward struct declaration."
  (let [(rawName (string-trim (.-name s)))]
    (if (= rawName "")
        ""
        (let [(typeName (ct/c99TypeName rawName))]
          (str "struct " typeName "_s;")))))

(df isModuleSummarySchema? [(s a/SchemaNode)] -> Bool
  :d "Checks if schema is ModuleSummary."
  (= (.-name s) "ModuleSummary"))

(df isNotModuleSummarySchema? [(s a/SchemaNode)] -> Bool
  :d "Checks if schema is not ModuleSummary."
  (!= (.-name s) "ModuleSummary"))

(df collectUniqueSchemas [(schemas (List a/SchemaNode))] -> (List a/SchemaNode)
  :d "Removes duplicate schemas by name to prevent redefinition errors."
  (let [(allUniq (collectUniqueSchemasStep schemas 0 (list-length schemas) (list) (list)))
        (mods (filter isModuleSummarySchema? allUniq))
        (others (filter isNotModuleSummarySchema? allUniq))]
    (list-append mods others)))

(df isSchemaEmbeddingEnum? [(e a/EnumNode)] -> Bool
  :d "Checks if enum embeds schema types by value."
  (let [(nm (.-name e))]
    (or (= nm "TopForm") (= nm "EvalValue"))))

(df isNotSchemaEmbeddingEnum? [(e a/EnumNode)] -> Bool
  :d "Checks if enum does not embed schema types."
  (not (isSchemaEmbeddingEnum? e)))

(df collectUniqueEnumsStep [(enums (List a/EnumNode)) (idx Int64) (len Int64) (seen (List String)) (acc (List a/EnumNode))] -> (List a/EnumNode)
  :d "Accumulates unique enums."
  (if (>= idx len)
      acc
      (let [(e (option-or (list-get enums idx) (a/EnumNode :name "" :typeVars (list) :cases (list))))
            (nm (.-name e))]
        (if (list-contains? seen nm)
            (collectUniqueEnumsStep enums (+ idx 1) len seen acc)
            (collectUniqueEnumsStep enums (+ idx 1) len (list-append seen (list nm)) (list-append acc (list e)))))))

(df collectUniqueEnums [(enums (List a/EnumNode))] -> (List a/EnumNode)
  :d "Removes duplicate enums by name to prevent redefinition errors."
  (collectUniqueEnumsStep enums 0 (list-length enums) (list) (list)))

(df collectUniqueDefunsStep [(defuns (List a/DefunNode)) (idx Int64) (len Int64) (seen (List String)) (acc (List a/DefunNode))] -> (List a/DefunNode)
  :d "Accumulates unique defuns."
  (if (>= idx len)
      acc
      (let [(d (option-or (list-get defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list))))
            (nm (cm/mangleCIdent (.-name d)))]
        (if (list-contains? seen nm)
            (collectUniqueDefunsStep defuns (+ idx 1) len seen acc)
            (collectUniqueDefunsStep defuns (+ idx 1) len (list-append seen (list nm)) (list-append acc (list d)))))))

(df collectUniqueDefuns [(defuns (List a/DefunNode))] -> (List a/DefunNode)
  :d "Removes duplicate defuns by mangled name to prevent redefinition errors."
  (collectUniqueDefunsStep defuns 0 (list-length defuns) (list) (list)))

(df collectFormsSchemas [(forms (List a/TopForm)) (idx Int64) (len Int64) (acc (List a/SchemaNode))] -> (List a/SchemaNode)
  :d "Extracts all schema nodes from top forms."
  (if (>= idx len)
      acc
      (let [(tf (option-or (list-get forms idx) (a/topSchema (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none)))))]
        (mt tf
          ((a/topSchema s) (collectFormsSchemas forms (+ idx 1) len (list-append acc (list s))))
          (:else (collectFormsSchemas forms (+ idx 1) len acc))))))

(df collectFormsEnums [(forms (List a/TopForm)) (idx Int64) (len Int64) (acc (List a/EnumNode))] -> (List a/EnumNode)
  :d "Extracts all enum nodes from top forms."
  (if (>= idx len)
      acc
      (let [(tf (option-or (list-get forms idx) (a/topSchema (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none)))))]
        (mt tf
          ((a/topEnum e) (collectFormsEnums forms (+ idx 1) len (list-append acc (list e))))
          (:else (collectFormsEnums forms (+ idx 1) len acc))))))

(df collectFormsDefuns [(forms (List a/TopForm)) (idx Int64) (len Int64) (acc (List a/DefunNode))] -> (List a/DefunNode)
  :d "Extracts all defun nodes from top forms."
  (if (>= idx len)
      acc
      (let [(tf (option-or (list-get forms idx) (a/topSchema (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none)))))]
        (mt tf
          ((a/topDefun d) (collectFormsDefuns forms (+ idx 1) len (list-append acc (list d))))
          (:else (collectFormsDefuns forms (+ idx 1) len acc))))))

(df isNonEmptyString? [(s String)] -> Bool
  :d "Checks if string has non-zero length."
  (> (string-length s) 0))

(df findEntryDefun [(defuns (List a/DefunNode)) (name String) (idx Int64) (len Int64)] -> (Option a/DefunNode)
  :d "Finds defun matching target entry name."
  (if (>= idx len)
      (none)
      (let [(d (option-or (list-get defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list))))]
        (if (= (.-name d) name)
            (some d)
            (findEntryDefun defuns name (+ idx 1) len)))))

(df emitCHeaderFile [(mod a/ModuleNode)] -> String
  :d "Projects an ASL module into a standalone ISO C99 header (.h) with include guards and prototypes."
  (let [(modPath (.-path mod))
        (defs (.-defs mod))
        (schemas (collectFormsSchemas defs 0 (list-length defs) (list)))
        (enums (collectFormsEnums defs 0 (list-length defs) (list)))
        (defuns (collectFormsDefuns defs 0 (list-length defs) (list)))
        (uniqSchemas (collectUniqueSchemas schemas))
        (uniqEnums (collectUniqueEnums enums))
        (simpleEnums (filter isNotSchemaEmbeddingEnum? uniqEnums))
        (complexEnums (filter isSchemaEmbeddingEnum? uniqEnums))
        (hdrIncludes (emitCStandardIncludes false))
        (strType (ct/emitCStringType))
        (forwardSchemas (map emitSchemaForwardDecl uniqSchemas))
        (simpleEnumStrs (map ct/emitCDefenum simpleEnums))
        (schemaStrs (map ct/emitCDefschema uniqSchemas))
        (complexEnumStrs (map ct/emitCDefenum complexEnums))
        (protoStrs (map emitCFunctionPrototype defuns))
        (protoBlock (if (<= (list-length protoStrs) 0)
                        ""
                        (emitCExternCWrapper (string-join protoStrs "\n"))))
        (sections (filter isNonEmptyString?
                          (list hdrIncludes strType (string-join forwardSchemas "\n") (string-join simpleEnumStrs "\n") (string-join schemaStrs "\n") (string-join complexEnumStrs "\n") protoBlock)))
        (bodyContent (string-join sections "\n\n"))]
    (emitCHeaderGuards modPath bodyContent)))

(df emitCSourceFile [(mod a/ModuleNode)] -> String
  :d "Projects an ASL module into an ISO C99 implementation (.c) file with prototypes and function definitions."
  (let [(defs (.-defs mod))
        (defuns (collectFormsDefuns defs 0 (list-length defs) (list)))
        (preamble (emitCHostedPreamble))
        (protoStrs (map emitCFunctionPrototype defuns))
        (fnDefs (map emitCFunctionDef defuns))
        (sections (filter isNonEmptyString?
                          (list preamble (string-join protoStrs "\n") (string-join fnDefs "\n"))))]
    (str (string-join sections "\n\n") "\n")))

(df emitCStandalone [(forms (List a/TopForm)) (entryFn String) (isFreestanding Bool)] -> String
  :d "Emits a complete, self-contained single-file ISO C99 translation unit ready for instant compiler invocation."
  (let [(schemas (collectFormsSchemas forms 0 (list-length forms) (list)))
        (enums (collectFormsEnums forms 0 (list-length forms) (list)))
        (defuns (collectFormsDefuns forms 0 (list-length forms) (list)))
        (uniqSchemas (collectUniqueSchemas schemas))
        (uniqEnums (collectUniqueEnums enums))
        (simpleEnums (filter isNotSchemaEmbeddingEnum? uniqEnums))
        (complexEnums (filter isSchemaEmbeddingEnum? uniqEnums))
        (uniqDefuns (collectUniqueDefuns defuns))
        (preamble (if isFreestanding (emitCFreestandingPreamble) (emitCHostedPreamble)))
        (forwardSchemas (map emitSchemaForwardDecl uniqSchemas))
        (simpleEnumStrs (map ct/emitCDefenum simpleEnums))
        (schemaStrs (map ct/emitCDefschema uniqSchemas))
        (complexEnumStrs (map ct/emitCDefenum complexEnums))
        (protoStrs (map emitCFunctionPrototype uniqDefuns))
        (fnDefs (map emitCFunctionDef uniqDefuns))
        (actualEntry (findEntryName uniqDefuns entryFn))
        (entryDefunOpt (findEntryDefun defuns actualEntry 0 (list-length defuns)))
        (hasArgs (mt entryDefunOpt
                   ((some d) (> (list-length (.-params d)) 0))
                   ((none) false)))
        (mainEntry (emitCMainEntryWithArgs actualEntry isFreestanding hasArgs))
        (sections (filter isNonEmptyString?
                          (list preamble
                                (string-join forwardSchemas "\n")
                                (string-join simpleEnumStrs "\n")
                                (string-join schemaStrs "\n")
                                (string-join complexEnumStrs "\n")
                                (string-join protoStrs "\n")
                                (string-join fnDefs "\n")
                                mainEntry)))]
    (str (string-join sections "\n\n") "\n")))

(df assembleCModule [(mod a/ModuleNode) (isFreestanding Bool)] -> String
  :d "Assembles an entire ASL module node into an ISO C99 translation unit."
  (emitCStandalone (.-defs mod) "" isFreestanding))
