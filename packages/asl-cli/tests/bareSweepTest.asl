(module asl-cli/tests/bareSweepTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt) (asl-tools/fleet/run :a run) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref ASL-TEST-EMPTY-ARG :do "a bare asl test or asl check sweeps every suite or file, so it must be asked for with --all: bare exits 2 with ERR_BARE_SWEEP and starts nothing; --all with paths is a usage error; --all alone still sweeps. Run by the natively built CLI in a one-file fixture workspace with a 30 s bound, so a leaked sweep stays small and cannot run for hours")
fn ! scratchBase! -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/bareSweepTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))

fn onlyFileSource -> String
  "(module bareSweepFixture/onlyFile :x [runTests] :i [])\n\nfn runTests -> Bool\n  true\n"

fn ! buildFixtureRepo! root: String -> Bool
  (let [(d1 (dirCreate (str root "/asl/grammar")))
        (f1 (fileWrite (str root "/asl/grammar/rules.asn") "(:rules)\n"))
        (f3 (fileWrite (str root "/onlyFile.asl") (onlyFileSource)))]
    (and (ok? d1) (and (ok? f1) (and (ok? f3) (gk/initGitRepoWith! root "bareSweepTest" "bareSweepTest@example.invalid" (list "onlyFile.asl"))))))

fn ! cli! binary: String root: String args: (List String) -> run/Done
  (run/runOneLimited (run/job (cons binary args) root (list "PATH=/usr/bin:/bin" (str "HOME=" root) "TMPDIR=/tmp" (str "ASL_ROOT=" root) (str "ASL_CLI_ROOT=" root))) (run/limits 30 16))

fn ! refused binary: String root: String verb: String args: (List String) label: String want: String -> Bool
  (let [(d (cli! binary root (cons verb args)))]
    (do
      (assert (= d.verdict "exit") (str label ": ended on its own, not by the 30 s bound: " d.out))
      (assert (= d.exit 2) (str label ": exits 2, got " (stringFromInt64 d.exit) ": " d.out))
      (assert (stringContains? d.out want) (str label ": names " want ": " d.out))
      (refute (stringContains? d.out "(:sweep ") (str label ": starts no sweep: " d.out))
      true))

fn ! runTests -> Bool
  (let [(base (scratchBase!))
        (fixtureRoot (str base "/fx"))
        (built (nt/prepareRun "asl/packages/asl-cli/src/native.asl" (nt/fingerprint)))
        (madeBase (dirCreate base))
        (fixtureReady (buildFixtureRepo! fixtureRoot))]
    (do
      (assert (some? built.binary) (str "asl/packages/asl-cli/src/native.asl builds natively: " built.reason))
      (assert (ok? madeBase) "scratch base directory is created")
      (assert fixtureReady "the one-file fixture repo is built")
      (let [(binary (optionOr built.binary ""))
            (r1 (refused binary fixtureRoot "test" (list) "bare asl test" "ERR_BARE_SWEEP"))
            (r2 (refused binary fixtureRoot "check" (list) "bare asl check" "ERR_BARE_SWEEP"))
            (r3 (refused binary fixtureRoot "test" (list "--all" "onlyFile.asl") "asl test --all with a path" "ERR_USAGE"))
            (r4 (refused binary fixtureRoot "check" (list "--all" "onlyFile.asl") "asl check --all with a path" "ERR_USAGE"))
            (all (cli! binary fixtureRoot (list "check" "--all")))
            (removed (pathRemove base))]
        (do
          (assert (= all.verdict "exit") (str "asl check --all ended on its own: " all.out))
          (assert (= all.exit 0) (str "asl check --all still sweeps the fixture and passes: " all.out))
          (assert (stringContains? all.out "(:sweep :verb check :runner \"native\" :status :passed :files 1") (str "asl check --all reports the one-file sweep: " all.out))
          (assert (ok? removed) "scratch fixture tree removed")
          (and r1 (and r2 (and r3 r4)))))))
