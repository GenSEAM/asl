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
      emitSchemaForwardDecl
      emitEnumForwardDecl
      collectFormsSchemas
      collectFormsEnums
      collectFormsDefuns]
  :i [(ast :a a) (reader :a rd) (c99Mangle :a cm) (c99Type :a ct) (c99Expr :a ce)])

(df emitCHeaderGuards [(modName String) (content String)] -> String
  :d "Wraps C header content with canonical preprocessor include guards."
  (let [(p0 (string-replace (string-replace (string-replace modName "/" "_") "-" "_") "." "_"))
        (u0 (string-upper p0))
        (u1 (if (string-starts-with? u0 "ASL_") u0 (str "ASL_" u0)))
        (guard (if (string-ends-with? u1 "_H") u1 (str u1 "_H")))]
    (str "#ifndef " guard "\n#define " guard "\n\n" content "\n\n#endif\n")))

(df emitCStandardIncludes [(isFreestanding Bool)] -> String
  :d "Emits ISO C99 standard header includes for the freestanding or hosted preset. The hosted preset must request POSIX.1-2008 before any libc header, because glibc latches the feature-test state in the first header it sees and a later request is then a no-op, which silently removes realpath and clock_gettime under -std=c99."
  (if isFreestanding
      "#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>"
      "#ifndef _POSIX_C_SOURCE\n#define _POSIX_C_SOURCE 200809L\n#endif\n\n#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>"))

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

