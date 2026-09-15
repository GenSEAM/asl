(module asl-codegen/c99IntegrationTest
  :d "Dynamic end-to-end integration and native compilation verification for ISO C99 code generator."
  :x [testEndToEndHostedC99
      testEndToEndFreestandingC99
      testClangCompilationAndExecution
      testC99IntegrationRefutations
      runTests]
  :i [(c99Emit :a ce)
      (ast :a a)
      (reader :a rd)])

(df sampleForms [] -> (List a/TopForm)
  :d "Assembles representative ASL top-level forms with schemas, enums, functions, and entrypoint."
  (let [(pSchema (a/SchemaNode :name "Point" :typeVars (list)
                               :fields (list (a/AstField :name "x" :type "Int64" :docstring "" :default (none) :json (none))
                                             (a/AstField :name "y" :type "Int64" :docstring "" :default (none) :json (none)))
                               :jsonCase (none)))
        (cCircle (a/EnumCase :name "Circle" :fields (list (a/Param :name "radius" :type "Int64")) :docstring ""))
        (cRect (a/EnumCase :name "Rectangle" :fields (list (a/Param :name "width" :type "Int64") (a/Param :name "height" :type "Int64")) :docstring ""))
        (eShape (a/EnumNode :name "Shape" :typeVars (list) :cases (list cCircle cRect)))
        (fnAdd (a/DefunNode :name "add-numbers" :typeVars (list) :isExported true :effect false
                            :params (list (a/Param :name "a" :type "Int64") (a/Param :name "b" :type "Int64"))
                            :retType "Int64" :docstring ""
                            :body (list (rd/sexprList (list (rd/sexprAtom "+") (rd/sexprAtom "a") (rd/sexprAtom "b"))))))
        (fnMain (a/DefunNode :name "main-entry" :typeVars (list) :isExported true :effect false
                             :params (list) :retType "Int64" :docstring ""
                             :body (list (rd/sexprList (list (rd/sexprAtom "add-numbers") (rd/sexprAtom "20") (rd/sexprAtom "22"))))))]
    (list (a/topSchema pSchema) (a/topEnum eShape) (a/topDefun fnAdd) (a/topDefun fnMain))))

(df testEndToEndHostedC99 [] -> Bool
  :d "Verifies hosted C99 code generation containing standard includes, typedefs, and main entrypoint."
  (let [(forms (sampleForms))
        (cCode (ce/emitCStandalone forms "main-entry" false))]
    (assert (string-contains? cCode "#include <stdint.h>") "hosted C99 includes stdint.h")
    (assert (string-contains? cCode "#include <stdio.h>") "hosted C99 includes stdio.h")
    (assert (string-contains? cCode "typedef struct AslPoint_s") "hosted C99 contains Point typedef")
    (assert (string-contains? cCode "typedef struct AslShape_s") "hosted C99 contains Shape typedef")
    (assert (string-contains? cCode "int64_t add_numbers(int64_t a, int64_t b);") "hosted C99 prototype add_numbers")
    (assert (string-contains? cCode "int64_t main_entry(void);") "hosted C99 prototype main_entry")
    (assert (string-contains? cCode "int main(int argc, char** argv)") "hosted C99 contains main entrypoint")
    (assert (string-contains? cCode "return (int)main_entry();") "main calls entrypoint")
    (refute (string-contains? cCode "#include <Arduino.h>") "hosted C99 does not include Arduino.h")
    (refute (string-contains? cCode "void setup(void)") "hosted C99 does not emit Arduino setup")
    (refute (string-contains? cCode "malloc") "hosted C99 does not use dynamic malloc")
    (refute (string-contains? cCode "add-numbers") "hosted C99 mangles kebab-case identifiers")
    true))

(df testEndToEndFreestandingC99 [] -> Bool
  :d "Verifies freestanding C99 preset with zero libc dependencies and setup/loop handlers."
  (let [(forms (sampleForms))
        (cCode (ce/emitCStandalone forms "main-entry" true))]
    (assert (string-contains? cCode "#include <stdint.h>") "freestanding C99 includes stdint.h")
    (assert (string-contains? cCode "void setup(void)") "freestanding C99 emits setup handler")
    (assert (string-contains? cCode "void loop(void)") "freestanding C99 emits loop handler")
    (refute (string-contains? cCode "#include <stdio.h>") "freestanding C99 omits stdio.h")
    (refute (string-contains? cCode "#include <stdlib.h>") "freestanding C99 omits stdlib.h")
    (refute (string-contains? cCode "int main(int argc") "freestanding C99 omits hosted main")
    (refute (string-contains? cCode "malloc") "freestanding C99 has zero malloc calls")
    true))

(df testClangCompilationAndExecution [] -> Bool
  :d "Dynamically compiles emitted C99 source under strict clang flags and runs the resulting binary."
  (let [(forms (sampleForms))
        (cCode (ce/emitCStandalone forms "main-entry" false))
        (srcPath "tmp/c99_integ_test.c")
        (binPath "tmp/c99_integ_test")
        (wRes (file-write srcPath cCode))
        (compCmd (str "clang -std=c99 -Wall -Wextra -Werror -Wno-unused-function -pedantic -O2 " srcPath " -o " binPath))
        (compRes (sysExec compCmd))
        (compCode (.-exitCode compRes))
        (compErr (.-stderr compRes))]
    (assert (= compCode 0) (str "Clang strict compilation must exit 0: " compErr))
    (refute (!= compCode 0) "Clang compilation must not fail")
    (refute (!= compCode 0) "Clang compilation must not fail")
    (let [(execRes (sysExec binPath))
          (execCode (.-exitCode execRes))
          (cleanRes (sysExec (str "rm -f " srcPath " " binPath)))]
      (assert (= execCode 42) (str "Compiled binary must exit with computed result 42, got: " (string-from-int64 execCode)))
      (refute (!= execCode 42) "Compiled binary exit code must not deviate from 42")
      true)))

(df testC99IntegrationRefutations [] -> Bool
  :d "Verifies dual-polarity refutations under D77 for keyword protection and standard conformance."
  (let [(fnConst (a/DefunNode :name "get-value" :typeVars (list) :isExported true :effect false
                              :params (list (a/Param :name "const" :type "Int64") (a/Param :name "volatile" :type "Int64"))
                              :retType "Int64" :docstring ""
                              :body (list (rd/sexprList (list (rd/sexprAtom "+") (rd/sexprAtom "const") (rd/sexprAtom "volatile"))))))
        (forms (list (a/topDefun fnConst)))
        (cCode (ce/emitCStandalone forms "get-value" false))]
    (assert (string-contains? cCode "asl_const") "C99 keyword const mangled to asl_const")
    (assert (string-contains? cCode "asl_volatile") "C99 keyword volatile mangled to asl_volatile")
    (refute (string-contains? cCode "int64_t const,") "C99 keyword const must not appear unescaped")
    (refute (string-contains? cCode "int64_t volatile)") "C99 keyword volatile must not appear unescaped")
    true))

(df runTests [] -> Bool
  :d "Executes all C99 integration tests."
  (do
    (assert (testEndToEndHostedC99) "testEndToEndHostedC99 must pass")
    (assert (testEndToEndFreestandingC99) "testEndToEndFreestandingC99 must pass")
    (assert (testClangCompilationAndExecution) "testClangCompilationAndExecution must pass")
    (assert (testC99IntegrationRefutations) "testC99IntegrationRefutations must pass")
    true))
