(module asl-cli/tests/frozenDirTest :x [runTests] :i [(tools/fleet/run :a run)])

fn ! cliWithin! root: String cache: String timeoutS: Int64 argv: (List String) -> run/Done
  (run/runOneLimited
    (run/job (listAppend (list "/usr/bin/nice" "-n" "15" (str root "/bin/asl")) argv) root
             (run/childEnv (list (str "ASL_ROOT=" root)
                                 (str "ASL_CLI_ROOT=" root)
                                 (str "ASL_PRELUDE=" root "/asl/prelude/prelude.asl")
                                 (str "ASL_NATIVE_CLI_CACHE=" cache))))
    (run/limits timeoutS 64))

fn ! cli! root: String cache: String argv: (List String) -> run/Done
  (cliWithin! root cache 180 argv)

; (:m :ref FROZENDIR-COLDLIMIT-20261022 :do "the cold-start warm-up waits for the native build to finish under a hang guard, not a speed claim: the build took 184s under fleet load and the shared 180s kill limit made the suite red twice; measured calls after it keep 180s")
fn warmupDeadlineS -> Int64
  1200

; (:m :ref FROZENDIR-STALE :do "asl/grammar/frozen.asn freezes distribTest and installParityTest inside the live asl-target-sh/tests and the whole asl-vector/tests package; the other asl-target-sh suites unfroze on 2026-10-15")
fn mixedDir -> String
  "asl/packages/asl-target-sh/tests"

fn frozenSuites -> (List String)
  (list "asl/packages/asl-target-sh/tests/distribTest.asl" "asl/packages/asl-target-sh/tests/installParityTest.asl")

fn liveSuites -> (List String)
  (list "asl/packages/asl-target-sh/tests/astTest.asl" "asl/packages/asl-target-sh/tests/emitPs1Test.asl"
        "asl/packages/asl-target-sh/tests/emitShTest.asl" "asl/packages/asl-target-sh/tests/lowerTest.asl")

fn frozenFile -> String
  "asl/packages/asl-vector/tests/vectorTest.asl"

fn ! checks! mode: String dir: run/Done explicit: run/Done live: run/Done -> Bool
  (do
    (assert (or (= dir.exit 0) (= dir.exit 1)) (str mode " directory with frozen suites exited normally: " dir.out))
    (assert (stringContains? dir.out "(:test :frozen ") (str mode " prints frozen count"))
    (assert (not (stringContains? dir.out "(:test :frozen 0)")) (str mode " reports at least one frozen suite: " dir.out))
    (assert (listAll? (fn [(s String)] -> Bool (not (stringContains? dir.out (str s ":")))) (frozenSuites)) (str mode " does not run the frozen suites of a directory: " dir.out))
    (assert (listAll? (fn [(s String)] -> Bool (stringContains? dir.out (str s ":"))) (liveSuites)) (str mode " runs the live suites of the same directory: " dir.out))
    (assert (= explicit.exit 0) (str mode " explicitly named frozen file still runs: " explicit.out))
    (assert (stringContains? explicit.out (str (frozenFile) ":")) (str mode " runs explicitly named frozen suite: " explicit.out))
    (assert (= live.exit 0) (str mode " live directory exits successfully: " live.out))
    (assert (stringContains? live.out "(:test :frozen 0)") (str mode " reports zero frozen suites for live directory"))
    true)

; (:m :ref NATIVE-STALE-CONVERGE :do "a brand-new cache dir (the common case: no ASL_NATIVE_CLI_CACHE preset) always cold-starts bin/asl's native build on its first call, regardless of verb; that build's own progress lines landed in the very first measured call's captured output and polluted the frozen/live substring checks below, flipping this suite red whenever the cache happened to arrive cold rather than pre-warmed by an earlier train step. A throwaway warm-up run forces the cold-start build to finish before any output is inspected, so the suite's own result no longer depends on whether the cache arrived warm or cold")
fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (configuredCache (optionOr (envGet "ASL_NATIVE_CLI_CACHE") ""))
        (ownsCache (stringEmpty? configuredCache))
        (cache (if ownsCache (str "/tmp/aslFrozenDirTest." (stringFromInt64 (procSelf))) configuredCache))
        (liveDir "asl/packages/asl-cli/tests/fixtures/testChanged")
        (warm (cliWithin! root cache (warmupDeadlineS) (list "test" (mixedDir))))
        (nativeDir (cli! root cache (list "test" (mixedDir))))
        (nativeFile (cli! root cache (list "test" (frozenFile))))
        (nativeLive (cli! root cache (list "test" liveDir)))
        (nativeChecks (checks! "bin/asl native path" nativeDir nativeFile nativeLive))
        (removed (if ownsCache (pathRemove cache) (ok ()) ))]
    (do (assert (or (= warm.exit 0) (= warm.exit 1)) (str "the warm-up run of mixedDir (cold-start build) finished before any measured call: " warm.out))
        (and nativeChecks (ok? removed))))