(df emitParamsStrStep [(ps (List a/Param)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Formats function parameter prototypes recursively without generic map."
  (if (>= idx len)
      (list-reverse acc)
      (let [(p (option-or (list-get ps idx) (a/Param :name "" :type "Unit")))]
        (emitParamsStrStep ps (+ idx 1) len (list-cons (emitParamPrototype p) acc)))))

(df emitParamsStr [(ps (List a/Param))] -> String
  :d "Formats parameter string for prototype or function definition."
  (if (<= (list-length ps) 0)
      "void"
      (string-join (emitParamsStrStep ps 0 (list-length ps) (list)) ", ")))

(df emitVoidParamsStep [(ps (List a/Param)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Emits (void)paramName; statements to silence -Wunused-parameter under -Werror."
  (if (>= idx len)
      (list-reverse acc)
      (let [(p (option-or (list-get ps idx) (a/Param :name "" :type "Unit")))
            (pName (cm/mangleCIdent (.-name p)))]
        (emitVoidParamsStep ps (+ idx 1) len (list-cons (str "    (void)" pName ";") acc)))))

(df emitSchemaForwardDeclsStep [(schemas (List a/SchemaNode)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Emits forward declarations for schemas recursively."
  (if (>= idx len)
      (list-reverse acc)
      (let [(s (option-or (list-get schemas idx) (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none))))]
        (emitSchemaForwardDeclsStep schemas (+ idx 1) len (list-cons (emitSchemaForwardDecl s) acc)))))

(df emitEnumForwardDeclsStep [(enums (List a/EnumNode)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Emits forward declarations for enums recursively."
  (if (>= idx len)
      (list-reverse acc)
      (let [(e (option-or (list-get enums idx) (a/EnumNode :name "" :typeVars (list) :cases (list))))]
        (emitEnumForwardDeclsStep enums (+ idx 1) len (list-cons (emitEnumForwardDecl e) acc)))))

(df emitCDefenumsStep [(enums (List a/EnumNode)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Emits enum definitions recursively."
  (if (>= idx len)
      (list-reverse acc)
      (let [(e (option-or (list-get enums idx) (a/EnumNode :name "" :typeVars (list) :cases (list))))]
        (emitCDefenumsStep enums (+ idx 1) len (list-cons (ct/emitCDefenum e) acc)))))

(df emitCDefschemasStep [(schemas (List a/SchemaNode)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Emits schema definitions recursively."
  (if (>= idx len)
      (list-reverse acc)
      (let [(s (option-or (list-get schemas idx) (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none))))]
        (emitCDefschemasStep schemas (+ idx 1) len (list-cons (ct/emitCDefschema s) acc)))))

(df emitCFunctionPrototypesStep [(defuns (List a/DefunNode)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Emits function prototypes recursively."
  (if (>= idx len)
      (list-reverse acc)
      (let [(d (option-or (list-get defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list))))]
        (emitCFunctionPrototypesStep defuns (+ idx 1) len (list-cons (emitCFunctionPrototype d) acc)))))

(df emitCFunctionPrototype [(fn a/DefunNode)] -> String
  :d "Formats an ISO C99 forward function prototype declaration."
  (let [(rawRet (.-retType fn))
        (retTy (ct/c99TypeStr rawRet))
        (fnName (cm/mangleCIdent (.-name fn)))
        (params (.-params fn))
        (paramStr (emitParamsStr params))
        (proto (str retTy " " fnName "(" paramStr ");"))]
    (if (string-starts-with? fnName "asl_is_")
        (let [(shortName (cm/sliceOr fnName 4 (string-length fnName) ""))]
          (str "#ifndef " shortName "\n#define " shortName " " fnName "\n#endif\n" proto))
        proto)))

(df ctxOfParamsStep [(ctx ce/LowerCtx) (ps (List a/Param)) (idx Int64) (len Int64)] -> ce/LowerCtx
  :d "Seeds the lowering context with each declared parameter and its emitted C type."
  (if (>= idx len)
      ctx
      (let [(p (option-or (list-get ps idx) (a/Param :name "" :type "Unit")))]
        (ctxOfParamsStep (ce/ctxWithVar ctx (.-name p) (ct/c99TypeStr (.-type p))) ps (+ idx 1) len))))

(df fnRetTypes [(defuns (List a/DefunNode))] -> (Map String String)
  :d "Collects every defun's declared C return type, so a let binding on a call takes its type from the callee's signature instead of from the lowered text."
  (fold (fn [(acc (Map String String)) (d a/DefunNode)] -> (Map String String)
          (map-set acc (.-name d) (ct/c99TypeStr (.-retType d))))
        (map-empty)
        defuns))

(df ctxOfDefun [(fn a/DefunNode) (fnTypes (Map String String))] -> ce/LowerCtx
  :d "Builds the lowering context a function body is lowered under, from its declared signature and the signatures of every function it can call."
  (let [(base (ce/LowerCtx :vars (list) :substs (list) :fns fnTypes :retTy (ct/c99TypeStr (.-retType fn))))]
    (ctxOfParamsStep base (.-params fn) 0 (list-length (.-params fn)))))

(df emitInitStmtsStep [(ctx ce/LowerCtx) (es (List rd/SExpr)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Formats intermediate body expressions as C statements under the enclosing context."
  (if (>= idx len)
      (list-reverse acc)
      (let [(e (option-or (list-get es idx) (rd/sexprAtom "()")))]
        (emitInitStmtsStep ctx es (+ idx 1) len (list-cons (emitInitStmt ctx e) acc)))))

(df emitInitStmt [(ctx ce/LowerCtx) (e rd/SExpr)] -> String
  :d "Formats an intermediate SExpr as a C statement."
  (let [(s (ce/lowerCExpr ctx e))]
    (if (or (string-ends-with? s ";") (string-ends-with? s "}"))
        (str "    " s)
        (str "    " s ";"))))

(df emitCFunctionDefsStep [(defuns (List a/DefunNode)) (fnTypes (Map String String)) (idx Int64) (len Int64) (acc (List String))] -> (List String)
  :d "Lowers each function definition under the shared signature table, threading it explicitly rather than through a closure."
  (if (>= idx len)
      (list-reverse acc)
      (let [(d (option-or (list-get defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list))))]
        (emitCFunctionDefsStep defuns fnTypes (+ idx 1) len (list-cons (emitCFunctionDef d fnTypes) acc)))))

(df emitCFunctionDef [(fn a/DefunNode) (fnTypes (Map String String))] -> String
  :d "Lowers a typed defun AST node into an ISO C99 function implementation."
  (let [(rawRet (.-retType fn))
        (retTy (ct/c99TypeStr rawRet))
        (fnName (cm/mangleCIdent (.-name fn)))
        (params (.-params fn))
        (paramStr (emitParamsStr params))
        (voidParams (emitVoidParamsStep params 0 (list-length params) (list)))
        (voidPrefix (if (> (list-length voidParams) 0)
                        (str (string-join voidParams "\n") "\n")
                        ""))
        (bodyCtx (ctxOfDefun fn fnTypes))
        (body (.-body fn))
        (bodyLen (list-length body))]
    (cond
      ((<= bodyLen 0)
       (if (= retTy "void")
           (str retTy " " fnName "(" paramStr ") {\n" voidPrefix "    return;\n}\n")
           (str retTy " " fnName "(" paramStr ") {\n" voidPrefix "    return (" retTy "){0};\n}\n")))
      ((= bodyLen 1)
       (let [(soleExpr (option-or (list-get body 0) (rd/sexprAtom "()")))
             (lowered (ce/lowerCExpr bodyCtx soleExpr))]
         (if (= retTy "void")
             (if (or (string-ends-with? lowered "}") (string-ends-with? lowered ";"))
                 (str retTy " " fnName "(" paramStr ") {\n" voidPrefix "    " lowered "\n    return;\n}\n")
                 (str retTy " " fnName "(" paramStr ") {\n" voidPrefix "    " lowered ";\n    return;\n}\n"))
             (if (string-starts-with? lowered "{")
                 (let [(wrapped (ce/wrapBlockWithReturn lowered))]
                   (let [(inner (cm/sliceOr wrapped 1 (- (string-length wrapped) 1) ""))]
                     (str retTy " " fnName "(" paramStr ") {\n" voidPrefix inner "\n    return (" retTy "){0};\n}\n")))
                 (if (or (string-starts-with? lowered "switch")
                         (string-starts-with? lowered "if"))
                     (str retTy " " fnName "(" paramStr ") {\n" voidPrefix "    " lowered "\n    return (" retTy "){0};\n}\n")
                     (str retTy " " fnName "(" paramStr ") {\n" voidPrefix "    return " lowered ";\n}\n"))))))
      (:else
       (let [(initExprs (option-or (list-slice body 0 (- bodyLen 1)) (list)))
             (lastExpr (option-or (list-get body (- bodyLen 1)) (rd/sexprAtom "()")))
             (initStmts (emitInitStmtsStep bodyCtx initExprs 0 (list-length initExprs) (list)))
             (lastLowered (ce/lowerCExpr bodyCtx lastExpr))
             (lastStmt (if (= retTy "void")
                           (if (or (string-ends-with? lastLowered ";") (string-ends-with? lastLowered "}"))
                               (str "    " lastLowered "\n    return;")
                               (str "    " lastLowered ";\n    return;"))
                           (if (or (string-starts-with? lastLowered "switch")
                                   (string-starts-with? lastLowered "if"))
                               (str "    " lastLowered "\n    return (" retTy "){0};")
                               (if (string-starts-with? lastLowered "{")
                                   (let [(wrapped (ce/wrapBlockWithReturn lastLowered))]
                                     (let [(inner (cm/sliceOr wrapped 1 (- (string-length wrapped) 1) ""))]
                                       (str inner "\n    return (" retTy "){0};")))
                                   (str "    return " lastLowered ";")))))]
         (str retTy " " fnName "(" paramStr ") {\n"
              voidPrefix
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
                     "    int exit_code = (" mangled "(args).tag == 0) ? 0 : 1;\n"
                     "    free(args_items);\n"
                     "    return exit_code;\n"
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

(df collectUniqueSchemasStep [(schemas (List a/SchemaNode)) (idx Int64) (len Int64) (seen (Map String Bool)) (acc (List a/SchemaNode))] -> (List a/SchemaNode)
  :d "Accumulates unique schemas."
  (if (>= idx len)
      (list-reverse acc)
      (let [(s (option-or (list-get schemas idx) (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none))))
            (nm (.-name s))]
        (if (map-has? seen nm)
            (collectUniqueSchemasStep schemas (+ idx 1) len seen acc)
            (collectUniqueSchemasStep schemas (+ idx 1) len (map-set seen nm true) (list-cons s acc))))))

(df emitSchemaForwardDecl [(s a/SchemaNode)] -> String
  :d "Emits an ISO C99 forward struct declaration and typedef for a schema."
  (let [(rawName (string-trim (.-name s)))]
    (if (= rawName "")
        ""
        (let [(typeName (ct/c99TypeName rawName))]
          (str "#ifndef " typeName "_FWD_DEFINED\n#define " typeName "_FWD_DEFINED\nstruct " typeName "_s;\ntypedef struct " typeName "_s " typeName ";\n#endif")))))

(df emitEnumForwardDecl [(e a/EnumNode)] -> String
  :d "Emits an ISO C99 forward struct and typedef declaration for an enum."
  (let [(rawName (string-trim (.-name e)))]
    (if (= rawName "")
        ""
        (let [(typeName (ct/c99TypeName rawName))]
          (str "#ifndef " typeName "_FWD_DEFINED\n#define " typeName "_FWD_DEFINED\nstruct " typeName "_s;\ntypedef struct " typeName "_s " typeName ";\n#endif")))))

(df isModuleSummarySchema? [(s a/SchemaNode)] -> Bool
  :d "Checks if schema is ModuleSummary."
  (= (.-name s) "ModuleSummary"))

(df isNotModuleSummarySchema? [(s a/SchemaNode)] -> Bool
  :d "Checks if schema is not ModuleSummary."
  (!= (.-name s) "ModuleSummary"))

(df collectUniqueSchemas [(schemas (List a/SchemaNode))] -> (List a/SchemaNode)
  :d "Removes duplicate schemas by name to prevent redefinition errors."
  (let [(allUniq (collectUniqueSchemasStep schemas 0 (list-length schemas) (map-empty) (list)))
        (mods (filter isModuleSummarySchema? allUniq))
        (others (filter isNotModuleSummarySchema? allUniq))]
    (list-append others mods)))

(df isDependentSchema? [(s a/SchemaNode)] -> Bool
  :d "Checks if a schema embeds container types of other schemas by value and must be emitted after valueTypedefs."
  (let [(nm (.-name s))]
    (or (= nm "ReadState")
        (or (= nm "LexState")
            (or (= nm "ScanState")
                (= nm "FrameMachine"))))))

(df isIndependentSchema? [(s a/SchemaNode)] -> Bool
  :d "Checks if a schema does not embed container types of other schemas."
  (not (isDependentSchema? s)))

(df isSchemaEmbeddingEnum? [(e a/EnumNode)] -> Bool
  :d "Checks if enum embeds schema types by value."
  (let [(nm (.-name e))]
    (or (= nm "TopForm") (= nm "EvalValue"))))

(df isNotSchemaEmbeddingEnum? [(e a/EnumNode)] -> Bool
  :d "Checks if enum does not embed schema types."
  (not (isSchemaEmbeddingEnum? e)))

(df collectUniqueEnumsStep [(enums (List a/EnumNode)) (idx Int64) (len Int64) (seen (Map String Bool)) (acc (List a/EnumNode))] -> (List a/EnumNode)
  :d "Accumulates unique enums."
  (if (>= idx len)
      (list-reverse acc)
      (let [(e (option-or (list-get enums idx) (a/EnumNode :name "" :typeVars (list) :cases (list))))
            (nm (.-name e))]
        (if (map-has? seen nm)
            (collectUniqueEnumsStep enums (+ idx 1) len seen acc)
            (collectUniqueEnumsStep enums (+ idx 1) len (map-set seen nm true) (list-cons e acc))))))

(df collectUniqueEnums [(enums (List a/EnumNode))] -> (List a/EnumNode)
  :d "Removes duplicate enums by name to prevent redefinition errors."
  (collectUniqueEnumsStep enums 0 (list-length enums) (map-empty) (list)))

(df collectUniqueDefunsStep [(defuns (List a/DefunNode)) (idx Int64) (len Int64) (seen (Map String Bool)) (acc (List a/DefunNode))] -> (List a/DefunNode)
  :d "Accumulates unique defuns."
  (if (>= idx len)
      (list-reverse acc)
      (let [(d (option-or (list-get defuns idx) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list))))
            (nm (cm/mangleCIdent (.-name d)))]
        (if (map-has? seen nm)
            (collectUniqueDefunsStep defuns (+ idx 1) len seen acc)
            (collectUniqueDefunsStep defuns (+ idx 1) len (map-set seen nm true) (list-cons d acc))))))

(df collectUniqueDefuns [(defuns (List a/DefunNode))] -> (List a/DefunNode)
  :d "Removes duplicate defuns by mangled name to prevent redefinition errors."
  (collectUniqueDefunsStep defuns 0 (list-length defuns) (map-empty) (list)))

(df collectFormsSchemas [(forms (List a/TopForm)) (idx Int64) (len Int64) (acc (List a/SchemaNode))] -> (List a/SchemaNode)
  :d "Extracts all schema nodes from top forms."
  (if (>= idx len)
      (list-reverse acc)
      (let [(tf (option-or (list-get forms idx) (a/topSchema (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none)))))]
        (mt tf
          ((a/topSchema s) (collectFormsSchemas forms (+ idx 1) len (list-cons s acc)))
          (:else (collectFormsSchemas forms (+ idx 1) len acc))))))

(df collectFormsEnums [(forms (List a/TopForm)) (idx Int64) (len Int64) (acc (List a/EnumNode))] -> (List a/EnumNode)
  :d "Extracts all enum nodes from top forms."
  (if (>= idx len)
      (list-reverse acc)
      (let [(tf (option-or (list-get forms idx) (a/topSchema (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none)))))]
        (mt tf
          ((a/topEnum e) (collectFormsEnums forms (+ idx 1) len (list-cons e acc)))
          (:else (collectFormsEnums forms (+ idx 1) len acc))))))

(df collectFormsDefuns [(forms (List a/TopForm)) (idx Int64) (len Int64) (acc (List a/DefunNode))] -> (List a/DefunNode)
  :d "Extracts all defun nodes from top forms."
  (if (>= idx len)
      (list-reverse acc)
      (let [(tf (option-or (list-get forms idx) (a/topSchema (a/SchemaNode :name "" :typeVars (list) :fields (list) :jsonCase (none)))))]
        (mt tf
          ((a/topDefun d) (collectFormsDefuns forms (+ idx 1) len (list-cons d acc)))
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
        (independentSchemas (filter isIndependentSchema? uniqSchemas))
        (dependentSchemas (filter isDependentSchema? uniqSchemas))
        (hdrIncludes (emitCStandardIncludes false))
        (strType (ct/emitCStringType))
        (forwardSchemas (emitSchemaForwardDeclsStep uniqSchemas 0 (list-length uniqSchemas) (list)))
        (forwardEnums (emitEnumForwardDeclsStep uniqEnums 0 (list-length uniqEnums) (list)))
        (allForwardTypes (string-join (list-append forwardSchemas forwardEnums) "\n"))
        (simpleEnumStrs (emitCDefenumsStep simpleEnums 0 (list-length simpleEnums) (list)))
        (indepSchemaStrs (emitCDefschemasStep independentSchemas 0 (list-length independentSchemas) (list)))
        (complexEnumStrs (emitCDefenumsStep complexEnums 0 (list-length complexEnums) (list)))
        (depSchemaStrs (emitCDefschemasStep dependentSchemas 0 (list-length dependentSchemas) (list)))
        (protoStrs (emitCFunctionPrototypesStep defuns 0 (list-length defuns) (list)))
        (protoBlock (if (<= (list-length protoStrs) 0)
                        ""
                        (emitCExternCWrapper (string-join protoStrs "\n"))))
        (sections (filter isNonEmptyString?
                          (list hdrIncludes strType allForwardTypes (string-join simpleEnumStrs "\n") (string-join indepSchemaStrs "\n") (string-join complexEnumStrs "\n") (string-join depSchemaStrs "\n") protoBlock)))
        (bodyContent (string-join sections "\n\n"))]
    (emitCHeaderGuards modPath bodyContent)))

(df emitCSourceFile [(mod a/ModuleNode)] -> String
  :d "Projects an ASL module into an ISO C99 implementation (.c) file with prototypes and function definitions."
  (let [(defs (.-defs mod))
        (defuns (collectFormsDefuns defs 0 (list-length defs) (list)))
        (preamble (emitCHostedPreamble))
        (protoStrs (emitCFunctionPrototypesStep defuns 0 (list-length defuns) (list)))
        (fnDefs (emitCFunctionDefsStep defuns (fnRetTypes defuns) 0 (list-length defuns) (list)))
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
        (independentSchemas (filter isIndependentSchema? uniqSchemas))
        (dependentSchemas (filter isDependentSchema? uniqSchemas))
        (uniqDefuns (collectUniqueDefuns defuns))
        (preamble (if isFreestanding (emitCFreestandingPreamble) (emitCHostedPreamble)))
        (forwardSchemas (emitSchemaForwardDeclsStep uniqSchemas 0 (list-length uniqSchemas) (list)))
        (forwardEnums (emitEnumForwardDeclsStep uniqEnums 0 (list-length uniqEnums) (list)))
        (uniqInsts (ct/dedupeInsts (ct/collectAllInsts forms)))
        (instForwardTypes (ct/emitInstForwardDeclsFromUniq uniqInsts))
        (allForwardTypes (string-join (list-append (list-append forwardSchemas forwardEnums) (list instForwardTypes)) "\n"))
        (sliceTypedefs (ct/emitInstTypedefsFromUniq uniqInsts true))
        (valueTypedefs (ct/emitInstTypedefsFromUniq uniqInsts false))
        (instAccessors (ct/emitInstAccessorsFromUniq uniqInsts))
        (simpleEnumStrs (emitCDefenumsStep simpleEnums 0 (list-length simpleEnums) (list)))
        (indepSchemaStrs (emitCDefschemasStep independentSchemas 0 (list-length independentSchemas) (list)))
        (complexEnumStrs (emitCDefenumsStep complexEnums 0 (list-length complexEnums) (list)))
        (depSchemaStrs (emitCDefschemasStep dependentSchemas 0 (list-length dependentSchemas) (list)))
        (protoStrs (emitCFunctionPrototypesStep uniqDefuns 0 (list-length uniqDefuns) (list)))
        (fnTypes (fnRetTypes uniqDefuns))
        (fnDefs (emitCFunctionDefsStep uniqDefuns fnTypes 0 (list-length uniqDefuns) (list)))
        (actualEntry (findEntryName uniqDefuns entryFn))
        (entryDefunOpt (findEntryDefun defuns actualEntry 0 (list-length defuns)))
        (hasArgs (mt entryDefunOpt
                   ((some d) (> (list-length (.-params d)) 0))
                   ((none) false)))
        (mainEntry (emitCMainEntryWithArgs actualEntry isFreestanding hasArgs))
        (sections (filter isNonEmptyString?
                          (list preamble
                                allForwardTypes
                                sliceTypedefs
                                (string-join simpleEnumStrs "\n")
                                (string-join indepSchemaStrs "\n")
                                (string-join complexEnumStrs "\n")
                                valueTypedefs
                                (string-join depSchemaStrs "\n")
                                instAccessors
                                (string-join protoStrs "\n")
                                (string-join fnDefs "\n")
                                mainEntry)))]
    (str (string-join sections "\n\n") "\n")))

(df assembleCModule [(mod a/ModuleNode) (isFreestanding Bool)] -> String
  :d "Assembles an entire ASL module node into an ISO C99 translation unit."
  (emitCStandalone (.-defs mod) "" isFreestanding))
