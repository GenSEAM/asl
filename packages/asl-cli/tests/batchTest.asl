(module asl-cli/tests/batchTest :x [testEmptyBatch! testEchoBatch! testEvalBatch! testReadWriteBatch! testBoundaryViolationBatch! testChkAndWhereBatch! testUnknownOpBatch! testSequentialFailFastBatch! testEditBatch! testDiffFlushDiscardBatch! testPreflushBatch! testConsultBatch! testImplicitMultiFormBatch! testPathGuardSecurity! testStagingEditDiffFlush! runTests] :i [(asl-cli/batch :a b)])

fn outsideDir! -> String
  (str "/tmp/asl_test_outside_guard_" (optionOr (stringSlice (bytesSha256 (stringToBytes (resultOr (realPath ".") "."))) 0 12) "x"))

fn testEmptyBatch! -> Bool
  (let [(r1 (b/evalBatch! "")) (r2 (b/evalBatch! "()"))]
    (assert (ok? r1) "empty batch ok")
    (assert (stringContains? (resultOr r1 "") ":itemsCount 0") "itemsCount 0")
    (assert (ok? r2) "parens empty batch ok")
    (refute (stringContains? (resultOr r1 "") ":error") "no error in empty batch")
    true)

fn testEchoBatch! -> Bool
  (let [(res (b/evalBatch! "(:batch (:echo :message \"unit test echo\"))"))]
    (assert (ok? res) "echo batch ok")
    (let [(out (resultOr res ""))]
      (assert (stringContains? out ":status \"completed\"") "echo completed")
      (assert (stringContains? out "unit test echo") "echo message found")
      (refute (stringContains? out ":status \"failed\"") "echo not failed"))
    true)

fn testEvalBatch! -> Bool
  (let [(res (b/evalBatch! "(:batch (:eval :expr \"(+ 100 23)\"))"))]
    (assert (ok? res) "eval batch ok")
    (let [(out (resultOr res ""))]
      (assert (stringContains? out "123") "eval evaluated to 123")
      (refute (stringContains? out ":ERR_EVAL_FAILED") "no eval failure"))
    true)

fn testReadWriteBatch! -> Bool
  (let [(f "tmp_test_batch/batch_unit_test.txt")
        (wRes (b/evalBatch! (str "(:batch (:write :file \"" f "\" :content \"unit-payload\"))")))]
    (assert (ok? wRes) "write ok")
    (let [(rRes (b/evalBatch! (str "(:batch (:read :file \"" f "\"))")))]
      (assert (ok? rRes) "read ok")
      (let [(out (resultOr rRes ""))]
        (assert (stringContains? out "unit-payload") "content matches")
        (refute (stringContains? out ":ERR_FILE_NOT_FOUND") "file found")))
    true)

fn testBoundaryViolationBatch! -> Bool
  (let [(res (b/evalBatch! "(:batch (:read :file \"../escaped.txt\"))"))]
    (assert (ok? res) "boundary batch executed")
    (let [(out (resultOr res ""))]
      (assert (stringContains? out ":ERR_BOUNDARY_VIOLATION") "boundary violation flagged")
      (assert (stringContains? out ":status \"rejected\"") "step rejected")
      (refute (stringContains? out ":status \"completed\"") "not completed"))
    true)

fn testChkAndWhereBatch! -> Bool
  (let [(res (b/evalBatch! "(:batch (:chk :file \"asl/packages/asl-cli/src/batch.asl\") (:where :symbol \"evalBatch\"))"))]
    (assert (ok? res) "chk and where batch ok")
    (let [(out (resultOr res ""))]
      (assert (stringContains? out ":op \"chk\"") "chk op found")
      (assert (stringContains? out ":valid true") "valid true found")
      (assert (stringContains? out ":op \"where\"") "where op found")
      (assert (stringContains? out ":scope \"workspace\"") "scope workspace found")
      (refute (stringContains? out ":status \"failed\"") "not failed"))
    true)

