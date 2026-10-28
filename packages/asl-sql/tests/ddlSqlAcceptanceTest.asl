(module asl-sql/tests/ddlSqlAcceptanceTest :x [testDdlDynamicExecution! testSqlDynamicExecution! runTests] :i [(asl-tools/fleet/run :a run)])

fn testDdlDynamicExecution! -> Bool
  (let [(res (run/runOneLimited (run/job (list "bin/asl" "test" "asl/packages/asl-sql/tests/ddlTest.asl") "." (run/childEnv (list))) (run/limits 180 8))) (code res.exit) (stdout res.out)] (assert (= code 0) (str "asl-sql ddl_test must exit 0, stderr: " "")) (refute (!= code 0) "asl-sql ddl_test must not fail") (assert (stringContains? stdout "assertion(s) executed") "ddl_test must report executed assertions") (assert (stringContains? stdout "refutation(s) executed") "ddl_test must report executed refutations") (refute (stringContains? stdout "ASL_ASSERTION_FAILURE") "ddl_test must not encounter assertion failures") true)

fn testSqlDynamicExecution! -> Bool
  (let [(res (run/runOneLimited (run/job (list "bin/asl" "test" "asl/packages/asl-sql/tests/sqlTest.asl") "." (run/childEnv (list))) (run/limits 180 8))) (code res.exit) (stdout res.out)] (assert (= code 0) (str "asl-sql sql_test must exit 0, stderr: " "")) (refute (!= code 0) "asl-sql sql_test must not fail") (assert (stringContains? stdout "assertion(s) executed") "sql_test must report executed assertions") (assert (stringContains? stdout "refutation(s) executed") "sql_test must report executed refutations") (refute (stringContains? stdout "ASL_ASSERTION_FAILURE") "sql_test must not encounter assertion failures") true)

fn ! runTests -> Bool
  (do (assert (testDdlDynamicExecution!) "testDdlDynamicExecution must pass") (assert (testSqlDynamicExecution!) "testSqlDynamicExecution must pass") true)
