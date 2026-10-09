(module asl-gates/tests/runnerMainTest
  :x [runTests]
  :i [(asl-gates/runnerMain :a rm) (tests/parity/gates/runnerCorpus :a gr) (asl-gates/tests/runnerParityTest :a rp)])

fn testParseDependenciesValid -> Bool
  (let [(text "(:package foo :version \"0.1.0\" :dependencies [\"dep-a\" \"dep-b\"])")
        (res (rm/parseDependencies text))]
    (mt res
      ((err e) false)
      ((ok deps)
       (do
         (assert (= (listLength deps) 2) "two dependencies parsed")
         (assert (= (optionOr (listHead deps) "") "dep-a") "first dep is dep-a")
         (assert (= (optionOr (listLast deps) "") "dep-b") "second dep is dep-b")
         true))))

fn testParseDependenciesEmpty -> Bool
  (let [(text "(:package bar :version \"0.1.0\" :dependencies [])")
        (res (rm/parseDependencies text))]
    (mt res
      ((err e) false)
      ((ok deps)
       (do
         (assert (= (listLength deps) 0) "zero dependencies parsed")
         true))))

fn testParseDependenciesMissing -> Bool
  (let [(text "(:package baz :version \"0.1.0\")")
        (res (rm/parseDependencies text))]
    (mt res
      ((ok _) false)
      ((err why)
       (do
         (assert (= why "no top-level :dependencies") "expected missing dependencies error")
         true))))

fn testParseDependenciesNonString -> Bool
  (let [(text "(:package bad :version \"0.1.0\" :dependencies [123])")
        (res (rm/parseDependencies text))]
    (mt res
      ((ok _) false)
      ((err why)
       (do
         (assert (stringStartsWith? why ":dependencies holds a non-string item") "expected non-string error")
         true))))

fn testPackagesSurvey! -> Bool
  (let [(res (rm/packages!))
        (pkgs (pairFirst res))
        (errors (pairSecond res))]
    (do
      (assert (= (listLength errors) 0) "packages parse errors is 0")
      (assert (> (listLength pkgs) 40) "packages count > 40")
      (let [(gatesPkg (rm/findPackageByName pkgs "asl-gates"))]
        (do
          (assert (some? gatesPkg) "asl-gates package found")
          (assert (= (optionOr gatesPkg (rm/makePackageInfo "" "" (list))).dir "asl/packages/asl-gates") "asl-gates dir matches")
          true))))

fn testChooseBaseCurrent! -> Bool
  (let [(res (rm/chooseBase!))
        (base (pairFirst res))
        (problems (pairSecond res))]
    (do
      (assert (none? base) "base is none on current tree")
      (assert (= (listLength problems) 0) "problems is empty")
      true))

fn shq s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn sh! dir: String script: String -> String
  (let [(res (command! (list "/bin/sh" "-c" script) dir (none)))]
    (do
      (assert (= res.code 0) (str "scratch step exits 0: " script " -> " res.errText))
      (stringTrim res.out)))

fn scratchDir! tag: String -> String
  (let [(tmp (optionOr (envGet "TMPDIR") "/tmp"))
        (res (command! (list "/usr/bin/mktemp" "-d" (str tmp "/" tag ".XXXXXX")) (workRoot!) (none)))]
    (do
      (assert (= res.code 0) (str "scratch directory created: " res.errText))
      (stringTrim res.out)))

fn fullGreenText sha: String tree: String body: String digest: String -> String
  (str "(:fullGreen :v 1 :sha \"" sha "\" :tree \"" tree "\" :date \"2026-09-26\" :receiptDigest \"" digest "\")\n" body)

fn writeRecord! dir: String name: String sha: String tree: String body: String -> Bool
  (let [(digest (bytesSha256 (stringToBytes body)))
        (w (fileWrite (str dir "/.asl/mem/benchmarks/fullGreen/" name) (fullGreenText sha tree body digest)))]
    (do
      (assert (ok? w) (str "record written: " name))
      true))

