(module asl-cli/tests/migrateBatchTest
  :d "Unit tests for migrateBatch with atomic transactional semantics and D77 refutations under ADR D93."
  :x [runTests
      RunTests
      testBatchDryRunSuccess
      testBatchCheckOnlySuccess
      testBatchAtomicAbortOnSemanticDivergence
      testDualPolarityRefutations]
  :i [(migrate :a mig)
      (reader :a rd)
      (indentParser :a ip)])

(df sampleModuleA [] -> Str
  :d "Returns valid sample module A source."
  (str "(module demo/modA\n"
       "  :d \"Module A service\"\n"
       "  :x [addA]\n"
       "  :i [])\n\n"
       "(df addA [(x Int64) (y Int64)] -> Int64\n"
       "  (+ x y))\n"))

(df sampleModuleB [] -> Str
  :d "Returns valid sample module B source."
  (str "(module demo/modB\n"
       "  :d \"Module B service\"\n"
       "  :x [multB]\n"
       "  :i [])\n\n"
       "(df multB [(x Int64) (y Int64)] -> Int64\n"
       "  (* x y))\n"))

(df sampleModuleC [] -> Str
  :d "Returns valid sample module C source."
  (str "(module demo/modC\n"
       "  :d \"Module C service\"\n"
       "  :x [subC]\n"
       "  :i [])\n\n"
       "(df subC [(x Int64) (y Int64)] -> Int64\n"
       "  (- x y))\n"))

(df corruptModuleSource [] -> Str
  :d "Returns malformed module source with unclosed delimiter for divergence testing."
  (str "(module demo/corrupt\n"
       "  :d \"Corrupted service\"\n"
       "  :x [badFn]\n"
       "  :i [])\n\n"
       "(df badFn [(x Int64] (+ x 1))\n"))

(df ! testBatchDryRunSuccess [] -> Bool
  :d "Asserts that batch dry-run succeeds on valid fixtures without mutating disk."
  (let [(pathA "tmp/migrate_batch_dryrun_a.asl")
        (pathB "tmp/migrate_batch_dryrun_b.asl")
        (srcA (sampleModuleA))
        (srcB (sampleModuleB))]
    (mt (file-write pathA srcA)
      ((err _) (assert false "failed to prepare dryrun fixture A"))
      ((ok _) true))
    (mt (file-write pathB srcB)
      ((err _) (assert false "failed to prepare dryrun fixture B"))
      ((ok _) true))
    (let [(res (mig/migrateBatch (list pathA pathB) true false))]
      (assert (is-ok? res) "migrateBatch dry-run must return ok")
      (refute (is-err? res) "migrateBatch dry-run must refute err")
      (mt res
        ((err emsg)
         (assert false (str "dryrun should succeed, got: " emsg)))
        ((ok outputs)
         (assert (= (list-length outputs) 2) "dryrun outputs length must be 2")
         (refute (!= (list-length outputs) 2) "dryrun outputs length refutes non-2")
         (let [(outA (option-or (list-get outputs 0) ""))
               (outB (option-or (list-get outputs 1) ""))]
           (assert (string-contains? outA "fn addA x: Int64 y: Int64 -> Int64") "outA contains fn signature")
           (assert (string-contains? outA "module demo/modA") "outA contains module header")
           (refute (string-contains? outA "(df addA") "outA refutes legacy df syntax")
           (assert (string-contains? outB "fn multB x: Int64 y: Int64 -> Int64") "outB contains fn signature")
           (assert (string-contains? outB "module demo/modB") "outB contains module header")
           (refute (string-contains? outB "(df multB") "outB refutes legacy df syntax")))))
    (mt (file-read pathA)
      ((err _) (assert false "failed to read dryrun pathA"))
      ((ok diskA)
       (assert (= diskA srcA) "diskA remains strictly identical to original source")
       (refute (!= diskA srcA) "diskA refutes modification")
       (refute (string-contains? diskA "fn addA") "diskA refutes migrated syntax")))
    (mt (file-read pathB)
      ((err _) (assert false "failed to read dryrun pathB"))
      ((ok diskB)
       (assert (= diskB srcB) "diskB remains strictly identical to original source")
       (refute (!= diskB srcB) "diskB refutes modification")
       (refute (string-contains? diskB "fn multB") "diskB refutes migrated syntax")))
    true))

