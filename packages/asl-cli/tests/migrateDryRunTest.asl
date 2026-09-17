(module asl-cli/tests/migrateDryRunTest
  :d "Dual-polarity unit test suite for Task 54502: Full Monorepo Dry-Run Batch Audit and AST Equivalence Scanner."
  :x [runTests
      RunTests
      testBatchAuditSummarySchema
      testDryRunReportSchema
      testValidateDryRunBatchSingle
      testValidateDryRunBatchErrorHandling
      testDiscoverTargetSourceFiles
      testZeroDiskDriftDuringBatchValidation
      testAuditMonorepoEquivalenceSubset]
  :i [(migrate :a mig)
      (reader :a rd)])

(df testBatchAuditSummarySchema [] -> Bool
  :d "Asserts BatchAuditSummary schema fields, invariants, and initial values."
  (let [(summary (mig/BatchAuditSummary :scannedCount 10 :passedCount 10 :failedCount 0 :errors (list)))]
    (assert (= (.-scannedCount summary) 10) "scannedCount matches initialized value")
    (assert (= (.-passedCount summary) 10) "passedCount matches initialized value")
    (assert (= (.-failedCount summary) 0) "failedCount matches zero failure baseline")
    (assert (list-empty? (.-errors summary)) "errors list is empty on zero failure")
    (refute (!= (.-scannedCount summary) 10) "refutes mismatched scannedCount")
    (refute (!= (.-passedCount summary) 10) "refutes mismatched passedCount")
    (refute (!= (.-failedCount summary) 0) "refutes non-zero failedCount")
    (refute (not (list-empty? (.-errors summary))) "refutes non-empty error list")
    true))

(df testDryRunReportSchema [] -> Bool
  :d "Asserts DryRunReport schema fields, invariants, and initial values."
  (let [(report (mig/DryRunReport :scannedCount 5 :passedCount 5 :failedCount 0 :errors (list)))]
    (assert (= (.-scannedCount report) 5) "report scannedCount matches initialized value")
    (assert (= (.-passedCount report) 5) "report passedCount matches initialized value")
    (assert (= (.-failedCount report) 0) "report failedCount matches zero failure baseline")
    (assert (list-empty? (.-errors report)) "report errors list is empty on zero failure")
    (refute (!= (.-scannedCount report) 5) "refutes report mismatched scannedCount")
    (refute (!= (.-passedCount report) 5) "refutes report mismatched passedCount")
    (refute (!= (.-failedCount report) 0) "refutes report non-zero failedCount")
    (refute (not (list-empty? (.-errors report))) "refutes report non-empty error list")
    true))

(df ! testValidateDryRunBatchSingle [] -> Bool
  :d "Asserts streaming in-memory batch dry-run validation of a single known valid module."
  (let [(summary (mig/validateDryRunBatch (list "asl/packages/asl-text/src/string.asl")))]
    (assert (= (.-scannedCount summary) 1) "single file scan records 1 scanned module")
    (assert (= (.-passedCount summary) 1) "string.asl validates cleanly in memory")
    (assert (= (.-failedCount summary) 0) "string.asl records 0 failures")
    (assert (list-empty? (.-errors summary)) "errors list remains empty on valid module")
    (refute (!= (.-scannedCount summary) 1) "refutes incorrect scannedCount")
    (refute (= (.-passedCount summary) 0) "refutes zero passed files on valid module")
    (refute (> (.-failedCount summary) 0) "refutes failures on valid module")
    (refute (not (list-empty? (.-errors summary))) "refutes unexpected errors on valid module")
    true))

(df ! testValidateDryRunBatchErrorHandling [] -> Bool
  :d "Asserts graceful failure recording when validating a nonexistent module."
  (let [(summary (mig/validateDryRunBatch (list "nonexistent_source_xyz.asl")))]
    (assert (= (.-scannedCount summary) 1) "nonexistent file is counted in scannedCount")
    (assert (= (.-passedCount summary) 0) "nonexistent file yields 0 passed files")
    (assert (= (.-failedCount summary) 1) "nonexistent file records 1 failed file")
    (assert (not (list-empty? (.-errors summary))) "errors list records failure diagnostic")
    (refute (!= (.-scannedCount summary) 1) "refutes inaccurate scannedCount on missing file")
    (refute (> (.-passedCount summary) 0) "refutes positive passedCount on missing file")
    (refute (= (.-failedCount summary) 0) "refutes zero failedCount on missing file")
    (refute (list-empty? (.-errors summary)) "refutes empty errors list on missing file")
    true))

(df ! testDiscoverTargetSourceFiles [] -> Bool
  :d "Asserts target source file discovery across package directories."
  (let [(files (mig/discoverTargetSourceFiles (list "asl/packages/asl-text")))]
    (assert (> (list-length files) 0) "discovered source files list is non-empty")
    (assert (list-contains? files "asl/packages/asl-text/src/string.asl") "discovery finds asl-text/src/string.asl")
    (refute (list-empty? files) "refutes empty discovery list on valid root")
    (refute (not (list-contains? files "asl/packages/asl-text/src/string.asl")) "refutes missing known module in discovery")
    true))

(df ! testZeroDiskDriftDuringBatchValidation [] -> Bool
  :d "Asserts that batch dry-run validation never mutates target files on disk."
  (let [(targetPath "asl/packages/asl-text/src/string.asl")
        (beforeRes (file-read targetPath))
        (summary (mig/validateDryRunBatch (list targetPath)))
        (afterRes (file-read targetPath))]
    (assert (is-ok? beforeRes) "source file exists and is readable prior to dry-run")
    (assert (is-ok? afterRes) "source file remains readable after dry-run")
    (assert (= (unwrap beforeRes) (unwrap afterRes)) "source file byte contents are 100% identical")
    (assert (= (.-passedCount summary) 1) "dry-run validation confirmed successful")
    (refute (is-err? beforeRes) "refutes pre-validation read error")
    (refute (is-err? afterRes) "refutes post-validation read error")
    (refute (!= (unwrap beforeRes) (unwrap afterRes)) "refutes byte drift during dry-run validation")
    (refute (is-err? afterRes) "afterRes is readable")
    true))

(df ! testAuditMonorepoEquivalenceSubset [] -> Bool
  :d "Asserts auditMonorepoEquivalence discovery and batch execution on package subset."
  (let [(summary (mig/auditMonorepoEquivalence (list "asl/packages/asl-text/src/string.asl")))]
    (assert (> (.-scannedCount summary) 0) "audit scanned at least one module")
    (assert (> (.-passedCount summary) 0) "audit passed at least one module")
    (assert (= (.-failedCount summary) 0) "audit on string.asl has 0 failures")
    (refute (= (.-scannedCount summary) 0) "refutes zero scanned modules in audit")
    (refute (= (.-passedCount summary) 0) "refutes zero passed modules in audit")
    true))

(df ! runTests [] -> Bool
  (do
    (println "PASS: migrateDryRunTest suite start")
    (testBatchAuditSummarySchema)
    (testDryRunReportSchema)
    (testValidateDryRunBatchSingle)
    (testValidateDryRunBatchErrorHandling)
    (testDiscoverTargetSourceFiles)
    (testZeroDiskDriftDuringBatchValidation)
    (testAuditMonorepoEquivalenceSubset)
    (println "PASS: migrateDryRunTest suite completed cleanly")
    true))

(df ! RunTests [] -> Bool
  (runTests))
