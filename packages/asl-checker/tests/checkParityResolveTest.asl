(module asl-checker/tests/checkParityResolveTest
  :x [runTests]
  :i [(asl-checker/check :a c)])

fn sourceIsClean! path: String -> Bool
  (mt (c/checkFile! path (list "."))
    ((err _) false)
    ((ok ds) (listEmpty? ds)))

fn ! runTests -> Bool
  (do (assert (sourceIsClean! "asl/packages/asl-checker/tests/checkDepIndexTest.asl") "with record copies do not create unknown-symbol diagnostics")
      (assert (sourceIsClean! "asl/grammar/tests/corpusTest.asl") "variadic host calls do not create checker arity diagnostics")
      (assert (sourceIsClean! "asl/packages/asl-agent/tests/asnBoxartTest.asl") "the corrected BoxNode constructor obeys its schema")
      (assert (sourceIsClean! "asl/packages/asl-gates/tests/runnerMainTest.asl") "public FullGreenRecord type references are exported")
      (assert (sourceIsClean! "asl/packages/asl-forms/src/search.asl") "same-named imported and prelude cases use the scrutinee enum")
      (assert (sourceIsClean! "asl/packages/asl-transpile/src/transpile.asl") "transpiler imports form a DAG and use exported parser types")
      true)
