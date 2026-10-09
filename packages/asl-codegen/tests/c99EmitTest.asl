(module asl-codegen/c99EmitTest :x [testHeaderGuards testStandardIncludes testExternCWrapper testFunctionPrototype testFunctionDef testMainEntry testHeaderFileProjection testSourceFileProjection testStandaloneProjection testDualPolarityRefutations testC99LocalizedSampleFixture! runTests] :i [(c99Emit :a ce) (ast :a a) (reader :a rd)])

fn testHeaderGuards -> Bool
  (let [(hdr (ce/emitCHeaderGuards "demo/math" "/* declarations */"))] (assert (stringContains? hdr "#ifndef ASL_DEMO_MATH_H") "guard ifndef") true)

fn testStandardIncludes -> Bool
  (let [(free (ce/emitCStandardIncludes true)) (host (ce/emitCStandardIncludes false))] (assert (stringContains? free "<stdint.h>") "freestanding has stdint") (assert (stringContains? host "<stdio.h>") "hosted has stdio") (assert (stringContains? host "_POSIX_C_SOURCE") "hosted preset requests POSIX.1-2008") (assert (< (optionOr (stringIndexOf host "_POSIX_C_SOURCE") 999999) (optionOr (stringIndexOf host "<stdio.h>") 0)) "the POSIX request precedes every libc header, because glibc latches the feature-test state in the first header it sees") (refute (stringContains? free "_POSIX_C_SOURCE") "the freestanding preset asks for no POSIX surface") true)

fn testExternCWrapper -> Bool
  (let [(res (ce/emitCExternCWrapper "int foo(void);"))] (assert (stringContains? res "#ifdef __cplusplus") "extern wrapper ifdef") true)

fn testFunctionPrototype -> Bool
  (let [(fn1 (a/DefunNode :name "add" :typeVars (list) :isExported true :effect false :params (list (a/Param :name "a" :type "Int64") (a/Param :name "b" :type "Int64")) :retType "Int64" :docstring "" :body (list (rd/makeAtom "0")))) (p1 (ce/emitCFunctionPrototype fn1))] (assert (stringContains? p1 "int64_t add(int64_t a, int64_t b);") "prototype add") true)

fn testFunctionDef -> Bool
  (let [(fn1 (a/DefunNode :name "add" :typeVars (list) :isExported true :effect false :params (list (a/Param :name "a" :type "Int64") (a/Param :name "b" :type "Int64")) :retType "Int64" :docstring "" :body (list (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "a") (rd/makeAtom "b")))))) (d1 (ce/emitCFunctionDef fn1 (mapEmpty)))] (assert (stringContains? d1 "int64_t add(int64_t a, int64_t b) {") "def signature") true)

fn testMainEntry -> Bool
  (let [(mHost (ce/emitCMainEntry "run" false)) (mFree (ce/emitCMainEntry "run" true))] (assert (stringContains? mHost "int main(int argc, char** argv)") "hosted main signature") (assert (stringContains? mFree "void setup(void)") "freestanding setup") true)

fn sampleModuleNode -> a/ModuleNode
  (let [(pSchema (a/SchemaNode :name "Point" :typeVars (list) :fields (list (a/AstField :name "x" :type "Int64" :docstring "" :default (none) :json (none)) (a/AstField :name "y" :type "Int64" :docstring "" :default (none) :json (none))) :jsonCase (none))) (fnAdd (a/DefunNode :name "add" :typeVars (list) :isExported true :effect false :params (list (a/Param :name "a" :type "Int64") (a/Param :name "b" :type "Int64")) :retType "Int64" :docstring "" :body (list (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "a") (rd/makeAtom "b")))))) (defs (list (a/topSchema pSchema) (a/topDefun fnAdd)))] (a/ModuleNode :path "demo/math" :docstring "" :exported (list "add") :imports (list) :defs defs))

fn testHeaderFileProjection -> Bool
  (let [(modNode (sampleModuleNode)) (hdr (ce/emitCHeaderFile modNode))] (assert (stringContains? hdr "#ifndef ASL_DEMO_MATH_H") "hdr guard") (assert (stringContains? hdr "struct AslPoint_s {") "hdr struct") (assert (stringContains? hdr "int64_t add(int64_t a, int64_t b);") "hdr add proto") true)