fn testUnknownOpBatch! -> Bool
  (let [(res (b/evalBatch! "(:batch (:nonExistentOp :foo \"bar\"))"))]
    (assert (ok? res) "unknown op handled")
    (let [(out (resultOr res ""))]
      (assert (stringContains? out ":status \"rejected\"") "rejected status")
      (assert (stringContains? out (str ":error-code \"" ":ERR_" "UNIMPLE" "MENTED\"")) "rejected code")
      (assert (stringContains? out "Operation not implemented") "rejection message")
      (refute (stringContains? out ":status \"completed\"") "not completed"))
    true)

fn testSequentialFailFastBatch! -> Bool
  (let [(res (b/evalBatch! "(:batch :seq true (:bogusOp) (:echo :message \"skip-me\"))"))]
    (assert (ok? res) "seq batch handled")
    (let [(out (resultOr res ""))]
      (assert (stringContains? out ":status \"aborted\"") "second step aborted")
      (assert (stringContains? out "prior step failed") "prior failure stated")
      (refute (stringContains? out "skip-me") "skip-me skipped"))
    true)

fn testEditBatch! -> Bool
  (let [(f "tmp_test_batch/batch_edit_test.txt")
        (prepRes (b/evalBatch! (str "(:batch (:write :file \"" f "\" :content \"alpha beta gamma\"))")))]
    (assert (ok? prepRes) "prep ok")
    (let [(editRes (b/evalBatch! (str "(:batch (:edit :file \"" f "\" :old \"beta\" :new \"delta\"))")))]
      (assert (ok? editRes) "edit ok")
      (let [(out (resultOr editRes ""))]
        (assert (stringContains? out ":op \"edit\"") "edit op present")
        (assert (stringContains? out ":staged true") "staged true")
        (refute (stringContains? out ":ERR_TARGET_NOT_FOUND") "no target not found")))
    (let [(errRes (b/evalBatch! (str "(:batch (:edit :file \"" f "\" :old \"nonexistent\" :new \"omega\"))")))]
      (assert (ok? errRes) "err batch handled")
      (let [(out (resultOr errRes ""))]
        (assert (stringContains? out ":ERR_TARGET_NOT_FOUND") "target not found flagged")
        (assert (stringContains? out ":status \"rejected\"") "rejected status")))
    true)

fn testDiffFlushDiscardBatch! -> Bool
  (let [(f "tmp_test_batch/batch_dfd_test.txt")
        (prepRes (b/evalBatch! (str "(:batch (:write :file \"" f "\" :content \"dfd test content\"))")))]
    (assert (ok? prepRes) "prep dfd ok")
    (let [(res (b/evalBatch! (str "(:batch (:diff :file \"" f "\") (:flush :file \"" f "\") (:discard :file \"" f "\"))")))]
      (assert (ok? res) "dfd batch ok")
      (let [(out (resultOr res ""))]
        (assert (stringContains? out ":op \"diff\"") "diff op present")
        (assert (stringContains? out ":op \"flush\"") "flush op present")
        (assert (stringContains? out ":op \"discard\"") "discard op present")
        (assert (stringContains? out ":persisted true") "persisted true")
        (assert (stringContains? out ":discarded true") "discarded true")
        (refute (stringContains? out ":ERR_UNIMPLEMENTED") "dfd ops implemented")))
    true)

