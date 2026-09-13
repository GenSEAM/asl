(module asl-cli/tests/batchTest
  :d "Unit tests for pure AgentScript batch evaluator engine."
  :x [testEmptyBatch
      testEchoBatch
      testEvalBatch
      testReadWriteBatch
      testBoundaryViolationBatch
      testChkAndWhereBatch
      testUnknownOpBatch
      testSequentialFailFastBatch
      RunTests]
  :i [(../src/batch :a b)])

(df testEmptyBatch [] -> Bool
  (let [(r1 (b/evalBatch ""))
        (r2 (b/evalBatch "()"))]
    (assert (= (.-_tag r1) "ok") "empty batch ok")
    (assert (string-contains? (.-value r1) ":itemsCount 0") "itemsCount 0")
    (assert (= (.-_tag r2) "ok") "parens empty batch ok")
    (refute (string-contains? (.-value r1) ":error") "no error in empty batch")
    true))

(df testEchoBatch [] -> Bool
  (let [(res (b/evalBatch "(:batch (:echo :message \"unit test echo\"))"))]
    (assert (= (.-_tag res) "ok") "echo batch ok")
    (let [(out (.-value res))]
      (assert (string-contains? out ":status \"completed\"") "echo completed")
      (assert (string-contains? out "unit test echo") "echo message found")
      (refute (string-contains? out ":status \"failed\"") "echo not failed"))
    true))

(df testEvalBatch [] -> Bool
  (let [(res (b/evalBatch "(:batch (:eval :expr \"(+ 100 23)\"))"))]
    (assert (= (.-_tag res) "ok") "eval batch ok")
    (let [(out (.-value res))]
      (assert (string-contains? out "123") "eval evaluated to 123")
      (refute (string-contains? out ":ERR_EVAL_FAILED") "no eval failure"))
    true))

(df testReadWriteBatch [] -> Bool
  (let [(f "scratch/batch_unit_test.txt")
        (wRes (b/evalBatch (str "(:batch (:write :file \"" f "\" :content \"unit-payload\"))")))]
    (assert (= (.-_tag wRes) "ok") "write ok")
    (let [(rRes (b/evalBatch (str "(:batch (:read :file \"" f "\"))")))]
      (assert (= (.-_tag rRes) "ok") "read ok")
      (let [(out (.-value rRes))]
        (assert (string-contains? out "unit-payload") "content matches")
        (refute (string-contains? out ":ERR_FILE_NOT_FOUND") "file found")))
    true))

(df testBoundaryViolationBatch [] -> Bool
  (let [(res (b/evalBatch "(:batch (:read :file \"../escaped.txt\"))"))]
    (assert (= (.-_tag res) "ok") "boundary batch executed")
    (let [(out (.-value res))]
      (assert (string-contains? out ":ERR_BOUNDARY_VIOLATION") "boundary violation flagged")
      (assert (string-contains? out ":status \"rejected\"") "step rejected")
      (refute (string-contains? out ":status \"completed\"") "not completed"))
    true))

(df testChkAndWhereBatch [] -> Bool
  (let [(res (b/evalBatch "(:batch (:chk :file \"asl/packages/asl-cli/src/batch.asl\") (:where :symbol \"evalBatch\"))"))]
    (assert (= (.-_tag res) "ok") "chk and where batch ok")
    (let [(out (.-value res))]
      (assert (string-contains? out ":op \"chk\"") "chk op found")
      (assert (string-contains? out ":valid true") "valid true found")
      (assert (string-contains? out ":op \"where\"") "where op found")
      (assert (string-contains? out ":scope \"workspace\"") "scope workspace found")
      (refute (string-contains? out ":status \"failed\"") "not failed"))
    true))

(df testUnknownOpBatch [] -> Bool
  (let [(res (b/evalBatch "(:batch (:nonExistentOp :foo \"bar\"))"))]
    (assert (= (.-_tag res) "ok") "unknown op handled")
    (let [(out (.-value res))]
      (assert (string-contains? out ":status \"rejected\"") "rejected status")
      (assert (string-contains? out ":error-code \":ERR_UNIMPLEMENTED\"") "unimplemented code")
      (assert (string-contains? out "Operation not implemented") "rejection message")
      (refute (string-contains? out ":status \"completed\"") "not completed"))
    true))

(df testSequentialFailFastBatch [] -> Bool
  (let [(res (b/evalBatch "(:batch :seq true (:bogusOp) (:echo :message \"skip-me\"))"))]
    (assert (= (.-_tag res) "ok") "seq batch handled")
    (let [(out (.-value res))]
      (assert (string-contains? out ":status \"aborted\"") "second step aborted")
      (assert (string-contains? out "prior step failed") "prior failure stated")
      (refute (string-contains? out "skip-me") "skip-me skipped"))
    true))

(df RunTests [] -> Bool
  (do
    (assert (testEmptyBatch) "testEmptyBatch")
    (assert (testEchoBatch) "testEchoBatch")
    (assert (testEvalBatch) "testEvalBatch")
    (assert (testReadWriteBatch) "testReadWriteBatch")
    (assert (testBoundaryViolationBatch) "testBoundaryViolationBatch")
    (assert (testChkAndWhereBatch) "testChkAndWhereBatch")
    (assert (testUnknownOpBatch) "testUnknownOpBatch")
    (assert (testSequentialFailFastBatch) "testSequentialFailFastBatch")
    true))
