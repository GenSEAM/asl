(module asl-target-llvm/tests/nativeTestReportTest
  :x [runTests]
  :i [(tools/nativeTest :a nt)])

fn hostCounts path: String text: String -> (Option (Pair Int64 Int64))
  (let [(line (nt/hostVerdictLine text))
        (body (mt (stringIndexOf line (str path ": "))
               ((some i) (optionOr (stringSlice line (+ i (stringLength path) 2) (stringLength line)) ""))
               ((none) "")))
        (words (stringSplit body " "))]
    (mt (stringToInt64 (optionOr (listHead words) ""))
      ((none) (none))
      ((some assertions)
       (if (stringContains? body " refutation(s) executed")
         (mt (stringToInt64 (optionOr (listGet words 3) ""))
           ((none) (none))
           ((some refutations) (some (pair assertions refutations))))
         (some (pair assertions 0))))))

fn ! freshCacheDir -> String
  (str ".asl/cache/nativeTestReportTest/" (stringFromInt64 (monotonicNs)))

fn ! compareSuite cacheDir: String path: String -> Bool
  (let [(built (nt/prepareIn cacheDir path "nativeReportTest" "test"))]
    (mt built.binary
      ((none) (do (assert (stringEmpty? built.reason) (str path " native build reason: " built.reason)) false))
      ((some bin)
       (let [(env (nt/withEnvOverrides! (list "ASL_ASSERT_REPORT=1" "ASL_PRELUDE=asl/host/out/prelude.asl")))
             (native (nt/runProc (list bin) (some env)))
             (host (nt/runProc (list "asl/host/out/asl-host" "test" path) (none)))
             (nativeCounts (nt/reportCounts native.stderr))
             (expected (hostCounts path host.stdout))]
         (do (assert (= native.exitCode 0) (str path " native exit is " native.exitCode))
             (assert (= host.exitCode 0) (str path " host exit is " host.exitCode))
             (assert (some? nativeCounts) (str path " native stderr contains an assertion report: " native.stderr))
             (assert (= nativeCounts expected) (str path " native report counts " nativeCounts " equal asl-host counts " expected))
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
        (mt built.binary
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
        (mt built.binary
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
        (mt built.binary
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
        (assert (compareSuite cacheDir "tests/conformance/loader/workspaceNameImportTest.asl") "workspaceNameImportTest native report matches asl-host")
        (assert (testZeroSuite cacheDir) "a runTests suite with zero assertions fails natively")
        (assert (testReportOrder cacheDir) "buffered suite output is flushed before its report")
        true))
