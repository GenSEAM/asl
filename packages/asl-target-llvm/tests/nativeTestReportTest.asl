(module asl-target-llvm/tests/nativeTestReportTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt)])

; (:m :ref HL-E-LLVM :do "HL-E-LLVM (asl-host deleted): compareSuite used to run each sample suite on a live asl-host and parse its own 'N assertion(s) executed[, M refutation(s) executed]' verdict line (hostCounts) as the expected count. Every sample path is a fixed, already-committed suite whose own assertion/refutation count only changes if its source changes (the same assumption any golden-value test makes), so the live host run is replaced by a recordedCounts table captured once from the leftover asl-host binary before HL-DELETE removed it. The fourth sample, tests/conformance/loader/workspaceNameImportTest.asl, is dropped: it is not owned by this unit and its OWN test body shells out to the now-deleted 'asl/host/out/asl-host run asl/packages/asl-compiler/src/asl1.asl build/check ...' as part of what it tests, so it fails under both host and native compilation regardless of this file's own port (an asl1.asl-build pattern matching the one this unit already replaced elsewhere via asl-cli/asl1Cache nativeAsl1!, but out of :owns here); swapped for asl-target-llvm/tests/nativeRtGapsTest.asl, this unit's own already-ported, now fully host-free suite, confirmed to report the same (12, 0) count whether loaded by the leftover host or compiled natively")

fn recordedCounts path: String -> (Option (Pair Int64 Int64))
  (cond
    ; (:m :ref NAMESFIX-FIX :do "typesTest.asl gained 2 asserts from this merge (EFFECT-INFER), confirmed by direct ./bin/asl test run: 75 assertion(s), 7 refutation(s)")
    ((= path "asl/packages/asl-checker/tests/typesTest.asl") (some (pair 75 7)))
    ; (:m :ref NAMESFIX-FIX :do "checkerTest.asl gained 1 assert and 1 refute from this merge (EFFECT-INFER), confirmed by direct ./bin/asl test run: 171 assertion(s), 73 refutation(s)")
    ((= path "asl/packages/asl-checker/tests/checkerTest.asl") (some (pair 171 73)))
    ((= path "asl/packages/asl-ir/tests/lowerTest.asl") (some (pair 122 0)))
    ((= path "asl/packages/asl-target-llvm/tests/nativeRtGapsTest.asl") (some (pair 12 0)))
    (else (none)))

fn ! freshCacheDir -> String
  (str ".asl/cache/nativeTestReportTest/" (stringFromInt64 (monotonicNs)))

fn ! compareSuite cacheDir: String path: String -> Bool
  (let [(built (nt/prepareIn cacheDir path "nativeReportTest" "test"))]
    (match built.binary
      ((none) (do (assert (stringEmpty? built.reason) (str path " native build reason: " built.reason)) false))
      ((some bin)
       (let [(env (nt/withEnvOverrides! (list "ASL_ASSERT_REPORT=1" "ASL_PRELUDE=asl/host/out/prelude.asl")))
             (native (nt/runProc (list bin) (some env)))
             (nativeCounts (nt/reportCounts native.stderr))
             (expected (recordedCounts path))]
         (do (assert (= native.exitCode 0) (str path " native exit is " native.exitCode))
             (assert (some? expected) (str path " has a recorded asl-host count"))
             (assert (some? nativeCounts) (str path " native stderr contains an assertion report: " native.stderr))
             (assert (= nativeCounts expected) (str path " native report counts " nativeCounts " equal the recorded asl-host counts " expected))
             true)))))

fn zeroSuiteSource -> String
  "(module nativeTestReport/zeroSuite :x [runTests] :i [])\n\nfn runTests -> Bool\n  true\n"

fn ! testZeroSuite cacheDir: String -> Bool
  (let [(dir ".asl/cache/nativeTestReportTest")
        (path (str dir "/zeroSuite.asl"))
        (made (dirCreate dir))
        (written (fileWrite path (zeroSuiteSource)))
        (built (nt/prepareIn cacheDir path "nativeReportTest-zero" "test"))]
    (do (assert (ok? made) (str "the zero-assertion fixture directory is created: " made))
        (assert (ok? written) (str "the zero-assertion fixture is written: " written))
        (match built.binary
          ((none) (do (assert (stringEmpty? built.reason) (str "the zero-assertion suite builds natively: " built.reason)) false))
          ((some bin)
           (let [(env (nt/withEnvOverrides! (list "ASL_ASSERT_REPORT=1" "ASL_PRELUDE=asl/host/out/prelude.asl")))
                 (native (nt/runProc (list bin) (some env)))
                 (counts (nt/reportCounts native.stderr))
                 (verdict (nt/verdictOf path native.exitCode native.stderr))
                 (cli (nt/runProc (list "./bin/asl" "test" "--native" path) (none)))]
             (do (assert (= verdict.exit 1) (str "the test path rejects zero assertions without runtime opt-in: " verdict.line))
                 (assert (= counts (some (pair 0 0))) (str "the zero-assertion native binary reports zero counts: " native.stderr))
                 (assert (= cli.exitCode 1) (str "asl test --native rejects the zero-assertion fixture: " cli.stdout " " cli.stderr))
                 true))))))

