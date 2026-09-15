(module asl-codegen/c99EmitTest
  :d "Unit tests"
  :x [testHeaderGuards testStandardIncludes testExternCWrapper testFunctionPrototype testFunctionDef testMainEntry testHeaderFileProjection testSourceFileProjection testStandaloneProjection testDualPolarityRefutations runTests]
  :i [(c99Emit :a ce) (ast :a a) (reader :a rd)])

(df testHeaderGuards [] -> Bool
  (let [(hdr (ce/emitCHeaderGuards "demo/math" "/* declarations */"))]
    (assert (string-contains? hdr "#ifndef ASL_DEMO_MATH_H") "guard ifndef")
    true))

(df testStandardIncludes [] -> Bool
  (let [(free (ce/emitCStandardIncludes true))
        (host (ce/emitCStandardIncludes false))]
    (assert (string-contains? free "<stdint.h>") "freestanding has stdint")
    (assert (string-contains? host "<stdio.h>") "hosted has stdio")
    true))
(df testExternCWrapper [] -> Bool
  (let [(res (ce/emitCExternCWrapper "int foo(void);"))]
    (assert (string-contains? res "#ifdef __cplusplus") "extern wrapper ifdef")
    true))
(df testFunctionPrototype [] -> Bool
  (let [(fn1 (a/DefunNode :name "add" :typeVars (list) :isExported true :effect false
                          :params (list (a/Param :name "a" :type "Int64") (a/Param :name "b" :type "Int64"))
                          :retType "Int64" :docstring "" :body (list (rd/makeAtom "0"))))
        (p1 (ce/emitCFunctionPrototype fn1))]
    (assert (string-contains? p1 "int64_t add(int64_t a, int64_t b);") "prototype add")
    true))
(df testFunctionDef [] -> Bool
  (let [(fn1 (a/DefunNode :name "add" :typeVars (list) :isExported true :effect false
                          :params (list (a/Param :name "a" :type "Int64") (a/Param :name "b" :type "Int64"))
                          :retType "Int64" :docstring ""
                          :body (list (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "a") (rd/makeAtom "b"))))))
        (d1 (ce/emitCFunctionDef fn1))]
    (assert (string-contains? d1 "int64_t add(int64_t a, int64_t b) {") "def signature")
    true))
(df testMainEntry [] -> Bool
  (let [(mHost (ce/emitCMainEntry "run" false))
        (mFree (ce/emitCMainEntry "run" true))]
    (assert (string-contains? mHost "int main(int argc, char** argv)") "hosted main signature")
    (assert (string-contains? mFree "void setup(void)") "freestanding setup")
    true))
(df sampleModuleNode [] -> a/ModuleNode
  (let [(pSchema (a/SchemaNode :name "Point" :typeVars (list)
                               :fields (list (a/AstField :name "x" :type "Int64" :docstring "" :default (none) :json (none))
                                             (a/AstField :name "y" :type "Int64" :docstring "" :default (none) :json (none)))
                               :jsonCase (none)))
        (fnAdd (a/DefunNode :name "add" :typeVars (list) :isExported true :effect false
                            :params (list (a/Param :name "a" :type "Int64") (a/Param :name "b" :type "Int64"))
                            :retType "Int64" :docstring ""
                            :body (list (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "a") (rd/makeAtom "b"))))))
        (defs (list (a/topSchema pSchema) (a/topDefun fnAdd)))]
    (a/ModuleNode :path "demo/math" :docstring "" :exported (list "add") :imports (list) :defs defs)))
(df testHeaderFileProjection [] -> Bool
  (let [(modNode (sampleModuleNode))
        (hdr (ce/emitCHeaderFile modNode))]
    (assert (string-contains? hdr "#ifndef ASL_DEMO_MATH_H") "hdr guard")
    (assert (string-contains? hdr "typedef struct AslPoint_s {") "hdr struct")
    (assert (string-contains? hdr "int64_t add(int64_t a, int64_t b);") "hdr add proto")
    true))
(df testSourceFileProjection [] -> Bool
  (let [(modNode (sampleModuleNode))
        (src (ce/emitCSourceFile modNode))]
    (assert (string-contains? src "int64_t add(int64_t a, int64_t b) {") "src add def")
    true))
(df testStandaloneProjection [] -> Bool
  (let [(modNode (sampleModuleNode))
        (cHosted (ce/emitCStandalone (.-defs modNode) "main" false))
        (cFree (ce/emitCStandalone (.-defs modNode) "main" true))]
    (assert (string-contains? cHosted "int main(int argc, char** argv)") "hosted main")
    (assert (not (string-contains? cFree "<stdio.h>")) "freestanding no stdio")
    true))
(df testDualPolarityRefutations [] -> Bool
  :d "Verifies dual-polarity refutations under D77."
  (let [(modNode (sampleModuleNode))
        (hdr (ce/emitCHeaderFile modNode))
        (cFree (ce/emitCStandalone (.-defs modNode) "main" true))]
    (refute (string-contains? hdr "return ") "header file must not contain return statements")
    (refute (string-contains? cFree "<stdio.h>") "freestanding mode must not include stdio.h")
    (refute (string-contains? cFree "malloc") "freestanding mode must not call malloc")
    (refute (string-contains? cFree "free(") "freestanding mode must not call free")
    true))

(df runTests [] -> Bool
  (do
    (assert (testHeaderGuards) "testHeaderGuards")
    (assert (testStandardIncludes) "testStandardIncludes")
    (assert (testExternCWrapper) "testExternCWrapper")
    (assert (testFunctionPrototype) "testFunctionPrototype")
    (assert (testFunctionDef) "testFunctionDef")
    (assert (testMainEntry) "testMainEntry")
    (assert (testHeaderFileProjection) "testHeaderFileProjection")
    (assert (testSourceFileProjection) "testSourceFileProjection")
    (assert (testStandaloneProjection) "testStandaloneProjection")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations")
    true))