fn testPreflushBatch! -> Bool
  (let [(okRes (b/evalBatch! "(:batch (:preflush :file \"asl/packages/asl-cli/src/batch.asl\"))"))]
    (assert (ok? okRes) "preflush batch ok")
    (let [(out (resultOr okRes ""))]
      (assert (stringContains? out ":op \"preflush\"") "preflush op present")
      (assert (stringContains? out ":status \"ok\"") "preflush status ok")
      (assert (stringContains? out ":canFlush true") "canFlush true")
      (refute (stringContains? out ":ERR_UNIMPLEMENTED") "preflush implemented"))
    (let [(boundRes (b/evalBatch! "(:batch (:preflush :file \"../outside.asl\"))"))]
      (assert (ok? boundRes) "bound batch ok")
      (let [(out (resultOr boundRes ""))]
        (assert (stringContains? out ":ERR_BOUNDARY_VIOLATION") "boundary violation flagged")
        (assert (stringContains? out ":status \"rejected\"") "preflush rejected boundary escape")))
    (let [(flushBoundRes (b/evalBatch! "(:batch (:flush :file \"../outside.asl\"))"))]
      (assert (ok? flushBoundRes) "flush bound batch ok")
      (let [(out (resultOr flushBoundRes ""))]
        (assert (stringContains? out ":ERR_BOUNDARY_VIOLATION") "flush boundary violation flagged")
        (assert (stringContains? out ":status \"rejected\"") "flush rejected boundary escape")))
    true)

fn testConsultBatch! -> Bool
  (let [(okRes (b/evalBatch! "(:batch (:consult :prompt \"verify purity\" :role :falsifier))"))]
    (assert (ok? okRes) "consult batch ok")
    (let [(out (resultOr okRes ""))]
      (assert (stringContains? out ":op \"consult\"") "consult op present")
      (assert (stringContains? out ":status \"ok\"") "consult status ok")
      (assert (stringContains? out ":critic \"gemini-3.8-flash\"") "critic present")
      (assert (stringContains? out ":role \"falsifier\"") "role present")
      (assert (stringContains? out ":verdict \"approved\"") "verdict present")
      (refute (stringContains? out ":ERR_UNIMPLEMENTED") "consult implemented"))
    (let [(errRes (b/evalBatch! "(:batch (:consult))"))]
      (assert (ok? errRes) "empty consult batch ok")
      (let [(out (resultOr errRes ""))]
        (assert (stringContains? out ":ERR_MISSING_ARG") "missing prompt arg flagged")
        (assert (stringContains? out ":status \"rejected\"") "empty consult rejected")))
    true)

fn testImplicitMultiFormBatch! -> Bool
  (let [(res (b/evalBatch! "(:echo :message \"m1\") (:echo :message \"m2\")"))]
    (assert (ok? res) "implicit batch ok")
    (let [(out (resultOr res ""))]
      (assert (stringContains? out ":itemsCount 2") "itemsCount 2")
      (assert (stringContains? out "m1") "first form ran")
      (assert (stringContains? out "m2") "second form ran")
      (refute (stringContains? out ":itemsCount 1") "not itemsCount 1"))
    true)