fn commitAll! dir: String msg: String -> String
  (sh! dir (str "/usr/bin/git add -A && /usr/bin/git commit -q -m " msg " && /usr/bin/git rev-parse HEAD"))

fn treeOf! dir: String sha: String -> String
  (sh! dir (str "/usr/bin/git rev-parse " sha "^{tree}"))

fn renderChooseBase res: (Pair (Option rm/FullGreenRecord) (List String)) -> String
  (str (mt (pairFirst res) ((some b) b.sha) ((none) "none")) "\n" (stringJoin (pairSecond res) "\n") "\n")

fn testChooseBaseScratch! -> Bool
  (let [(dir (scratchDir! "aslChooseBase"))
        (shaA (sh! dir "/usr/bin/git init -q . && /usr/bin/git config user.email t@example.invalid && /usr/bin/git config user.name t && mkdir -p .asl/mem/benchmarks/fullGreen && printf '(:knownRed :v 1\\n  (:suite \"aTest.asl\" :cause \"ERR_LOAD\" :failedAssertDigest \"d1\" :since \"s\")\\n  (:suite \"bTest.asl\" :cause \"ERR_LOAD\" :failedAssertDigest \"d2\" :since \"s\")\\n)\\n' > .asl/mem/knownRed.asn && /usr/bin/git add -A && /usr/bin/git commit -q -m A && /usr/bin/git rev-parse HEAD"))
        (treeA (treeOf! dir shaA))
        (_ (writeRecord! dir (str shaA ".asn") shaA treeA "receipt A\n"))
        (shaC (commitAll! dir "C"))
        (shaB (sh! dir "echo g > g && /usr/bin/git add -A && /usr/bin/git commit -q -m B && /usr/bin/git rev-parse HEAD"))
        (treeB (treeOf! dir shaB))
        (shaS (sh! dir (str "/usr/bin/git checkout -q -b side " shaA " && echo s > s && /usr/bin/git add -A && /usr/bin/git commit -q -m S && /usr/bin/git rev-parse HEAD && /usr/bin/git checkout -q -")))
        (treeS (treeOf! dir shaS))
        (_ (writeRecord! dir (str shaB ".asn") shaB treeB "receipt B\n"))
        (_ (writeRecord! dir (str shaC ".asn") shaC treeA "receipt C with the tree of A\n"))
        (_ (writeRecord! dir (str shaS ".asn") shaS treeS "receipt S off the first-parent line\n"))
        (_ (writeRecord! dir "misnamed.asn" shaA treeA "receipt A again\n"))
        (badWrite (fileWrite (str dir "/.asl/mem/benchmarks/fullGreen/bad.asn") (fullGreenText shaA treeA "body\n" (bytesSha256 (stringToBytes "other body\n")))))
        (_ (commitAll! dir "D"))
        (_ (writeRecord! dir (str shaA ".asn") shaA treeA "receipt A rewritten\n"))
        (_ (sh! dir "/usr/bin/grep -v bTest .asl/mem/knownRed.asn > k.tmp && mv k.tmp .asl/mem/knownRed.asn"))
        (res (rm/chooseBaseAt! dir))
        (problems (pairSecond res))
        (short (optionOr (stringSlice shaB 0 12) ""))
        (dir0 ".asl/mem/benchmarks/fullGreen/")
        (recordProblems (listSort (list (str dir0 "bad.asn does not re-hash to its :receiptDigest") (str dir0 "misnamed.asn is not named for its :sha") (str dir0 shaC ".asn :tree is not the tree of its :sha"))))
        (want (str shaB "\n" (stringJoin (listAppend recordProblems (list (str "M " dir0 shaA ".asn since base " short) (str ".asl/mem/knownRed.asn lost 1 line(s) since base " short))) "\n") "\n"))
        (aslOut (renderChooseBase res))]
    (do
      (assert (ok? badWrite) "bad record written")
      (assert (= (mt (pairFirst res) ((some b) b.sha) ((none) "none")) shaB) "base is the newest ancestor record, B")
      (assert (listContains? problems ".asl/mem/benchmarks/fullGreen/bad.asn does not re-hash to its :receiptDigest") "bad digest named")
      (assert (listContains? problems ".asl/mem/benchmarks/fullGreen/misnamed.asn is not named for its :sha") "misnamed record named")
      (assert (listContains? problems (str ".asl/mem/benchmarks/fullGreen/" shaC ".asn :tree is not the tree of its :sha")) "wrong tree named")
      (assert (listContains? problems (str "M .asl/mem/benchmarks/fullGreen/" shaA ".asn since base " short)) "record rewritten since base named")
      (assert (listContains? problems (str ".asl/mem/knownRed.asn lost 1 line(s) since base " short)) "knownRed shrink since base named")
      (assert (= (listLength problems) 5) "exactly five problems; the side record is skipped silently")
      (assert (= aslOut want) (str "chooseBase output is byte-equal to runner.py order (records in git ls-files order, then since-base changes, then the knownRed shrink): asl " aslOut " want " want))
      (assert (ok? (pathRemove dir)) "scratch repo removed")
      true))