(df ! testBatchCheckOnlySuccess [] -> Bool
  :d "Asserts that batch check-only mode validates all files without modifying disk."
  (let [(pathA "tmp/migrate_batch_check_a.asl")
        (pathB "tmp/migrate_batch_check_b.asl")
        (srcA (sampleModuleA))
        (srcB (sampleModuleB))]
    (mt (file-write pathA srcA)
      ((err _) (assert false "failed to prepare check fixture A"))
      ((ok _) true))
    (mt (file-write pathB srcB)
      ((err _) (assert false "failed to prepare check fixture B"))
      ((ok _) true))
    (let [(res (mig/migrateBatch (list pathA pathB) false true))]
      (assert (is-ok? res) "migrateBatch check-only must return ok")
      (refute (is-err? res) "migrateBatch check-only must refute err")
      (mt res
        ((err emsg)
         (assert false (str "check-only should succeed, got: " emsg)))
        ((ok msgs)
         (assert (= (list-length msgs) 2) "check-only msgs length must be 2")
         (refute (!= (list-length msgs) 2) "check-only msgs length refutes non-2")
         (let [(msgA (option-or (list-get msgs 0) ""))
               (msgB (option-or (list-get msgs 1) ""))]
           (assert (string-contains? msgA "Validated migratable") "msgA reports validated migratable")
           (assert (string-contains? msgA pathA) "msgA contains target path A")
           (assert (string-contains? msgA "✓ ") "msgA contains checkmark")
           (refute (string-contains? msgA "Successfully migrated") "msgA refutes write migration message")
           (assert (string-contains? msgB "Validated migratable") "msgB reports validated migratable")
           (assert (string-contains? msgB pathB) "msgB contains target path B")
           (assert (string-contains? msgB "✓ ") "msgB contains checkmark")
           (refute (string-contains? msgB "Successfully migrated") "msgB refutes write migration message")))))
    (mt (file-read pathA)
      ((err _) (assert false "failed to read check pathA"))
      ((ok diskA)
       (assert (= diskA srcA) "diskA remains strictly untouched in check mode")
       (refute (!= diskA srcA) "diskA refutes changes in check mode")
       (refute (string-contains? diskA "fn addA") "diskA refutes new syntax in check mode")))
    (mt (file-read pathB)
      ((err _) (assert false "failed to read check pathB"))
      ((ok diskB)
       (assert (= diskB srcB) "diskB remains strictly untouched in check mode")
       (refute (!= diskB srcB) "diskB refutes changes in check mode")
       (refute (string-contains? diskB "fn multB") "diskB refutes new syntax in check mode")))
    true))

(df ! testBatchAtomicAbortOnSemanticDivergence [] -> Bool
  :d "Asserts atomic abort with zero side-effects when one file in the batch diverges."
  (let [(pathA "tmp/migrate_batch_abort_a.asl")
        (pathCorrupt "tmp/migrate_batch_abort_corrupt.asl")
        (pathB "tmp/migrate_batch_abort_b.asl")
        (srcA (sampleModuleA))
        (srcCorrupt (corruptModuleSource))
        (srcB (sampleModuleB))]
    (mt (file-write pathA srcA)
      ((err _) (assert false "failed to prepare abort fixture A"))
      ((ok _) true))
    (mt (file-write pathCorrupt srcCorrupt)
      ((err _) (assert false "failed to prepare abort corrupt fixture"))
      ((ok _) true))
    (mt (file-write pathB srcB)
      ((err _) (assert false "failed to prepare abort fixture B"))
      ((ok _) true))
    (let [(res (mig/migrateBatch (list pathA pathCorrupt pathB) false false))]
      (assert (is-err? res) "batch with divergent file must return err")
      (refute (is-ok? res) "batch with divergent file must refute ok")
      (mt res
        ((ok _) (assert false "divergent batch must not return ok"))
        ((err emsg)
         (assert (string-contains? emsg "Migration aborted: semantic divergence detected in ") "error message identifies semantic divergence")
         (assert (string-contains? emsg pathCorrupt) "error message identifies corrupted file path")
         (refute (string-contains? emsg "Successfully migrated") "error message refutes successful migration")
         (refute (string-contains? emsg pathA) "error message does not blame valid file A"))))
    (mt (file-read pathA)
      ((err _) (assert false "failed to read abort pathA"))
      ((ok diskA)
       (assert (= diskA srcA) "diskA strictly intact after atomic abort")
       (refute (!= diskA srcA) "diskA refutes corruption after atomic abort")
       (refute (string-contains? diskA "fn addA") "diskA refutes partial migration write")))
    (mt (file-read pathCorrupt)
      ((err _) (assert false "failed to read abort corrupt path"))
      ((ok diskCorrupt)
       (assert (= diskCorrupt srcCorrupt) "corrupt disk file preserved untouched")
       (refute (!= diskCorrupt srcCorrupt) "corrupt file refutes modification")))
    (mt (file-read pathB)
      ((err _) (assert false "failed to read abort pathB"))
      ((ok diskB)
       (assert (= diskB srcB) "diskB strictly intact after atomic abort")
       (refute (!= diskB srcB) "diskB refutes corruption after atomic abort")
       (refute (string-contains? diskB "fn multB") "diskB refutes partial migration write")))
    true))