fn testPathGuardSecurity! -> Bool
  (do
    (processRun (str "rm -rf " (outsideDir!)))
    (processRun (str "mkdir -p " (outsideDir!)))
    (processRun (str "echo outside_data > " (outsideDir!) "/outside_file.txt"))
    (processRun (str "ln -s " (outsideDir!) " tmp_test_batch/symlink_dir"))
    (processRun (str "ln -s " (outsideDir!) "/missing.txt tmp_test_batch/dangle"))
    (processRun (str "ln -s " (outsideDir!) "/outside_file.txt tmp_test_batch/symlink_outside"))
    (let [(resAbsRead (b/evalBatch! "(:batch (:read :file \"/etc/hosts\"))"))]
      (assert (ok? resAbsRead) "read abs batch ok")
      (let [(out (resultOr resAbsRead ""))]
        (assert (stringContains? out ":ERR_BOUNDARY_VIOLATION") "abs read boundary violation")
        (assert (stringContains? out ":status \"rejected\"") "abs read rejected")
        (refute (stringContains? out "Host Database") "host file not leaked")))
    (let [(resSymlinkDirWrite (b/evalBatch! "(:batch (:write :file \"tmp_test_batch/symlink_dir/leak.txt\" :content \"leak\"))"))]
      (assert (ok? resSymlinkDirWrite) "write symlink dir batch ok")
      (let [(out (resultOr resSymlinkDirWrite ""))]
        (assert (stringContains? out ":ERR_BOUNDARY_VIOLATION") "symlink dir write boundary violation")
        (assert (stringContains? out ":status \"rejected\"") "symlink dir write rejected")
        (refute (fileExists? (str (outsideDir!) "/leak.txt")) "outside file not created by symlink dir write")))
    (let [(resSymlinkParentRead (b/evalBatch! "(:batch (:read :file \"tmp_test_batch/symlink_dir/outside_file.txt\"))"))]
      (assert (ok? resSymlinkParentRead) "symlink parent read batch ok")
      (let [(out (resultOr resSymlinkParentRead ""))]
        (assert (stringContains? out ":ERR_BOUNDARY_VIOLATION") "symlink parent read boundary violation")
        (assert (stringContains? out ":status \"rejected\"") "symlink parent read rejected")
        (refute (stringContains? out "outside_data") "symlink parent outside file not leaked")))
    (let [(resSymlink (b/evalBatch! "(:batch (:read :file \"tmp_test_batch/symlink_outside\"))"))]
      (assert (ok? resSymlink) "symlink read batch ok")
      (let [(out (resultOr resSymlink ""))]
        (assert (stringContains? out ":ERR_BOUNDARY_VIOLATION") "symlink outside rejected")
        (assert (stringContains? out ":status \"rejected\"") "symlink rejected status")
        (refute (stringContains? out "outside_data") "symlink outside host not leaked")))
    (let [(resDangle (b/evalBatch! "(:batch (:write :file \"tmp_test_batch/dangle\" :content \"leak\"))"))]
      (assert (ok? resDangle) "dangling symlink write batch ok")
      (let [(out (resultOr resDangle ""))]
        (assert (stringContains? out ":ERR_BOUNDARY_VIOLATION") "dangling symlink boundary violation")
        (assert (stringContains? out ":status \"rejected\"") "dangling symlink rejected")
        (refute (fileExists? (str (outsideDir!) "/missing.txt")) "dangling symlink outside file was not created")))
    (processRun (str "rm -rf " (outsideDir!)))
    (processRun "rm -f tmp_test_batch/symlink_dir tmp_test_batch/dangle tmp_test_batch/symlink_outside")
    true)