fn testAffectedHead! -> Bool
  (let [(root (workRoot!))
        (scratch (scratchDir! "aslAffected"))
        (repo (str scratch "/repo"))
        (_ (sh! scratch (str "/usr/bin/git clone -q --local " (shq root) " repo")))
        (cleanRes (rm/affectedAt! repo "HEAD"))
        (cleanScope (pairFirst cleanRes))
        (cleanSuites (pairFirst (pairSecond cleanRes)))
        (cleanReason (pairSecond (pairSecond cleanRes)))
        (untrackedPath (str repo "/stray.txt"))
        (w (fileWrite untrackedPath "stray\n"))
        (untrackedRes (rm/affectedAt! repo "HEAD"))
        (untrackedScope (pairFirst untrackedRes))
        (untrackedSuites (pairFirst (pairSecond untrackedRes)))
        (untrackedReason (pairSecond (pairSecond untrackedRes)))]
    (do
      (assert (ok? w) "stray file written")
      (assert (= cleanScope ":affected") "clean affected scope is :affected")
      (assert (stringContains? cleanReason "asl-gates") "clean reason mentions asl-gates")
      (assert (> (listLength cleanSuites) 0) "clean suites list non-empty")
      (assert (= untrackedScope ":full") "untracked scope is :full")
      (assert (= (listLength untrackedSuites) 0) "untracked suites list empty")
      (assert (= untrackedReason "no package manifest owns stray.txt") "untracked reason explains no owning manifest")
      (assert (ok? (pathRemove scratch)) "scratch repo removed")
      true))

fn testParseRunArgs -> Bool
  (let [(empty (rm/makeRunArgs (list) (list) (none) (none)))
        (good (rm/parseRunArgs (list "--suite" "s2.asl" "--path" "p" "--suite" "s1.asl" "--base" "HEAD~1") empty))
        (stray (rm/parseRunArgs (list "--suite" "s1.asl" "s2.asl") empty))
        (bare (rm/parseRunArgs (list "--path" "p" "--suite") empty))
        (full (rm/parseRunArgs (list "--full") empty))]
    (do
      (mt good
        ((err _) (assert false "well-formed run arguments parse"))
        ((ok a)
         (do
           (assert (= a.suites (list "s2.asl" "s1.asl")) "suites kept in argument order")
           (assert (= a.paths (list "p")) "path parsed")
           (assert (= a.base (some "HEAD~1")) "base parsed"))))
      (mt stray
        ((ok _) (assert false "a bare positional is refused"))
        ((err e)
         (do
           (assert (= e.code 64) "bare positional exits 64")
           (assert (= e.line "(:runner :status :failed :err ERR_USAGE :ev \"s2.asl\")") "bare positional names the argument"))))
      (mt bare
        ((ok _) (assert false "--suite without a value is refused"))
        ((err e)
         (do
           (assert (= e.code 2) "--suite without a value exits 2")
           (assert (= e.line "(:runner :status :failed :err ERR_RUNNER :ev \"\")") "--suite without a value is ERR_RUNNER"))))
      (mt full
        ((ok _) (assert false "--full is not a runner.py run flag"))
        ((err e) (assert (= e.code 64) "--full exits 64")))
      true))

