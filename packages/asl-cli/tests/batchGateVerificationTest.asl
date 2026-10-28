(module asl-cli/tests/batchGateVerificationTest :x [testBatchTestSuite! testEchoBatchExecution! testUnknownOpRejectionContract! testSequentialFailFast! testBatchModuleIntegrity! runTests] :i [(asl-cli/batch :a b) (asl-tools/fleet/run :a run)])

fn testBatchTestSuite! -> Bool
  (let [(res (run/runOneLimited (run/job (list "bin/asl" "test" "asl/packages/asl-cli/tests/batchTest.asl") "." (run/childEnv (list))) (run/limits 180 8))) (code res.exit) (out res.out)] (assert (= code 0) "batchTest.asl must pass cleanly") (refute (!= code 0) "batchTest.asl must not fail") (assert (stringContains? out "assertion(s) executed") "batchTest.asl ran assertions") (refute (stringContains? out "0 assertion(s) executed") "batchTest.asl is non-vacuous") true)

fn testEchoBatchExecution! -> Bool
  (let [(res (b/evalBatch! "(:batch (:echo :message \"hello pure asl\"))"))] (assert (ok? res) "rpc echo batch command exits 0") (refute (not (ok? res)) "rpc echo batch must not fail") (let [(out (resultOr res ""))] (assert (stringContains? out ":batch-res") "envelope contains :batch-res") (assert (stringContains? out ":status \"completed\"") "echo batch marked completed") (assert (stringContains? out ":op \"echo\"") "contains echo operation") (assert (stringContains? out "hello pure asl") "echoes payload text") (refute (stringContains? out ":ERR_") "no error code in echo batch") true))

fn testUnknownOpRejectionContract! -> Bool
  (let [(res (b/evalBatch! "(:batch (:unknownSubsystemOp :param 99))"))] (assert (ok? res) "rpc unknown op exits 0 with structured envelope") (refute (not (ok? res)) "rpc unknown op must exit 0") (let [(out (resultOr res ""))] (assert (stringContains? out ":batch-res") "envelope contains :batch-res") (assert (stringContains? out ":status \"rejected\"") "step rejected") (assert (stringContains? out ":error-code \":ERR_UNIMPLEMENTED\"") "error code matches ADR-0081") (assert (stringContains? out "Operation not implemented") "rejection message present") (refute (stringContains? out ":status \"completed\"") "batch must not be completed") true))

fn testSequentialFailFast! -> Bool
  (let [(res (b/evalBatch! "(:batch :seq true (:fakeOp1) (:echo :message \"never-run\"))"))] (assert (ok? res) "sequential batch exits 0 with envelope") (refute (not (ok? res)) "sequential batch must exit 0") (let [(out (resultOr res ""))] (assert (stringContains? out ":batch-res") "envelope contains :batch-res") (assert (stringContains? out ":status \"aborted\"") "subsequent step aborted") (assert (stringContains? out "prior step failed") "prior failure reason present") (assert (stringContains? out ":sequenced true") "sequenced mode verified") (refute (stringContains? out ":op \"echo\" :status \"ok\"") "second step must not execute") true))

fn testBatchModuleIntegrity! -> Bool
  (let [(chkRes (run/runOneLimited (run/job (list "bin/asl" "check" "asl/packages/asl-cli/src/batch.asl") "." (run/childEnv (list))) (run/limits 180 8)))] (assert (= chkRes.exit 0) "batch.asl delimiter balance and syntax valid") (refute (!= chkRes.exit 0) "batch.asl check must exit 0") true)

fn ! runTests -> Bool
  (do (assert (testBatchTestSuite!) "testBatchTestSuite passes") (assert (testEchoBatchExecution!) "testEchoBatchExecution passes") (assert (testUnknownOpRejectionContract!) "testUnknownOpRejectionContract passes") (assert (testSequentialFailFast!) "testSequentialFailFast passes") (assert (testBatchModuleIntegrity!) "testBatchModuleIntegrity passes") true)
