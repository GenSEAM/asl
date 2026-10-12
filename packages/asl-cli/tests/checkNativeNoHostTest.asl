(module asl-cli/tests/checkNativeNoHostTest
  :x [runTests]
  :i [(tools/nativeTest :a nt) (tools/fleet/run :a run) (asl-proc/gitFixture :a gf)])

fn ! scratchBase! -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/checkNativeNoHostTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))

fn onlyFileSource -> String
  "(module checkNoHostFixture/onlyFile :x [runTests] :i [])\n\nfn runTests -> Bool\n  true\n"

fn envName row: String -> String
  (optionOr (listHead (stringSplit row "=")) row)

fn isolatedEnv home: String overrides: (List String) -> (List String)
  (let [(names (map envName overrides))]
    (listAppend (filter (fn [(row String)] -> Bool (not (listContains? names (envName row))))
      (list "PATH=/usr/bin:/bin" (str "HOME=" home) "TMPDIR=/tmp"))
      overrides))

fn ! buildFixtureRepo! root: String -> Bool
  (and (ok? (gf/initContained! root))
    (and (ok? (gf/gitWrite! root (list "config" "user.name" "checkNativeNoHostTest") (none)))
      (and (ok? (gf/gitWrite! root (list "config" "user.email" "checkNativeNoHostTest@example.invalid") (none)))
        (and (ok? (fileWrite (str root "/onlyFile.asl") (onlyFileSource)))
          (and (ok? (gf/gitWrite! root (list "add" "-A") (none)))
            (ok? (gf/gitWrite! root (list "commit" "-q" "-m" "seed") (none))))))))

fn ! buildPoisonHost! path: String -> Bool
  (and (ok? (fileWrite path "#!/bin/sh\nexit 97\n"))
       (ok? (fileChmod path 493)))

fn ! testBareSweepIgnoresPoisonHost binary: String root: String fixtureRoot: String poison: String -> Bool
  (let [(env (isolatedEnv fixtureRoot (list (str "ASL_ROOT=" fixtureRoot) (str "ASL_CLI_HOST_BIN=" poison) (str "ASL_HOST=" poison))))
        (d (run/runOneLimited (run/job (list binary "check") root env) (run/limits 60 16)))]
    (do
      (assert (= d.verdict "exit") (str "the native binary ended on its own for bare check: " d.out))
      (assert (= d.exit 0) (str "bare check on a one-file fixture passes without asl-host: " d.out))
      (assert (stringContains? d.out "(:sweep :verb check :runner \"native\" :status :passed :files 1 :passed 1 :failed 0 :unbalanced 0 :frozen 0)") (str "the sweep report shows one file checked natively: " d.out))
      (refute (stringContains? d.out "97") (str "the poisoned stand-in host binary was never invoked (its exit 97 never surfaces): " d.out))
      true))

fn ! testSingleFileIgnoresPoisonHost binary: String root: String poison: String -> Bool
  (let [(env (isolatedEnv root (list (str "ASL_CLI_HOST_BIN=" poison) (str "ASL_HOST=" poison))))
        (d (run/runOneLimited (run/job (list binary "check" "asl/packages/asl-cli/tests/fixtures/sweep/passTest.asl") root env) (run/limits 60 16)))]
    (do
      (assert (= d.verdict "exit") (str "the native binary ended on its own for a single-file check: " d.out))
      (assert (= d.exit 0) (str "check on a single file passes without asl-host: " d.out))
      (assert (stringContains? d.out "ok asl/packages/asl-cli/tests/fixtures/sweep/passTest.asl: 1 module(s) checked") (str "the native checker's own verdict is printed: " d.out))
      (refute (stringContains? d.out "97") (str "the poisoned stand-in host binary was never invoked for a single-file check: " d.out))
      true))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (base (scratchBase!))
        (fixtureRoot (str base "/fx"))
        (poison (str base "/poisonHost"))
        (built (nt/prepareRun "asl/packages/asl-cli/src/native.asl" (nt/fingerprint)))
        (madeBase (dirCreate base))
        (fixtureReady (buildFixtureRepo! fixtureRoot))
        (poisonReady (buildPoisonHost! poison))]
    (do
      (assert (some? built.binary) (str "asl/packages/asl-cli/src/native.asl builds natively: " built.reason))
      (assert (ok? madeBase) "scratch base directory is created")
      (assert fixtureReady "the one-file fixture repo is built")
      (assert poisonReady "the poisoned stand-in host binary is written and made executable")
      (let [(binary (optionOr built.binary ""))
            (r1 (testBareSweepIgnoresPoisonHost binary root fixtureRoot poison))
            (r2 (testSingleFileIgnoresPoisonHost binary root poison))
            (removed (pathRemove base))]
        (do
          (assert (ok? removed) "scratch fixture tree removed")
          (and r1 r2)))))