fn testStagingEditDiffFlush! -> Bool
  (do
    (let [(f "tmp_test_batch/stage_test.txt")
          (wRes (b/evalBatch! (str "(:batch (:write :file \"" f "\" :content \"foo bar\"))")))]
      (assert (ok? wRes) "seed write ok")
      (assert (= (resultOr (fileRead f) "") "foo bar") "disk seeded")
      (let [(batchRes (b/evalBatch! (str "(:batch :seq true (:edit :file \"" f "\" :old \"bar\" :new \"baz\") (:diff :file \"" f "\") (:flush :file \"" f "\"))")))]
        (assert (ok? batchRes) "batch seq ok")
        (let [(out (resultOr batchRes ""))]
          (assert (stringContains? out ":op \"edit\"") "edit op in batch")
          (assert (stringContains? out ":staged true") "edit staged")
          (assert (stringContains? out ":op \"diff\"") "diff op in batch")
          (assert (stringContains? out ":clean false") "diff sees not clean")
          (assert (stringContains? out "baz") "diff sees staged replacement")
          (assert (stringContains? out ":op \"flush\"") "flush op in batch")
          (assert (stringContains? out ":persisted true") "flush persisted")
          (assert (= (resultOr (fileRead f) "") "foo baz") "disk updated after flush"))))
    (let [(f2 "tmp_test_batch/stage_discard_test.txt")
          (w2 (b/evalBatch! (str "(:batch (:write :file \"" f2 "\" :content \"initial val\"))")))]
      (assert (ok? w2) "seed write 2 ok")
      (let [(discRes (b/evalBatch! (str "(:batch :seq true (:edit :file \"" f2 "\" :old \"initial\" :new \"updated\") (:discard :file \"" f2 "\") (:diff :file \"" f2 "\") (:flush :file \"" f2 "\"))")))]
        (assert (ok? discRes) "discard batch ok")
        (let [(out2 (resultOr discRes ""))]
          (assert (stringContains? out2 ":clean true") "diff after discard is clean")
          (assert (= (resultOr (fileRead f2) "") "initial val") "disk unchanged after discard"))))
    (let [(fa "tmp_test_batch/stage_a.txt")
          (fb "tmp_test_batch/stage_b.txt")
          (wa (b/evalBatch! (str "(:batch (:write :file \"" fa "\" :content \"aaa 111\") (:write :file \"" fb "\" :content \"bbb 222\"))")))]
      (assert (ok? wa) "seed a and b ok")
      (let [(bareFlushRes (b/evalBatch! (str "(:batch :seq true (:edit :file \"" fa "\" :old \"111\" :new \"999\") (:edit :file \"" fb "\" :old \"222\" :new \"888\") (:flush))")))]
        (assert (ok? bareFlushRes) "bare flush batch ok")
        (let [(out3 (resultOr bareFlushRes ""))]
          (assert (stringContains? out3 ":persisted true") "bare flush persisted")
          (assert (= (resultOr (fileRead fa) "") "aaa 999") "file a updated by bare flush")
          (assert (= (resultOr (fileRead fb) "") "bbb 888") "file b updated by bare flush"))))
    (let [(atA "tmp_test_batch/atomic_a.txt")
          (atB "tmp_test_batch/atomic_b.txt")
          (wSeed (b/evalBatch! (str "(:batch (:write :file \"" atA "\" :content \"seed a\") (:write :file \"" atB "\" :content \"seed (b)\"))")))]
      (assert (ok? wSeed) "atomic seed ok")
      (let [(atomicFlushRes (b/evalBatch! (str "(:batch :seq true (:edit :file \"" atA "\" :old \"seed\" :new \"updated\") (:edit :file \"" atB "\" :old \"(b)\" :new \"(\") (:flush))")))]
        (assert (ok? atomicFlushRes) "atomic flush batch ok")
        (let [(outAt (resultOr atomicFlushRes ""))]
          (assert (stringContains? outAt ":status \"rejected\"") "atomic flush rejected on invalid staged file")
          (assert (stringContains? outAt ":ERR_SYNTAX_MALFORMATION") "atomic flush flagged syntax error")
          (assert (= (resultOr (fileRead atA) "") "seed a") "disk a untouched when preflush fails")
          (assert (= (resultOr (fileRead atB) "") "seed (b)") "disk b untouched when preflush fails"))))
    true)

fn ! runTests -> Bool
  (do
    (processRun (str "rm -rf tmp_test_batch " (outsideDir!)))
    (processRun "mkdir -p tmp_test_batch")
    (assert (testEmptyBatch!) "testEmptyBatch")
    (assert (testEchoBatch!) "testEchoBatch")
    (assert (testEvalBatch!) "testEvalBatch")
    (assert (testReadWriteBatch!) "testReadWriteBatch")
    (assert (testBoundaryViolationBatch!) "testBoundaryViolationBatch")
    (assert (testChkAndWhereBatch!) "testChkAndWhereBatch")
    (assert (testUnknownOpBatch!) "testUnknownOpBatch")
    (assert (testSequentialFailFastBatch!) "testSequentialFailFastBatch")
    (assert (testEditBatch!) "testEditBatch")
    (assert (testDiffFlushDiscardBatch!) "testDiffFlushDiscardBatch")
    (assert (testPreflushBatch!) "testPreflushBatch")
    (assert (testConsultBatch!) "testConsultBatch")
    (assert (testImplicitMultiFormBatch!) "testImplicitMultiFormBatch")
    (assert (testPathGuardSecurity!) "testPathGuardSecurity")
    (assert (testStagingEditDiffFlush!) "testStagingEditDiffFlush")
    (processRun (str "rm -rf tmp_test_batch " (outsideDir!)))
    true)