(df ! testDualPolarityRefutations [] -> Bool
  :d "Executes comprehensive D77 refutations against partial writes, error handling, and batch writing."
  (let [(pathA "tmp/migrate_batch_refute_a.asl")
        (pathCorrupt "tmp/migrate_batch_refute_corrupt.asl")
        (pathB "tmp/migrate_batch_refute_b.asl")
        (pathEmpty "tmp/migrate_batch_refute_empty.asl")
        (pathNonexistent "tmp/migrate_batch_nonexistent_target_xyz.asl")
        (pathW1 "tmp/migrate_batch_w1.asl")
        (pathW2 "tmp/migrate_batch_w2.asl")
        (pathW3 "tmp/migrate_batch_w3.asl")
        (srcA (sampleModuleA))
        (srcCorrupt (corruptModuleSource))
        (srcB (sampleModuleB))
        (srcC (sampleModuleC))]
    (mt (file-write pathA srcA)
      ((err _) (assert false "failed to write refute A"))
      ((ok _) true))
    (mt (file-write pathCorrupt srcCorrupt)
      ((err _) (assert false "failed to write refute corrupt"))
      ((ok _) true))
    (mt (file-write pathB srcB)
      ((err _) (assert false "failed to write refute B"))
      ((ok _) true))
    (mt (file-write pathEmpty "")
      ((err _) (assert false "failed to write refute empty"))
      ((ok _) true))

    (let [(resDryAbort (mig/migrateBatch (list pathA pathCorrupt pathB) true false))]
      (assert (is-err? resDryAbort) "corrupt file in dry-run batch must trigger error")
      (refute (is-ok? resDryAbort) "corrupt file in dry-run batch refutes ok")
      (mt resDryAbort
        ((ok _) (assert false "dry-run abort must not return ok"))
        ((err eDry)
         (assert (string-contains? eDry pathCorrupt) "dry-run error references corrupt path")
         (refute (string-contains? eDry pathA) "dry-run error refutes blaming path A"))))

    (let [(resCheckAbort (mig/migrateBatch (list pathA pathCorrupt pathB) false true))]
      (assert (is-err? resCheckAbort) "corrupt file in check-only batch must trigger error")
      (refute (is-ok? resCheckAbort) "corrupt file in check-only batch refutes ok")
      (mt resCheckAbort
        ((ok _) (assert false "check-only abort must not return ok"))
        ((err eChk)
         (assert (string-contains? eChk pathCorrupt) "check-only error references corrupt path")
         (refute (string-contains? eChk pathA) "check-only error refutes blaming path A"))))

    (let [(resNonexist (mig/migrateBatch (list pathA pathNonexistent) false false))]
      (assert (is-err? resNonexist) "batch with nonexistent file must fail")
      (refute (is-ok? resNonexist) "batch with nonexistent file refutes ok")
      (mt resNonexist
        ((ok _) (assert false "nonexistent file must not succeed"))
        ((err eNon)
         (assert (string-contains? eNon pathNonexistent) "error references missing file path")
         (assert (string-contains? eNon "semantic divergence detected in") "error message indicates divergence"))))

    (let [(resEmpty (mig/migrateBatch (list pathEmpty) false false))]
      (assert (is-err? resEmpty) "empty file batch must fail")
      (refute (is-ok? resEmpty) "empty file batch refutes ok")
      (mt resEmpty
        ((ok _) (assert false "empty file must not succeed"))
        ((err eEmp)
         (assert (string-contains? eEmp pathEmpty) "empty file error references empty path"))))

    (let [(resEmptyListDry (mig/migrateBatch (list) true false))
          (resEmptyListChk (mig/migrateBatch (list) false true))
          (resEmptyListWr (mig/migrateBatch (list) false false))]
      (assert (is-ok? resEmptyListDry) "empty list dry-run returns ok")
      (assert (is-ok? resEmptyListChk) "empty list check-only returns ok")
      (assert (is-ok? resEmptyListWr) "empty list write returns ok")
      (refute (is-err? resEmptyListDry) "empty list dry-run refutes error")
      (refute (is-err? resEmptyListChk) "empty list check refutes error")
      (refute (is-err? resEmptyListWr) "empty list write refutes error"))

    (mt (file-write pathW1 srcA)
      ((err _) (assert false "failed to write W1"))
      ((ok _) true))
    (mt (file-write pathW2 srcB)
      ((err _) (assert false "failed to write W2"))
      ((ok _) true))
    (mt (file-write pathW3 srcC)
      ((err _) (assert false "failed to write W3"))
      ((ok _) true))

    (let [(resWrite (mig/migrateBatch (list pathW1 pathW2 pathW3) false false))]
      (assert (is-ok? resWrite) "full valid batch write must succeed")
      (refute (is-err? resWrite) "full valid batch write refutes error")
      (mt resWrite
        ((err ew) (assert false (str "batch write should succeed, got: " ew)))
        ((ok wmsgs)
         (assert (= (list-length wmsgs) 3) "batch write returns 3 messages")
         (refute (!= (list-length wmsgs) 3) "batch write message count refutes non-3")
         (let [(m1 (option-or (list-get wmsgs 0) ""))
               (m2 (option-or (list-get wmsgs 1) ""))
               (m3 (option-or (list-get wmsgs 2) ""))]
           (assert (string-contains? m1 "Successfully migrated") "m1 confirms migration")
           (assert (string-contains? m2 "Successfully migrated") "m2 confirms migration")
           (assert (string-contains? m3 "Successfully migrated") "m3 confirms migration")
           (refute (string-contains? m1 "divergence") "m1 refutes divergence")
           (refute (string-contains? m2 "divergence") "m2 refutes divergence")
           (refute (string-contains? m3 "divergence") "m3 refutes divergence")))))

    (mt (file-read pathW1)
      ((err _) (assert false "failed to read W1"))
      ((ok d1)
       (assert (string-contains? d1 "fn addA x: Int64 y: Int64 -> Int64") "W1 has migrated fn")
       (refute (string-contains? d1 "(df addA") "W1 refutes old df syntax")
       (refute (= d1 srcA) "W1 refutes old source content")))

    (mt (file-read pathW2)
      ((err _) (assert false "failed to read W2"))
      ((ok d2)
       (assert (string-contains? d2 "fn multB x: Int64 y: Int64 -> Int64") "W2 has migrated fn")
       (refute (string-contains? d2 "(df multB") "W2 refutes old df syntax")
       (refute (= d2 srcB) "W2 refutes old source content")))

    (mt (file-read pathW3)
      ((err _) (assert false "failed to read W3"))
      ((ok d3)
       (assert (string-contains? d3 "fn subC x: Int64 y: Int64 -> Int64") "W3 has migrated fn")
       (refute (string-contains? d3 "(df subC") "W3 refutes old df syntax")
       (refute (= d3 srcC) "W3 refutes old source content")))
    true))

(df ! runTests [] -> Bool
  :d "Master test runner for migrateBatch unit test suite."
  (and (testBatchDryRunSuccess)
       (and (testBatchCheckOnlySuccess)
            (and (testBatchAtomicAbortOnSemanticDivergence)
                 (testDualPolarityRefutations)))))

(df ! RunTests [] -> Bool
  :d "PascalCase alias for master test runner."
  (runTests))
