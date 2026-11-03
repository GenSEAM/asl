(module asl-tools/tests/renderTagTest :x [runTests] :i [(asl-tools/renderTag :a rt)])

fn ! tempRoot -> String
  (str "/tmp/renderTagTest_" (stringFromInt64 (monotonicNs)))

fn ! put! root: String rel: String text: String -> Bool
  (let [(p (str root "/" rel))
        (parts (stringSplit p "/"))
        (_ (dirCreate (stringJoin (listTake parts (- (listLength parts) 1)) "/")))]
    (ok? (fileWrite p text)))

fn verifyText body: String -> String
  (str "(module asl-cli/verify\n  :x [formatDiag]\n  :i [(asl/packages/asl-cli/src/system :a sys) (asl-forms/indent :a ind) (asl-checker/types :a ty)])\n\nfn formatDiag d: ty/Diagnostic -> String\n  " body "\n")

fn ! runTests -> Bool
  (let [(root (tempRoot))
        (_ (put! root "asl/packages/asl-cli/src/verify.asl" (verifyText "(str d.path \": \" d.code)")))
        (_ (put! root "asl/packages/asl-cli/src/system.asl" "(module asl-cli/system)\n"))
        (_ (put! root "asl/packages/asl-forms/src/indent.asl" "(module asl-forms/indent)\n"))
        (_ (put! root "asl/packages/asl-checker/src/types.asl" "(module asl-checker/types)\n"))
        (_ (put! root "asl/packages/asl-cli/src/other.asl" "(module asl-cli/other)\n"))
        (t0 (rt/renderTagIn! root))
        (t0again (rt/renderTagIn! root))
        (_ (put! root "asl/packages/asl-cli/src/other.asl" "(module asl-cli/other)\n; changed\n"))
        (tOther (rt/renderTagIn! root))
        (_ (put! root "asl/packages/asl-cli/src/verify.asl" (verifyText "(str d.path \":\" d.line \": \" d.code)")))
        (tVerify (rt/renderTagIn! root))
        (_ (put! root "asl/packages/asl-forms/src/indent.asl" "(module asl-forms/indent)\n; changed\n"))
        (tImport (rt/renderTagIn! root))
        (files (rt/importFiles (verifyText "x")))
        (_ (pathRemove root))]
    (do
      (refute (fileExists? root) "the scratch tree is removed before any assert can stop the test")
      (assert (= (stringLength t0) 16) (str "the tag is a 16-hex digest: " t0))
      (assert (= t0 t0again) "an unchanged renderer keeps its tag, so cached verdicts still hit")
      (assert (= t0 tOther) "a file the renderer does not import leaves the tag alone")
      (assert (!= tOther tVerify) "an edit of verify.asl changes the tag, so old rendered bodies miss")
      (assert (!= tVerify tImport) "an edit of a file verify imports changes the tag")
      (assert (= files (list "asl/packages/asl-cli/src/system.asl" "asl/packages/asl-forms/src/indent.asl" "asl/packages/asl-checker/src/types.asl")) (str "imports map to files by the package layout: " (stringJoin files " ")))
      true))
