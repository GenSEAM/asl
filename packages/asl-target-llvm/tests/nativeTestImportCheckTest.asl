(module asl-target-llvm/tests/nativeTestImportCheckTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt)])

; (:m :ref TEST-CHECKS-IMPORTS :do "asl test checks the imported modules like asl check: a lib whose Float64 listSum is a type error must stop the test before compiling, with the lib's file:line:col in the reason, not a runtime ERR_TYPE without location")
fn libSource -> String
  "(module tmp/zzNtImportCheck/lib :x [total] :i [])\n\nfn total xs: (List Float64) -> Float64\n  (listSum xs)\n"

fn useSource -> String
  "(module tmp/zzNtImportCheck/useTest :x [runTests] :i [(tmp/zzNtImportCheck/lib :a l)])\n\nfn ! runTests -> Bool\n  (do (assert (= (l/total (list 1.0 2.0)) 3.0) \"total sums\")\n      true)\n"

fn ! runTests -> Bool
  (let [(dir "tmp/zzNtImportCheck")
        (made (dirCreate dir))
        (lib (fileWrite (str dir "/lib.asl") (libSource)))
        (use (fileWrite (str dir "/useTest.asl") (useSource)))
        (built (nt/prepareIn (str ".asl/cache/nativeTestImportCheckTest/" (stringFromInt64 (monotonicNs))) (str dir "/useTest.asl") (str "importCheck" (stringFromInt64 (monotonicNs))) "test"))]
    (do (assert (ok? made) "the fixture directory is created")
        (assert (ok? lib) "the lib is written")
        (assert (ok? use) "the test is written")
        (assert (= built.cache "checker-reject") (str "the test is rejected by the checker, got " built.cache ": " built.reason))
        (assert (stringContains? built.reason "tmp/zzNtImportCheck/lib.asl:4:3: ERR_TYPE_MISMATCH") (str "the reason names the lib site: " built.reason))
        true))