fn testForceFullPrefixes -> Bool
  (do
    (assert (rm/isForceFull "bin/asl-full") "bin/asl matches bin/asl-full as a prefix")
    (assert (rm/isForceFull "bin/asl-core-legacy") "bin/asl-core matches as a prefix")
    (assert (rm/isForceFull "scripts/runGateTests.sh.orig") "scripts/runGateTests.sh matches as a prefix")
    (assert (rm/isForceFull ".asl/mem/knownRed.asn.tmp") "knownRed path matches as a prefix")
    (assert (rm/isForceFull "asl/grammar/rules.asn") "directory entry matches")
    (refute (rm/isForceFull "bin/as") "a shorter path is not forced")
    (refute (rm/isForceFull "asl/packages/asl-gates/src/runnerMain.asl") "a package path is not forced")
    true)

fn testBaselineAsserts -> Bool
  (do
    (assert (= (rm/baselineAsserts "(:testTelemetry :v 3\n  :runnerDigest \"0123456789abcdef\"\n  :executedAsserts 812 :executedRefutes 0\n") (some 812)) "baseline executed count read")
    (assert (none? (rm/baselineAsserts "  :runnerDigest \"0123456\"\n  :executedAsserts 812\n")) "a digest under eight characters is refused")
    (assert (none? (rm/baselineAsserts "  :runnerDigest \"0123456789abcdef\"\n  :executedAsserts 0\n")) "zero executed is refused")
    true)

(schema Outcome
  (:f code Int64)
  (:f out String)
  (:f errText String))

fn command! argv: (List String) cwd: String env: (Option (List String)) -> Outcome
  (mt (gr/runCommand! argv cwd env)
    ((err e) (Outcome :code 127 :out "" :errText e))
    ((ok captured) (Outcome :code captured.exit :out captured.stdout :errText captured.stderr)))

fn workRoot! -> String
  (mt (realPath ".")
    ((ok p) p)
    ((err e) (do (assert false (str "realPath . fails: " e)) "")))

fn ! timesLedger! -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/aslRunnerMainTimes." (stringFromInt64 (procSelf)) ".asn")

fn runAsl! dir: String env: String args: String -> Outcome
  (let [(root (workRoot!))
        (argv (listAppend (list (str root "/asl/host/out/asl-host") "run" (str root "/asl/packages/asl-gates/src/runnerMain.asl"))
                          (filter (fn [(arg String)] -> Bool (not (stringEmpty? arg))) (stringSplit args " "))))
        (extra (filter (fn [(kv String)] -> Bool (not (stringEmpty? kv))) (stringSplit env " ")))
        (childEnv (listAppend (filter (fn [(kv String)] -> Bool (not (stringStartsWith? kv "ASL_GATE_TIMES="))) (envList)) (cons (str "ASL_GATE_TIMES=" (timesLedger!)) extra)))]
    (command! argv dir (some childEnv)))

fn testRunUsageParity! -> Bool
  (let [(root (workRoot!))
        (missing (runAsl! root "" "run --suite"))
        (bogus (runAsl! root "" "run --bogus"))
        (path (runAsl! root "" "run --path"))
        (telemetry (runAsl! root "" "gateTests --telemetry"))
        (capture (runAsl! root "" "capture --strict-falsify"))]
    (do
      (assert (= missing.code 2) "run --suite without a value exits 2")
      (assert (stringContains? bogus.out "ERR_USAGE") "unknown run option is diagnosed")
      (assert (= path.code 2) "run --path without a value exits 2")
      (assert (= telemetry.code 2) "gateTests --telemetry without value exits 2")
      (assert (= capture.code 2) "capture rejects a run-only option")
      true))

fn fixtureDir -> String
  "asl/packages/asl-gates/tests/fixtures/runner"

fn fixtureSleepContent -> String
  "#!/bin/sh
