(module asl-gates/tests/runnerMainTest
  :x [runTests]
  :i [(asl-gates/runnerMain :a rm) (tests/parity/gates/runnerCorpus :a gr) (asl-gates/tests/runnerParityTest :a rp) (asl-proc/gitFixture :a gf)])

fn testParseDependenciesValid -> Bool
  (let [(text "(:package foo :version \"0.1.0\" :dependencies [\"dep-a\" \"dep-b\"])")
        (res (rm/parseDependencies text))]
    (match res
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
    (match res
      ((err e) false)
      ((ok deps)
       (do
         (assert (= (listLength deps) 0) "zero dependencies parsed")
         true))))

fn testParseDependenciesMissing -> Bool
  (let [(text "(:package baz :version \"0.1.0\")")
        (res (rm/parseDependencies text))]
    (match res
      ((ok _) false)
      ((err why)
       (do
         (assert (= why "no top-level :dependencies") "expected missing dependencies error")
         true))))

fn testParseDependenciesNonString -> Bool
  (let [(text "(:package bad :version \"0.1.0\" :dependencies [123])")
        (res (rm/parseDependencies text))]
    (match res
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
  (let [(withCeiling (listAppend (envList) (list (str "GIT_CEILING_DIRECTORIES=" (gf/ceilingFor! dir)))))
        (res (command! (list "/bin/sh" "-c" script) dir (some withCeiling)))]
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
  (str (match (pairFirst res) ((some b) b.sha) ((none) "none")) "\n" (stringJoin (pairSecond res) "\n") "\n")

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
      (assert (= (match (pairFirst res) ((some b) b.sha) ((none) "none")) shaB) "base is the newest ancestor record, B")
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
      (match good
        ((err _) (assert false "well-formed run arguments parse"))
        ((ok a)
         (do
           (assert (= a.suites (list "s2.asl" "s1.asl")) "suites kept in argument order")
           (assert (= a.paths (list "p")) "path parsed")
           (assert (= a.base (some "HEAD~1")) "base parsed"))))
      (match stray
        ((ok _) (assert false "a bare positional is refused"))
        ((err e)
         (do
           (assert (= e.code 64) "bare positional exits 64")
           (assert (= e.line "(:runner :status :failed :err ERR_USAGE :ev \"s2.asl\")") "bare positional names the argument"))))
      (match bare
        ((ok _) (assert false "--suite without a value is refused"))
        ((err e)
         (do
           (assert (= e.code 2) "--suite without a value exits 2")
           (assert (= e.line "(:runner :status :failed :err ERR_RUNNER :ev \"\")") "--suite without a value is ERR_RUNNER"))))
      (match full
        ((ok _) (assert false "--full is not a runner.py run flag"))
        ((err e) (assert (= e.code 64) "--full exits 64")))
      true))

fn testForceFullPrefixes -> Bool
  (do
    (assert (rm/isForceFull "bin/asl-full") "bin/asl matches bin/asl-full as a prefix")
    (assert (rm/isForceFull "bin/asl-core-legacy") "bin/asl-core matches as a prefix")
    (assert (rm/isForceFull "scripts/audit/foo.py") "scripts/audit/ matches as a prefix")
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
  (match (gr/runCommand! argv cwd env)
    ((err e) (Outcome :code 127 :out "" :errText e))
    ((ok captured) (Outcome :code captured.exit :out captured.stdout :errText captured.stderr)))

fn workRoot! -> String
  (match (realPath ".")
    ((ok p) p)
    ((err e) (do (assert false (str "realPath . fails: " e)) "")))

fn ! timesLedger! -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/aslRunnerMainTimes." (stringFromInt64 (procSelf)) ".asn")

fn envKeyOf kv: String -> String
  (optionOr (listHead (stringSplit kv "=")) "")

fn runAsl! dir: String env: String args: String -> Outcome
  (let [(root (workRoot!))
        (argv (listAppend (list (str root "/bin/asl") "run" (str root "/asl/packages/asl-gates/src/runnerMain.asl"))
                          (filter (fn [(arg String)] -> Bool (not (stringEmpty? arg))) (stringSplit args " "))))
        (extra (filter (fn [(kv String)] -> Bool (not (stringEmpty? kv))) (stringSplit env " ")))
        (overridden (cons "ASL_GATE_TIMES" (map envKeyOf extra)))
        (childEnv (listAppend (filter (fn [(kv String)] -> Bool (not (listContains? overridden (envKeyOf kv)))) (envList)) (cons (str "ASL_GATE_TIMES=" (timesLedger!)) extra)))]
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
  (optionOr (stringSlice (bytesSha256 (stringToBytes (str "ERR_RUNTIME\n" "FAIL " (redFixturePath name) ": " (redFixturePath name) ":4:4: ERR_UNKNOWN_SYMBOL unbound symbol: " missing " (after 0 asserts)"))) 0 16) "")

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
  (match (fileReadString path)
    ((ok s) s)
    ((err e) (do (assert false (str "read " path ": " e)) "")))

fn dropLastLine text: String -> String
  (let [(body (stringTrim text))
        (lines (stringLines body))]
    (stringJoin (listTake lines (- (listLength lines) 1)) "\n"))

fn editedLedger original: String -> String
  (str (dropLastLine original) "\n"
       "  (:suite \"" (redFixturePath "heldRedTest") "\" :cause \"ERR_RUNTIME\" :failedAssertDigest \"" (redDigest "heldRedTest" "heldRedMissing") "\" :since \"R1a2\")\n"
       "  (:suite \"" (redFixturePath "driftRedTest") "\" :cause \"ERR_RUNTIME\" :failedAssertDigest \"0000000000000000\" :since \"R1a2\")\n"
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
      (assert (stringContains? out (str "(:check :id suite :status :failed :err ERR_KNOWN_RED_DRIFT :suite \"" (redFixturePath "driftRedTest") "\" :ev \"ERR_RUNTIME " (redDigest "driftRedTest" "driftRedMissing") " ")) "drift names the new signature")
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
    (assert (rp/replayChooseBaseFixtures!) "synthetic chooseBase fixtures replay through ASL only")
    true)

fn frozenFixtureDir -> String
  "asl/packages/asl-gates/tests/frozenLedgerFixture"

fn frozenFixtureSuiteContent name: String marker: String -> String
  (str "(module asl-gates/tests/frozenLedgerFixture/" name "\n  :x [runTests]\n  :i [])\n\nfn runTests -> Bool\n  (do (assert (ok? (fileWrite \"" marker "\" \"ran\\n\")) \"" name " writes its marker\") true)\n")

fn ledgerWithFixtureRow original: String path: String -> String
  (str (dropLastLine original) "\n"
       "  (:frozen :path \"" path "\" :kind suite :reason \"runnerMainTest fixture\" :since \"2026-10-11\" :by principal))\n")

fn dirtiedCheck marker: String -> String
  (str "(:check :id suite :status :failed :err ERR_TREE_DIRTIED :suite \"snapshot\" :ev \"suites wrote " marker "\")")

fn testFrozenLedger! -> Bool
  (let [(scratch (scratchDir! "aslFrozenLedger"))
        (repo (str scratch "/repo"))
        (_ (sh! scratch (str "/usr/bin/git clone -q --local " (shq (workRoot!)) " repo")))
        (frozenMarker "frozenLedgerCandidateTest.out")
        (liveMarker "liveLedgerCandidateTest.out")
        (frozenPath (str (frozenFixtureDir) "/frozenLedgerCandidateTest.asl"))
        (livePath (str (frozenFixtureDir) "/liveLedgerCandidateTest.asl"))
        (_ (sh! repo (str "mkdir -p " (shq (frozenFixtureDir)))))
        (wFrozen (fileWrite (str repo "/" frozenPath) (frozenFixtureSuiteContent "frozenLedgerCandidateTest" frozenMarker)))
        (wLive (fileWrite (str repo "/" livePath) (frozenFixtureSuiteContent "liveLedgerCandidateTest" liveMarker)))
        (_ (sh! repo "/usr/bin/git add -A"))
        (ledgerPath (str repo "/asl/grammar/frozen.asn"))
        (originalLedger (readText! ledgerPath))
        (wLedger (fileWrite ledgerPath (ledgerWithFixtureRow originalLedger frozenPath)))
        (sweepOut (runAsl! repo "" (str "run --path " (frozenFixtureDir))))
        (explicitOut (runAsl! repo "" (str "run --path " frozenPath)))]
    (do
      (assert (ok? wFrozen) "frozen candidate fixture written")
      (assert (ok? wLive) "live candidate fixture written")
      (assert (ok? wLedger) "frozen ledger gained the fixture row")
      (assert (= sweepOut.code 1) (str "sweep over the fixture dir exits 1 (the one live suite dirties the snapshot): " sweepOut.errText))
      (assert (stringContains? sweepOut.out " :suites 1 ") "sweep over the fixture dir runs exactly one candidate")
      (assert (stringContains? sweepOut.out " :frozen 1 ") "sweep reports the one frozen candidate as skipped, not silently")
      (assert (stringContains? sweepOut.out (dirtiedCheck liveMarker)) "the live candidate is the one that actually ran and wrote its marker")
      (refute (stringContains? sweepOut.out frozenMarker) "the frozen candidate's marker never appears; it did not run")
      (assert (= explicitOut.code 1) (str "naming the frozen candidate on the command line exits 1 (it dirties the snapshot too): " explicitOut.errText))
      (assert (stringContains? explicitOut.out " :suites 1 ") "an explicitly named frozen candidate still runs alone")
      (assert (stringContains? explicitOut.out " :frozen 0 ") "an explicitly named frozen candidate is not counted as skipped")
      (assert (stringContains? explicitOut.out (dirtiedCheck frozenMarker)) "naming the frozen candidate explicitly actually runs it, marker and all")
      (refute (stringContains? explicitOut.out liveMarker) "the live candidate was not even a candidate for this explicit path; its marker never appears")
      (assert (ok? (fileWrite ledgerPath originalLedger)) "frozen ledger restored")
      (assert (ok? (pathRemove scratch)) "scratch clone removed")
      true))

fn gateShContent name: String failed: Int64 -> String
  (str "#!/bin/sh\necho \"(:gate :name " name " :asserts 1 :failed " (stringFromInt64 failed) ")\"\n")

fn writeShSuite! repo: String name: String failed: Int64 -> Bool
  (let [(path (str repo "/" (livePath name)))]
    (and (ok? (dirCreate (str repo "/" (liveDir))))
         (ok? (fileWrite path (gateShContent name failed)))
         (= (command! (list "/bin/chmod" "+x" path) repo (none)).code 0)))

fn liveDir -> String
  "asl/packages/asl-gates/tests/runnerLiveFixture"

fn livePath name: String -> String
  (str (liveDir) "/" name)

fn leftovers! dir: String -> (List String)
  (match (dirList dir) ((ok names) (listSort names)) ((err e) (list (str "unreadable " e))))

; (:m :ref RUNNER-BEHAVIOUR :do "a process in its own session whose argv0 is the given name, detached from our pipes and bounded by alarm 120; the pid it prints is also its process group id")
fn ! orphan! argv0: String -> Int64
  (let [(r (command! (list "/usr/bin/perl" "-e" "use POSIX; my $p = fork; if ($p) { print \"$p\\n\"; exit 0 } POSIX::setsid(); open STDIN, '<', '/dev/null'; open STDOUT, '>', '/dev/null'; open STDERR, '>', '/dev/null'; alarm 120; exec { '/bin/sleep' } $ARGV[0], '120';" argv0) (workRoot!) (none)))]
    (optionOr (stringToInt64 (stringTrim r.out)) -1))

fn ! pidAlive? pid: Int64 -> Bool
  (= (command! (list "/bin/ps" "-p" (stringFromInt64 pid)) (workRoot!) (none)).code 0)

fn ! finishedPid! -> Int64
  (optionOr (stringToInt64 (stringTrim (command! (list "/bin/sh" "-c" "echo $$") (workRoot!) (none)).out)) -1)

fn ! killPid! pid: Int64 -> Unit
  (do (command! (list "/bin/kill" "-9" (stringFromInt64 pid)) (workRoot!) (none)) ())

; (:m :ref RUNNER-BEHAVIOUR :do "run against a lock another process holds: after ASL_GATE_LOCK_WAIT_S the runner reports ERR_BUSY with the holder pid, exits 1 and starts no suite; once the lock is released the same run goes through")
fn ! testRunnerBusy! repo: String scratch: String -> Bool
  (let [(lockPath (str repo "/.git/aslRunner.lock"))
        (log (str scratch "/busy.log"))
        (env (str "ASL_GATE_LOCK_WAIT_S=1 ASL_RUNNER_FIXTURE_LOG=" log))
        (args (str "run --suite " (fixtureDir) "/snapshotProbeATest.sh"))
        (held (fileLock lockPath true))
        (wrote (fileWrite lockPath (stringFromInt64 (procSelf))))
        (busy (runAsl! repo env args))
        (ranWhileBusy (fileExists? log))
        (released (match held ((ok fd) (fdClose fd)) ((err e) (err e))))
        (free (runAsl! repo env args))]
    (do
      (assert (and (ok? held) (ok? wrote)) "the test process holds the runner lock")
      (assert (= busy.code 1) (str "a busy run exits 1: " busy.out))
      (assert (and (stringStartsWith? busy.out "(:runner :status :failed :err ERR_BUSY :ev \"a runner already holds ") (stringContains? busy.out (str "/repo/.git/aslRunner.lock, holder pid " (stringFromInt64 (procSelf)) "\")"))) (str "ERR_BUSY names the lock file and the holder pid: " busy.out))
      (refute ranWhileBusy "no suite started while the lock was held")
      (assert (ok? released) "lock released")
      (assert (stringContains? free.out ":suites 1 ") (str "after release the same run goes through: " free.out))
      (assert (ok? (pathRemove log)) "probe log removed")
      true))

; (:m :ref RUNNER-BEHAVIOUR :do "a failing native build in the snapshot is a runner error: exit 2, ERR_RUNNER with the build's exit code and output, no suite verdicts, and the snapshot and lock are cleaned up")
fn ! testRunnerBuildFail! repo: String scratch: String -> Bool
  (let [(tmp (str scratch "/tmpBuild"))
        (_ (sh! scratch (str "mkdir -p " (shq tmp))))
        (buildSh (str repo "/asl/host/build.sh"))
        (original (readText! buildSh))
        (broken (fileWrite buildSh "#!/bin/sh\necho 'compiling fixture'\necho 'fixture build: seeded failure' >&2\nexit 3\n"))
        (out (runAsl! repo (str "TMPDIR=" tmp) (str "run --suite " (redFixturePath "heldRedTest"))))
        (restored (fileWrite buildSh original))]
    (do
      (assert (ok? broken) "build.sh replaced by a failing one")
      (assert (= out.code 2) (str "a failed build exits 2: " out.out))
      (assert (stringContains? out.out "(:runner :status :failed :err ERR_RUNNER :ev \"native CLI build failed: exit 3: ") (str "the failure names the build exit: " out.out))
      (assert (stringContains? out.out "fixture build: seeded failure") "the build output is in the evidence")
      (refute (stringContains? out.out ":suites ") "no suite verdicts after a failed build")
      (assert (listEmpty? (leftovers! tmp)) (str "no snapshot left behind: " (stringJoin (leftovers! tmp) ",")))
      (assert (ok? restored) "build.sh restored")
      true))

; (:m :ref RUNNER-BEHAVIOUR :do "a registry lists the process groups an earlier runner left: the next run kills a group whose leader is a runner snapshot process and leaves a listed group that is not one, then empties the registry")
fn ! testRunnerReap! repo: String scratch: String -> Bool
  (let [(registry (str repo "/.git/aslRunner.pgids"))
        (mine (orphan! "aslRunnerSnap.reapFixture"))
        (other (orphan! "plainSleepReapFixture"))
        (_ (fileWrite registry (str (stringFromInt64 mine) "\n" (stringFromInt64 other) "\n")))
        (aliveBefore (and (pidAlive? mine) (pidAlive? other)))
        (out (runAsl! repo "" (str "run --suite " (fixtureDir) "/liveOkTest.sh")))
        (mineAlive (pidAlive? mine))
        (otherAlive (pidAlive? other))
        (after (resultOr (fileReadString registry) "gone"))
        (_k1 (killPid! mine))
        (_k2 (killPid! other))]
    (do
      (assert (and (> mine 1) (> other 1) aliveBefore) "both fixture groups are running before the run")
      (assert (stringContains? out.out ":suites 1 ") (str "the run itself went through: " out.out))
      (refute mineAlive "the listed group led by a runner snapshot process is killed")
      (assert otherAlive "a listed group that is not a runner snapshot is left alone")
      (assert (stringEmpty? after) (str "the registry is emptied: " after))
      true))

; (:m :ref RUNNER-BEHAVIOUR :do "temp dirs of dead runners (aslRunnerSnap.<pid>.* and aslKnownRedCapture.<pid>.*) are swept at the start of a run; a live pid, our own pid and names of any other shape stay")
fn ! testRunnerSweep! repo: String scratch: String -> Bool
  (let [(tmp (str scratch "/tmpSweep"))
        (dead (stringFromInt64 (finishedPid!)))
        (live (stringFromInt64 (procSelf)))
        (names (list (str "aslRunnerSnap." dead ".a") (str "aslKnownRedCapture." dead ".b") (str "aslRunnerSnap." live ".c") (str "unrelated." dead ".d") "aslRunnerSnap.notAPid.e"))
        (_ (sh! scratch (str "mkdir -p " (shq tmp) " && cd " (shq tmp) " && mkdir " (stringJoin (map shq names) " "))))
        (out (runAsl! repo (str "TMPDIR=" tmp) (str "run --suite " (fixtureDir) "/liveOkTest.sh")))
        (left (leftovers! tmp))]
    (do
      (assert (stringContains? out.out ":suites 1 ") (str "the run itself went through: " out.out))
      (assert (= left (listSort (list (str "aslRunnerSnap." live ".c") (str "unrelated." dead ".d") "aslRunnerSnap.notAPid.e"))) (str "only the dead runners' dirs are swept: " (stringJoin left ",")))
      true))

; (:m :ref RUNNER-BEHAVIOUR :do "the snapshot is the working tree, not the index: an edited tracked suite runs as edited, a newly staged suite runs, a deleted tracked suite does not")
fn ! testRunnerLiveEdits! repo: String -> Bool
  (let [(made (and (writeShSuite! repo "aLiveTest.sh" 0) (writeShSuite! repo "bLiveTest.sh" 0) (writeShSuite! repo "cLiveTest.sh" 0)))
        (_ (sh! repo "/usr/bin/git add -A"))
        (edited (fileWrite (str repo "/" (livePath "aLiveTest.sh")) (gateShContent "aLiveTest.sh" 1)))
        (deleted (pathRemove (str repo "/" (livePath "bLiveTest.sh"))))
        (added (and (writeShSuite! repo "dLiveTest.sh" 0) (= (command! (list "/usr/bin/git" "add" (livePath "dLiveTest.sh")) repo (none)).code 0)))
        (out (runAsl! repo "" (str "run --path " (liveDir))))]
    (do
      (assert (and made (ok? edited) (ok? deleted) added) "fixture edited after staging: a edited, b deleted, d new and staged")
      (assert (stringContains? out.out " :suites 3 :passedSuites 2 ") (str "a, c and d ran; a failed: " out.out))
      (assert (stringContains? out.out (str "(:check :id suite :status :failed :err ERR_NEW_RED_SUITE :suite \"" (livePath "aLiveTest.sh") "\"")) "the edited suite runs as edited and is a new red")
      (refute (stringContains? out.out "bLiveTest.sh") "the deleted suite is not run")
      (assert (= out.code 1) "a new red suite exits 1")
      true))

fn ! testRunnerBehaviours! -> Bool
  (let [(scratch (makeClone!))
        (repo (str scratch "/repo"))
        (_ (sh! scratch "mkdir -p tmp"))
        (okWritten (writeShSuite! repo "liveOkTest.sh" 0))
        (moved (sh! repo (str "mv " (shq (livePath "liveOkTest.sh")) " " (shq (str (fixtureDir) "/liveOkTest.sh")) " && /usr/bin/git add -A")))]
    (do
      (assert okWritten "ok suite fixture written")
      (assert (testRunnerBusy! repo scratch) "runner busy")
      (assert (testRunnerBuildFail! repo scratch) "runner build failure")
      (assert (testRunnerReap! repo scratch) "runner reaps orphan groups")
      (assert (testRunnerSweep! repo scratch) "runner sweeps stale temps")
      (assert (testRunnerLiveEdits! repo) "runner snapshots the working tree")
      (assert (ok? (pathRemove scratch)) "scratch clone removed")
      true))

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
    (assert (testChooseBaseReplay!) "chooseBase replay")
    (assert (testFrozenLedger!) "frozen ledger")
    (assert (testRunnerBehaviours!) "runner behaviours")
    (assert (ok? (fileReadString (timesLedger!))) "runner children wrote the private gateTimes ledger")
    (assert (ok? (pathRemove (timesLedger!))) "private gateTimes ledger removed")
    true)
