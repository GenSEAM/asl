(module asl-cli/tests/frozenDirTest :x [runTests] :i [(asl-tools/fleet/run :a run) (asl-gates/suiteRunner :a sr)])

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

; (:m :ref TRAIN-SHARED-NATIVE-20261022 :do "the native CLI cache is the caller's shared one (the default $HOME/.asl/run/nativeCli that bin/asl uses), not a private /tmp dir: the suite asserts the frozen/live directory listing, so a private dir only made it cold-build the CLI (about 170s) on every run; the warm-up call stays so a cold shared cache still keeps its build banner out of the measured calls")
fn sharedCache -> String
  (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli")

; (:m :ref FROZENDIR-OWN-FIXTURE-20261023 :do "the frozen/live contract is asserted on a throwaway git root that carries its own asl/grammar/frozen.asn (one frozen and one live trivial suite), so unfreezing a real suite cannot break it and no real suite directory is run; one cheap CLI call over the all-frozen asl-vector/tests dir plus the live testChanged fixture only checks the bin/asl wiring")
fn frozenRel -> String
  "suites/frozenTest.asl"

fn liveRel -> String
  "suites/liveTest.asl"

fn suiteText name: String ok: String -> String
  (str "(module suites/" name " :x [runTests] :i [])\n\nfn runTests -> Bool\n  (do (assert (= 1 " ok ") \"" name " ran\") true)\n")

fn ! writeFixture! root: String -> Bool
  (and (ok? (dirCreate (str root "/asl")))
       (and (ok? (dirCreate (str root "/asl/grammar")))
            (and (ok? (dirCreate (str root "/suites")))
                 (and (ok? (fileWrite (str root "/asl/grammar/frozen.asn")
                                      (str "(:frozenPaths :v 1\n  (:frozen :path \"" (frozenRel) "\" :kind suite :reason \"fixture\"))\n")))
                      (and (ok? (fileWrite (str root "/" (frozenRel)) (suiteText "frozenTest" "2")))
                           (ok? (fileWrite (str root "/" (liveRel)) (suiteText "liveTest" "1"))))))))

fn ! gitIndexed! root: String -> Bool
  (match (sr/gitRun! root (list "init" "-q"))
    ((err _) false)
    ((ok i) (match (sr/gitRun! root (list "add" "-A"))
              ((err _) false)
              ((ok a) (and (= i.code 0) (= a.code 0))))))

fn ! removeTree! root: String path: String -> Bool
  (let [(done (run/runOneLimited (run/job (list "/bin/rm" "-rf" path) root (run/childEnv (list))) (run/limits 30 4)))]
    (= done.exit 0))

fn suitesText r: (Result (List String) String) -> String
  (match r
    ((ok l) (stringJoin l ","))
    ((err e) e))

fn countText r: (Result Int64 String) -> String
  (match r
    ((ok n) (stringFromInt64 n))
    ((err e) e))

fn ! fixtureChecks! base: String -> Bool
  (let [(made (writeFixture! base))
        (indexed (gitIndexed! base))
        (dirRun (sr/discover base (list "suites")))
        (dirCount (sr/frozenCount base (list "suites")))
        (explicitRun (sr/discover base (list (frozenRel))))
        (explicitCount (sr/frozenCount base (list (frozenRel))))]
    (do (assert made "the throwaway frozen/live fixture was written")
        (assert indexed "the throwaway fixture is a git root with both suites indexed")
        (assert (= (suitesText dirRun) (liveRel)) (str "a directory run keeps the live suite and drops the frozen one: " (suitesText dirRun)))
        (assert (= (countText dirCount) "1") (str "a directory run counts the one frozen suite: " (countText dirCount)))
        (assert (listContains? (resultOr explicitRun (list)) (frozenRel)) (str "an explicitly named frozen suite still runs: " (suitesText explicitRun)))
        (assert (= (countText explicitCount) "0") (str "an explicitly named frozen suite is not counted frozen: " (countText explicitCount)))
        true))

fn ! checks! mode: String dir: run/Done -> Bool
  (do
    (assert (or (= dir.exit 0) (= dir.exit 1)) (str mode " directories with frozen suites exited normally: " dir.out))
    (assert (stringContains? dir.out "(:test :frozen 2)") (str mode " reports both frozen vector suites: " dir.out))
    (assert (not (stringContains? dir.out "vectorTest.asl:")) (str mode " does not run a frozen suite of a directory: " dir.out))
    (assert (not (stringContains? dir.out "vectorizerTest.asl:")) (str mode " does not run the other frozen suite of a directory: " dir.out))
    (assert (stringContains? dir.out "testChanged/alphaTest.asl:") (str mode " runs the live suites of the other directory: " dir.out))
    true)

; (:m :ref NATIVE-STALE-CONVERGE :do "a brand-new cache dir (the common case: no ASL_NATIVE_CLI_CACHE preset) always cold-starts bin/asl's native build on its first call, regardless of verb; that build's own progress lines landed in the very first measured call's captured output and polluted the substring checks below, so a throwaway warm-up run forces the cold-start build to finish before any output is inspected")
fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (configuredCache (optionOr (envGet "ASL_NATIVE_CLI_CACHE") ""))
        (cache (if (stringEmpty? configuredCache) (sharedCache) configuredCache))
        (frozenDir "asl/packages/asl-vector/tests")
        (liveDir "asl/packages/asl-cli/tests/fixtures/testChanged")
        (base (resultOr (sr/makeTempDir! "frozenDirTest") ""))
        (fixture (fixtureChecks! base))
        (cleaned (removeTree! root base))
        (warm (cliWithin! root cache (warmupDeadlineS) (list "test" liveDir)))
        (nativeDir (cli! root cache (list "test" frozenDir liveDir)))]
    (do (assert (not (stringEmpty? base)) "the throwaway root was created")
        (assert fixture "the throwaway fixture checks passed")
        (assert cleaned "the throwaway root was removed")
        (assert (or (= warm.exit 0) (= warm.exit 1)) (str "the warm-up run (cold-start build) finished before any measured call: " warm.out))
        (checks! "bin/asl native path" nativeDir)))