fn orderSuiteSource -> String
  "(module nativeTestReport/orderSuite :x [runTests] :i [])\n\nfn ! runTests -> Bool\n  (do (assert (stringContains? (optionOr (envGet \"ASL_PRELUDE\") \"\") \"prelude.asl\") \"native prelude environment is present\")\n      (println \"stdout-marker\")\n      true)\n"

fn ! testReportOrder cacheDir: String -> Bool
  (let [(dir ".asl/cache/nativeTestReportTest")
        (path (str dir "/orderSuite.asl"))
        (made (dirCreate dir))
        (written (fileWrite path (orderSuiteSource)))
        (built (nt/prepareIn cacheDir path "nativeReportTest-order" "test"))]
    (do (assert (ok? made) (str "the report-order fixture directory is created: " made))
        (assert (ok? written) (str "the report-order fixture is written: " written))
        (match built.binary
          ((none) (do (assert (stringEmpty? built.reason) (str "the report-order suite builds natively: " built.reason)) false))
          ((some bin)
           (let [(env (nt/withEnvOverrides! (list "ASL_ASSERT_REPORT=1" "ASL_ASSERT_FAIL_EMPTY=1" "ASL_PRELUDE=asl/host/out/prelude.asl")))
                 (native (nt/runProc (list "/bin/sh" "-c" (str bin " 2>&1")) (some env)))
                 (output native.stdout)
                 (marker (stringIndexOf output "stdout-marker"))
                 (report (stringIndexOf output " assertion(s) executed") )]
             (do (assert (= native.exitCode 0) (str "the report-order fixture exits 0: " native.stderr))
                 (assert (some? marker) (str "the fixture stdout marker is merged: " output))
                 (assert (some? report) (str "the report is merged with fixture output: " output))
                 (assert (< (optionOr marker 0) (optionOr report 0)) (str "buffered stdout is flushed before the report: " output))
                 true))))))

fn missingReportSuiteSource -> String
  "(module nativeTestReport/missingReport :x [runTests] :i [])\n\nfn ! runTests -> Bool\n  (do (assert (stringContains? (optionOr (envGet \"ASL_PRELUDE\") \"\") \"prelude.asl\") \"native prelude environment is present\")\n      true)\n"

fn ! testMissingReport cacheDir: String -> Bool
  (let [(dir ".asl/cache/nativeTestReportTest")
        (path (str dir "/missingReport.asl"))
        (made (dirCreate dir))
        (written (fileWrite path (missingReportSuiteSource)))
        (built (nt/prepareIn cacheDir path "nativeReportTest-no-report" "test"))]
    (do (assert (ok? made) (str "the no-report fixture directory is created: " made))
        (assert (ok? written) (str "the no-report fixture is written: " written))
        (match built.binary
          ((none) (do (assert (stringEmpty? built.reason) (str "the no-report suite builds natively: " built.reason)) false))
          ((some bin)
           (let [(env (nt/withEnvOverrides! (list "ASL_PRELUDE=asl/host/out/prelude.asl")))
                 (native (nt/runProc (list bin) (some env)))
                 (counts (nt/reportCounts native.stderr))
                 (verdict (nt/verdictOf path native.exitCode native.stderr))]
             (do (assert (= native.exitCode 0) (str "the no-report native fixture itself runs: " native.stderr))
                 (assert (none? counts) (str "the native fixture prints no assertion report: " native.stderr))
                 (assert (= verdict.exit 1) "native test verdict rejects an executable that printed no assertion report")
                 (assert (stringContains? verdict.line "without an assertion report") verdict.line)
                 true))))))

fn ! runTests -> Bool
  (let [(cacheDir (freshCacheDir))]
    (do (assert (testMissingReport cacheDir) "a native test with no assertion report fails")
        (assert (compareSuite cacheDir "asl/packages/asl-checker/tests/typesTest.asl") "typesTest native report matches asl-host")
        (assert (compareSuite cacheDir "asl/packages/asl-checker/tests/checkerTest.asl") "checkerTest native report matches asl-host")
        (assert (compareSuite cacheDir "asl/packages/asl-ir/tests/lowerTest.asl") "lowerTest native report matches asl-host")
        (assert (compareSuite cacheDir "asl/packages/asl-target-llvm/tests/nativeRtGapsTest.asl") "nativeRtGapsTest native report matches the recorded asl-host count")
        (assert (testZeroSuite cacheDir) "a runTests suite with zero assertions fails natively")
        (assert (testReportOrder cacheDir) "buffered suite output is flushed before its report")
        true))
