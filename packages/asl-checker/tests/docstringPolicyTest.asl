(module asl-checker/tests/docstringPolicyTest :x [testMAslWithoutDocstringPasses testMAslPassesCleanly testArbitraryPathWithoutDocstringPasses testUnexportedFunctionWithoutDocstringPasses testCheckerTestDocstringsMaintained! testRunnerExecution! runTests] :i [(asl-checker/check :a c) (asl-checker/types :a ty) (asl-tools/fleet/run :a run)])

fn testMAslWithoutDocstringPasses -> Bool
  (let [(diags (c/checkSource "(module m :x [f]) (df f [] -> Int64 42)" (mapEmpty) "m.asl"))] (assert (listEmpty? diags) "m.asl without a source doc produces no diagnostics: docs live in doc.asn (D158)") (refute (listAny? (fn [(d ty/Diagnostic)] -> Bool (= d.code "rule-8")) diags) "no rule-8 diagnostic") true)

fn testMAslPassesCleanly -> Bool
  (let [(diags (c/checkSource "(module m :x [f]) (df f [] -> Int64 42)" (mapEmpty) "m.asl"))] (assert (listEmpty? diags) "m.asl produces zero diagnostics") (refute (not (listEmpty? diags)) "m.asl must not produce diagnostics") true)

fn testArbitraryPathWithoutDocstringPasses -> Bool
  (let [(diags (c/checkSource "(module arbitrary :x [g]) (df g [] -> Int64 99)" (mapEmpty) "arbitrary.asl"))] (assert (listEmpty? diags) "arbitrary.asl without a source doc produces no diagnostics") (refute (listAny? (fn [(d ty/Diagnostic)] -> Bool (= d.code "rule-8")) diags) "no rule-8 diagnostic for arbitrary.asl") true)

fn testUnexportedFunctionWithoutDocstringPasses -> Bool
  (let [(diags (c/checkSource "(module m :x []) (df internal [] -> Int64 123)" (mapEmpty) "m.asl"))] (assert (listEmpty? diags) "Unexported function does not require :d") (refute (not (listEmpty? diags)) "Unexported function must not produce diagnostics") true)

fn testCheckerTestDocstringsMaintained! -> Bool
  (let [(res (run/runOneLimited (run/job (list "bin/asl" "test" "asl/packages/asl-checker/tests/checkerTest.asl") "." (run/childEnv (list))) (run/limits 180 8))) (code res.exit) (out res.out)] (assert (= code 0) "checkerTest suite must exit 0") (refute (!= code 0) "checkerTest suite must not fail") (assert (stringContains? out "assertion(s) executed") "checkerTest must execute assertions") (refute (stringContains? out " 0 assertion(s) executed") "checkerTest assertions must be non-zero") true)

fn testRunnerExecution! -> Bool
  (let [(res (run/runOneLimited (run/job (list "bin/asl" "test" "asl/packages/asl-checker/tests/docstringPolicyRunnerTest.asl") "." (run/childEnv (list))) (run/limits 180 8))) (code res.exit) (out res.out)] (assert (= code 0) "Task50402_runner must exit 0") (refute (!= code 0) "Task50402_runner must not fail") (assert (stringContains? out "assertion(s) executed") "Task50402_runner must execute assertions") (refute (stringContains? out " 0 assertion(s) executed") "Task50402_runner assertions must be non-zero") true)

fn ! runTests -> Bool
  (do (assert (testMAslWithoutDocstringPasses) "testMAslWithoutDocstringPasses must pass") (assert (testMAslPassesCleanly) "testMAslPassesCleanly must pass") (assert (testArbitraryPathWithoutDocstringPasses) "testArbitraryPathWithoutDocstringPasses must pass") (assert (testUnexportedFunctionWithoutDocstringPasses) "testUnexportedFunctionWithoutDocstringPasses must pass") (assert (testCheckerTestDocstringsMaintained!) "testCheckerTestDocstringsMaintained must pass") (assert (testRunnerExecution!) "testRunnerExecution must pass") true)