: \"${ASL_RUNNER_FIXTURE_SLEEP:?set by runnerMainTest to a uniquely named sleep}\"
\"$ASL_RUNNER_FIXTURE_SLEEP\" 60 >/dev/null 2>&1 &
\"$ASL_RUNNER_FIXTURE_SLEEP\" 30 >/dev/null 2>&1
echo \"(:gate :name sleepyGrandchild :asserts 1 :failed 0)\"
"

fn fixtureProbeAContent -> String
  "#!/bin/sh
: \"${ASL_RUNNER_FIXTURE_LOG:?set by runnerMainTest to a log outside the snapshot}\"
pwd -P >> \"$ASL_RUNNER_FIXTURE_LOG\"
echo probe > probeA.out
echo \"(:gate :name snapshotProbeA :asserts 1 :failed 0)\"
"

fn fixtureProbeBContent -> String
  "#!/bin/sh
: \"${ASL_RUNNER_FIXTURE_LOG:?set by runnerMainTest to a log outside the snapshot}\"
pwd -P >> \"$ASL_RUNNER_FIXTURE_LOG\"
echo probe > probeB.out
echo \"(:gate :name snapshotProbeB :asserts 1 :failed 0)\"
"

fn fixtureRedContent name: String missing: String -> String
  (str "(module asl-gates/tests/fixtures/runner/" name " :x [runTests] :i [])\n\nfn runTests -> Bool\n  (" missing ")\n")

fn redFixturePath name: String -> String
  (str (fixtureDir) "/" name ".asl")

fn redDigest name: String missing: String -> String
  (optionOr (stringSlice (bytesSha256 (stringToBytes (str "ERR_UNKNOWN_SYMBOL\n" (redFixturePath name) ": ERR_UNKNOWN_SYMBOL " missing))) 0 16) "")

fn makeClone! -> String
  (let [(root (workRoot!))
        (scratch (scratchDir! "aslRunnerDiff"))
        (fixDir (str scratch "/repo/" (fixtureDir)))]
    (do
      (sh! scratch (str "/usr/bin/git clone -q --local " (shq root) " repo && mkdir -p " (shq fixDir)))
      (assert (ok? (fileWrite (str fixDir "/sleepyGrandchildTest.sh") (fixtureSleepContent))) "wrote sleep fixture")
      (assert (ok? (fileWrite (str fixDir "/snapshotProbeATest.sh") (fixtureProbeAContent))) "wrote probeA fixture")
      (assert (ok? (fileWrite (str fixDir "/snapshotProbeBTest.sh") (fixtureProbeBContent))) "wrote probeB fixture")
      (assert (ok? (fileWrite (str fixDir "/heldRedTest.asl") (fixtureRedContent "heldRedTest" "heldRedMissing"))) "wrote held red fixture")
      (assert (ok? (fileWrite (str fixDir "/driftRedTest.asl") (fixtureRedContent "driftRedTest" "driftRedMissing"))) "wrote drift red fixture")
      (sh! scratch (str "chmod +x " (shq fixDir) "/*.sh"))
      scratch))

fn readText! path: String -> String
  (mt (fileReadString path)
    ((ok s) s)
    ((err e) (do (assert false (str "read " path ": " e)) "")))

fn dropLastLine text: String -> String
  (let [(body (stringTrim text))
        (lines (stringLines body))]
    (stringJoin (listTake lines (- (listLength lines) 1)) "\n"))

fn editedLedger original: String -> String
  (str (dropLastLine original) "\n"
       "  (:suite \"" (redFixturePath "heldRedTest") "\" :cause \"ERR_UNKNOWN_SYMBOL\" :failedAssertDigest \"" (redDigest "heldRedTest" "heldRedMissing") "\" :since \"R1a2\")\n"
       "  (:suite \"" (redFixturePath "driftRedTest") "\" :cause \"ERR_UNKNOWN_SYMBOL\" :failedAssertDigest \"0000000000000000\" :since \"R1a2\")\n"
       "  (:suite \"asl/packages/asl-gates/tests/siteClaimsTest.asl\" :cause \"ERR_LOAD\" :failedAssertDigest \"1111111111111111\" :since \"R1a2\")\n"
       "  (:suite \"tests/gone/missingTest.asl\" :cause \"ERR_LOAD\" :failedAssertDigest \"2222222222222222\" :since \"R1a2\")\n"
       ")\n")