fn testSourceFileProjection -> Bool
  (let [(modNode (sampleModuleNode)) (src (ce/emitCSourceFile modNode))] (assert (stringContains? src "int64_t add(int64_t a, int64_t b) {") "src add def") true)

fn testStandaloneProjection -> Bool
  (let [(modNode (sampleModuleNode)) (cHosted (ce/emitCStandalone modNode.defs "main" false)) (cFree (ce/emitCStandalone modNode.defs "main" true))] (assert (stringContains? cHosted "int main(int argc, char** argv)") "hosted main") (assert (not (stringContains? cFree "<stdio.h>")) "freestanding no stdio") true)

fn testDualPolarityRefutations -> Bool
  (let [(modNode (sampleModuleNode)) (hdr (ce/emitCHeaderFile modNode)) (cFree (ce/emitCStandalone modNode.defs "main" true))] (refute (stringContains? hdr "return ") "header file must not contain return statements") (refute (stringContains? cFree "<stdio.h>") "freestanding mode must not include stdio.h") (refute (stringContains? cFree "malloc") "freestanding mode must not call malloc") (refute (stringContains? cFree "free(") "freestanding mode must not call free") true)

fn testC99LocalizedSampleFixture! -> Bool
  (let [(readRes (fileRead "asl/packages/asl-codegen/tests/fixtures/c99/sampleC99.asl"))] (assert (ok? readRes) "sampleC99 fixture must be readable") (refute (err? readRes) "sampleC99 fixture refutes read error under D77") (mt readRes ((err _) false) ((ok src) (let [(parseRes (a/parse src))] (assert (ok? parseRes) "sampleC99 source parses successfully") (refute (err? parseRes) "sampleC99 source refutes parse error under D77") (mt parseRes ((err _) false) ((ok forms) (mt (listHead forms) ((none) false) ((some firstForm) (mt firstForm ((a/topModule modNode) (let [(hdr (ce/emitCHeaderFile modNode)) (srcCode (ce/emitCSourceFile modNode)) (cStandalone (ce/emitCStandalone modNode.defs "main" false))] (assert (stringContains? hdr "#ifndef ASL_CODEGEN_TESTS_FIXTURES_C99_SAMPLEC99_H") "Header guard matches fixture path") (assert (stringContains? hdr "int64_t add(int64_t a, int64_t b);") "Header prototype for add") (assert (stringContains? hdr "int64_t multiply(int64_t x, int64_t y);") "Header prototype for multiply") (assert (stringContains? hdr "int64_t sampleOp(int64_t p, int64_t q, int64_t r);") "Header prototype for sampleOp") (assert (stringContains? srcCode "int64_t add(int64_t a, int64_t b) {") "Source def for add") (assert (stringContains? srcCode "int64_t multiply(int64_t x, int64_t y) {") "Source def for multiply") (assert (stringContains? srcCode "int64_t sampleOp(int64_t p, int64_t q, int64_t r) {") "Source def for sampleOp") (assert (stringContains? cStandalone "int main(int argc, char** argv)") "Standalone main entry") (refute (stringContains? hdr "package ") "Header refutes Go package under D77") (refute (stringContains? hdr "def add(") "Header refutes Python def add under D77") (refute (stringContains? hdr "(module") "Header refutes WAT '(module' under D77") (refute (stringContains? srcCode "tests/fixtures/wat") "Source refutes dependency on global shared fixtures under D77") true)) (else false))))))))))

fn ! runTests -> Bool
  (do (assert (testHeaderGuards) "testHeaderGuards") (assert (testStandardIncludes) "testStandardIncludes") (assert (testExternCWrapper) "testExternCWrapper") (assert (testFunctionPrototype) "testFunctionPrototype") (assert (testFunctionDef) "testFunctionDef") (assert (testMainEntry) "testMainEntry") (assert (testHeaderFileProjection) "testHeaderFileProjection") (assert (testSourceFileProjection) "testSourceFileProjection") (assert (testStandaloneProjection) "testStandaloneProjection") (assert (testDualPolarityRefutations) "testDualPolarityRefutations") (assert (testC99LocalizedSampleFixture!) "testC99LocalizedSampleFixture") true)
