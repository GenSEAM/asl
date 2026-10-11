(module asl-cli/binAslNativeTest :x [runTests] :i [(tools/fleet/run :a run)])

fn probe -> String
  "asl/packages/asl-cli/tests/fixtures/servedBy/servedProbe.asl"

fn fixture name: String -> String
  (str "asl/packages/asl-cli/tests/fixtures/servedBy/" name ".asl")

fn ! envWith extra: (List String) -> (List String)
  (listAppend (cons (str "SERVED_STOP_PID=" (stringFromInt64 (procSelf))) (cons "ASL_NATIVE_CLI_WAIT=1" extra))
    (filter (fn [(row String)] -> Bool (not (or (stringStartsWith? row "ASL_HOST=") (or (stringStartsWith? row "SERVED_STOP_PID=") (stringStartsWith? row "ASL_NATIVE_TRACE="))))) (run/childEnv (list))))

fn ! binAsl! root: String args: (List String) env: (List String) -> run/Done
  (run/runOneLimited (run/job (cons (str root "/bin/asl") args) root env) (run/limits 1500 64))

fn ! binAslSplit! root: String args: (List String) env: (List String) errFile: String -> run/Done
  (run/runOneLimited (run/job (listAppend (list "/bin/sh" "-c" "exec \"$0\" \"$@\" 2>\"$BIN_ASL_ERR\"" (str root "/bin/asl")) args) root (cons (str "BIN_ASL_ERR=" errFile) env)) (run/limits 1500 64))

fn freshSuite tag: String -> String
  (str "(module quietFixture/quietTest :x [runTests] :i [])\n\nfn runTests -> Bool\n  (do (assert (= (stringLength \"" tag "\") " (stringFromInt64 (stringLength tag)) ") \"the tag has its length\")\n      true)\n")

fn ! testServed root: String host: String -> Bool
  (let [(native (binAsl! root (list "test" (probe)) (envWith (list))))
        (forced (binAsl! root (list "test" (probe)) (envWith (list (str "ASL_HOST=" host)))))
        (checked (binAsl! root (list "check" "asl/packages/asl-cli/tests/fixtures/sweep/passTest.asl") (envWith (list))))]
    (do (assert (= native.verdict "exit") "bin/asl test ended on its own, inside the limit")
        (assert (= native.exit 0) (str "bin/asl test served the probe natively: " native.out))
        (assert (stringContains? native.out "servedProbe.asl: 4 assertion(s) executed, 1 refutation(s) executed") "the native run reports the probe's four assertions and one refutation")
        (refute (stringContains? native.out "runs on asl-host") "bin/asl printed no host fallback note for test")
        (assert (!= forced.exit 0) "with ASL_HOST set, bin/asl test runs on asl-host and the probe fails")
        (assert (stringContains? forced.out "no asl-host stands between bin/asl and this suite") "the forced host run fails on the host refutation")
        (assert (= checked.exit 0) (str "bin/asl check still answers through asl-host: " checked.out))
        (assert (stringContains? checked.out "asl: check is not native yet, so it runs on asl-host") "the check fallback names its verb on stderr")
        (assert (stringContains? checked.out "ok asl/packages/asl-cli/tests/fixtures/sweep/passTest.asl") "the host check result follows the note")
        true))

fn ! testUnsupportedFallsBack root: String -> Bool
  (let [(gap (binAsl! root (list "test" (fixture "unsupportedProbe")) (envWith (list))))
        (failing (binAsl! root (list "test" (fixture "failingProbe")) (envWith (list))))]
    (do (assert (= gap.exit 0) (str "a suite the native lowering rejects keeps the asl-host verdict: " gap.out))
        (assert (stringContains? gap.out (str "asl: " (fixture "unsupportedProbe") " runs on asl-host: ERR_NATIVE_UNSUPPORTED: ")) "the rerun note names the suite and the gap")
        (assert (stringContains? gap.out "ERR_LOWER_UNSUPPORTED] 'quote'") "the note carries the lowering diagnostic")
        (assert (stringContains? gap.out "unsupportedProbe.asl: 1 assertion(s) executed (1 passed)") "asl-host ran the suite's assertion")
        (assert (= failing.exit 1) (str "a suite that fails natively fails: " failing.out))
        (assert (stringContains? failing.out "ERR_ASSERT: assertion failed: two has two letters") "the native failure is reported")
        (refute (stringContains? failing.out "runs on asl-host") "a native test failure is never rerun on asl-host")
        true))

fn ! testQuiet root: String host: String -> Bool
  (let [(dir (str root "/.asl/cache/binAslQuiet/" (stringFromInt64 (procSelf))))
        (tag (str "quiet" (stringFromInt64 (procSelf)) "x" (stringFromInt64 (nowNs))))
        (rel (str ".asl/cache/binAslQuiet/" (stringFromInt64 (procSelf)) "/quietTest.asl"))
        (made (mt (dirCreate dir) ((err e) (err e)) ((ok _) (fileWrite (str dir "/quietTest.asl") (freshSuite tag)))))
        (nativeErr (str dir "/native.err"))
        (hostErr (str dir "/host.err"))
        (native (binAslSplit! root (list "test" rel) (envWith (list)) nativeErr))
        (forced (binAslSplit! root (list "test" rel) (envWith (list (str "ASL_HOST=" host))) hostErr))
        (nativeText (resultOr (fileRead nativeErr) "unreadable"))
        (hostText (resultOr (fileRead hostErr) "unreadable"))
        (cleaned (run/runOneLimited (run/job (list "/bin/rm" "-rf" dir) root (run/childEnv (list))) (run/limits 30 4)))]
    (do (assert (ok? made) "the fresh suite was written")
        (assert (= native.exit 0) (str "the fresh suite passes natively: " native.out nativeText))
        (assert (= forced.exit 0) (str "the fresh suite passes on asl-host: " forced.out hostText))
        (refute (stringContains? nativeText "NATIVE-") (str "native stderr carries no NATIVE-* telemetry: " nativeText))
        (assert (= nativeText hostText) (str "native stderr equals the host path's stderr: native " nativeText " host " hostText))
        (assert (= cleaned.exit 0) "the fresh suite was removed")
        true))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (host (str root "/asl/host/out/asl-host"))]
    (and (testServed root host) (and (testUnsupportedFallsBack root) (testQuiet root host))))