fn gitStatus! repo: String -> String
  (sh! repo "/usr/bin/git status --porcelain -uall")

fn testRunVerdictParity! scratch: String -> Bool
  (let [(repo (str scratch "/repo"))
        (ledgerPath (str repo "/.asl/mem/knownRed.asn"))
        (original (readText! ledgerPath))
        (edited (editedLedger original))
        (w (fileWrite ledgerPath edited))
        (statusBefore (gitStatus! repo))
        (args (str "run --suite asl/packages/asl-gates/tests/siteClaimsTest.asl --suite " (redFixturePath "driftRedTest") " --suite " (redFixturePath "heldRedTest")))
        (asl (runAsl! repo "" args))
        (aslLedger (readText! ledgerPath))
        (aslStatus (gitStatus! repo))
        (out asl.out)]
    (do
      (assert (ok? w) "edited ledger written")
      (assert (!= edited original) "ledger edit took effect")
      (assert (stringStartsWith? out "(:runner :status :failed :scope :affected :suites 3 :passedSuites 1 :knownRedHeld 1 ") "one held, one passing, receipt failed")
      (assert (stringContains? out (str "(:check :id suite :status :failed :err ERR_KNOWN_RED_DRIFT :suite \"" (redFixturePath "driftRedTest") "\" :ev \"ERR_UNKNOWN_SYMBOL " (redDigest "driftRedTest" "driftRedMissing") " ")) "drift names the new signature")
      (assert (stringContains? out "(:check :id suite :status :failed :err ERR_STALE_KNOWN_RED :suite \"asl/packages/asl-gates/tests/siteClaimsTest.asl\" :ev \"listed in knownRed but passed\")") "stale entry for a passing suite")
      (assert (stringContains? out "(:check :id suite :status :failed :err ERR_STALE_KNOWN_RED :suite \"tests/gone/missingTest.asl\" :ev \"knownRed entry names no suite file\")") "missing-file entry")
      (assert (stringContains? out (str "(:knownRedDelta (:added (:suite \"" (redFixturePath "heldRedTest") "\"")) "delta against HEAD lists the appended entries as added")
      (assert (= asl.code 1) "failed receipt exits 1")
      (assert (= aslLedger edited) "asl runner leaves the ledger as it found it")
      (assert (= aslStatus statusBefore) "asl runner leaves the clone status unchanged")
      (assert (ok? (fileWrite ledgerPath original)) "ledger restored")
      true))

fn probeLines! log: String -> (List String)
  (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines (readText! log)))

fn testSingleSnapshotParity! scratch: String -> Bool
  (let [(repo (str scratch "/repo"))
        (log (str scratch "/probe.log"))
        (env (str "ASL_RUNNER_FIXTURE_LOG=" log))
        (args (str "run --suite " (fixtureDir) "/snapshotProbeATest.sh --suite " (fixtureDir) "/snapshotProbeBTest.sh"))
        (asl (runAsl! repo env args))
        (aslDirs (probeLines! log))
        (dirtied "(:check :id suite :status :failed :err ERR_TREE_DIRTIED :suite \"snapshot\" :ev \"suites wrote probeA.out, probeB.out\")")]
    (do
      (assert (= (listLength aslDirs) 2) "asl runner ran both probes")
      (assert (= (optionOr (listHead aslDirs) "") (optionOr (listLast aslDirs) "-")) "both probes ran in one snapshot")
      (assert (stringContains? asl.out dirtied) "tree dirtying is one snapshot check naming both files")
      (refute (stringContains? asl.out "ERR_TREE_DIRTIED :suite \"asl/") "no per-suite dirtying check")
      (assert (ok? (pathRemove log)) "probe log removed")
      true))

fn grandchildAlive! sleeper: String -> Bool
  (= (command! (list "/usr/bin/pgrep" "-f" sleeper) (workRoot!) (none)).code 0)

fn testTimeoutKillsGroup! scratch: String -> Bool
  (let [(repo (str scratch "/repo"))
        (sleeper (str scratch "/sleepGrandchildR1a"))
        (linked (command! (list "/bin/ln" "-s" "/bin/sleep" sleeper) repo (none)))
        (env (str "ASL_SUITE_TIMEOUT_S=2 ASL_RUNNER_FIXTURE_SLEEP=" sleeper))
        (args (str "run --suite " (fixtureDir) "/sleepyGrandchildTest.sh"))
        (t0 (monotonicNs))
        (asl (runAsl! repo env args))
        (elapsedMs (/ (- (monotonicNs) t0) 1000000))
        (aslAlive (grandchildAlive! sleeper))
        (_ (command! (list "/usr/bin/pkill" "-f" sleeper) repo (none)))]
    (do
      (assert (= linked.code 0) "uniquely named sleep linked")
      (refute aslAlive "asl runner kills the timed-out suite's process group, grandchild included")
      (assert (< elapsedMs 30000) (str "asl run exits before the fixture's 30 s sleeper: " (stringFromInt64 elapsedMs) " ms"))
      (assert (stringContains? asl.out ":err ERR_TIMEOUT :suite \"asl/packages/asl-gates/tests/fixtures/runner/sleepyGrandchildTest.sh\" :ev \"ERR_TIMEOUT ") "timeout verdict reported")
      true))

fn testGateTestsTolerance! scratch: String -> Bool
  (let [(repo (str scratch "/repo"))
        (env "ASL_DECLARED_GAP_TOLERANCE=100000")
        (args (str "gateTests evalRunner node " (redFixturePath "heldRedTest")))
        (asl (runAsl! repo env args))]
    (do
      (assert (stringContains? asl.out "    Declared-vs-executed reconciliation passed: ") "the gap is within the tolerance")
      (assert (stringContains? asl.out " (tolerance 100000)\n") "ASL_DECLARED_GAP_TOLERANCE is read")
      (assert (stringContains? asl.errText "    x executed assertions 0 below floor 400") "the executed floor still fails the run")
      (assert (= asl.code 1) "gateTests exits 1 below the floor")
      true))

fn testRunDifferential! -> Bool
  (let [(scratch (makeClone!))]
    (do
      (assert (testRunVerdictParity! scratch) "run verdict parity")
      (assert (testSingleSnapshotParity! scratch) "single snapshot parity")
      (assert (testTimeoutKillsGroup! scratch) "timeout kills the group")
      (assert (testGateTestsTolerance! scratch) "gateTests tolerance parity")
      (assert (ok? (pathRemove scratch)) "clone removed")
      true))

fn testChooseBaseReplay! -> Bool
  (do
    (assert (gr/replayCase! "runBase") "pinned runner.py runBase fixture replays chooseBase through ASL only")
    (assert (rp/replayChooseBaseFixtures!) "synthetic chooseBase fixtures replay through ASL only")
    true)

fn ! runTests -> Bool
  (do
    (assert (testParseDependenciesValid) "parseDependencies valid")
    (assert (testParseDependenciesEmpty) "parseDependencies empty")
    (assert (testParseDependenciesMissing) "parseDependencies missing")
    (assert (testParseDependenciesNonString) "parseDependencies non-string")
    (assert (testPackagesSurvey!) "packages survey")
    (assert (testChooseBaseCurrent!) "chooseBase current")
    (assert (testChooseBaseScratch!) "chooseBase scratch repo")
    (assert (testAffectedHead!) "affected HEAD")
    (assert (testParseRunArgs) "parseRunArgs")
    (assert (testForceFullPrefixes) "FORCE_FULL prefixes")
    (assert (testBaselineAsserts) "gateTests baseline")
    (assert (testRunUsageParity!) "run usage parity")
    (assert (testRunDifferential!) "run differential")
    (assert (testChooseBaseReplay!) "chooseBase fixture replay")
    (assert (ok? (fileReadString (timesLedger!))) "runner children wrote the private gateTimes ledger")
    (assert (ok? (pathRemove (timesLedger!))) "private gateTimes ledger removed")
    true)
