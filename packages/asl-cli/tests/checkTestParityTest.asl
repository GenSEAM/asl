(module asl-cli/tests/checkTestParityTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref CHECK-TEST-PARITY :do "asl check and asl test of one suite agree in a foreign workspace: a module importing asl-json passes both; an unresolved import, an unknown symbol and an unexported type fail both with the same code and the suite path:line:col; replays the inbox repros workspace-20261030-checkTestImportParity and workspace-20261028-testRunsWhatCheckRejects")
fn ! fixtureRoot! tag: String -> String
  (str (resultOr (realPath "/tmp") "/tmp") "/aslCheckTestParity_" tag "_" (stringFromInt64 (monotonicNs)))

fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

fn ! aslIn! root: String verb: String path: String -> fr/Done
  (fr/runOneLimited (fr/job (list (str (repoRoot!) "/bin/asl") verb path) root (fr/childEnv (list))) (fr/limits 900 64))

fn bridgeSource imports: String body: String -> String
  (str "(module fx/bridge\n  :x [mk]\n  :i [" imports "])\n\nfn mk -> Int64\n  " body "\n")

fn suiteSource extra: String -> String
  (str "(module fx/bridgeTest\n  :x [runTests]\n  :i [(fx/bridge :a b)])\n\n" extra "fn ! runTests -> Bool\n  (do (assert (= (b/mk) 3) \"mk\") true)\n")

fn ! stage! root: String bridge: String suite: String -> Bool
  (and (ok? (dirCreate root))
       (and (ok? (dirCreate (str root "/kernel")))
            (and (ok? (fileWrite (str root "/.asl.config.asn") "(:asl-config :workspace \"fx\")\n"))
                 (and (ok? (fileWrite (str root "/kernel/bridge.asl") bridge))
                      (ok? (fileWrite (str root "/kernel/bridgeTest.asl") suite))))))

fn bothFail code: String chk: fr/Done tst: fr/Done -> Bool
  (and (and (!= chk.exit 0) (!= tst.exit 0))
       (and (stringContains? chk.out code) (and (stringContains? tst.out code) (and (stringContains? chk.out "kernel/bridgeTest.asl:") (stringContains? tst.out "kernel/bridgeTest.asl:")))))

fn ! parityOf! tag: String bridge: String suite: String -> (Pair fr/Done fr/Done)
  (let [(root (fixtureRoot! tag))
        (staged (stage! root bridge suite))
        (chk (aslIn! root "check" "kernel/bridgeTest.asl"))
        (tst (aslIn! root "test" "kernel/bridgeTest.asl"))
        (_ (pathRemove root))]
    (if staged (pair chk tst) (pair (fr/Done :idx 0 :exit 99 :out "stage failed" :ms 0 :verdict "") (fr/Done :idx 0 :exit 99 :out "stage failed" :ms 0 :verdict ""))))

fn ! testUnresolvedImportFailsBoth! -> Bool
  (let [(r (parityOf! "missing" (bridgeSource "(fx/missing :a m)" "3") (suiteSource "")))]
    (do (assert (bothFail "ERR_UNRESOLVED_IMPORT" (pairFirst r) (pairSecond r)) (str "an unresolved import fails both with the code: " (pairFirst r).out " | " (pairSecond r).out))
        true))

fn ! testUnknownSymbolFailsBoth! -> Bool
  (let [(r (parityOf! "symbol" (bridgeSource "" "3") (suiteSource "fn useIt -> Int64\n  (noSuchFunctionAnywhere 1)\n\n")))]
    (do (assert (bothFail "ERR_UNKNOWN_SYMBOL" (pairFirst r) (pairSecond r)) (str "an unknown symbol fails both with the code: " (pairFirst r).out " | " (pairSecond r).out))
        true))

fn ! testUnexportedTypeFailsBoth! -> Bool
  (let [(r (parityOf! "type" "(module fx/bridge\n  :x [mk]\n  :i [])\n\n(schema Box (:f v Int))\n\nfn mk -> Int64\n  3\n" (suiteSource "fn useBox b: b/Box -> Int64\n  b.v\n\n")))]
    (do (assert (bothFail "ERR_NOT_EXPORTED" (pairFirst r) (pairSecond r)) (str "a type the module does not export fails both with the code: " (pairFirst r).out " | " (pairSecond r).out))
        true))

fn ! testAslPackageImportPassesBoth! -> Bool
  (let [(r (parityOf! "pkg" (bridgeSource "(asl-json/json :a j)" "3") (suiteSource "")))
        (chk (pairFirst r))
        (tst (pairSecond r))]
    (do (assert (= chk.exit 0) (str "asl check resolves an asl-json import from a foreign workspace: " chk.out))
        (assert (= tst.exit 0) (str "asl test resolves it too: " tst.out))
        (assert (stringContains? tst.out "1 assertion(s) executed") "the suite ran its assertion")
        true))

fn ! testCheckNamesTheCallersPath -> Bool
  (let [(r (parityOf! "path" (bridgeSource "(fx/missing :a m)" "3") (suiteSource "")))
        (chk (pairFirst r))]
    (do (assert (stringContains? chk.out "kernel/bridgeTest.asl") (str "check names the path the caller gave: " chk.out))
        (assert (not (stringContains? chk.out "outsidePkg")) (str "no staged path leaks into check output: " chk.out))
        true))

; (:m :ref CHECK-FOREIGN-LOWS :do "routes of asl check from a foreign workspace: an in-root file is never staged; a directory argument is refused (ERR_NO_FILE) not staged; a mixed list checks the outside file in its staged mirror and the in-root file as ever; an imported staged file is named by its package path, absolute; a deleted module does not survive in the mirror between two runs")
fn ! aslArgs! root: String verb: String args: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (cons (str (repoRoot!) "/bin/asl") (cons verb args)) root (fr/childEnv (list))) (fr/limits 900 64))

fn ! inRootFile! -> String
  (str (repoRoot!) "/asl/packages/asl-cli/src/check.asl")

fn leaks? out: String -> Bool
  (or (stringContains? out "outsidePkg") (stringContains? out "nativeTest/outside"))

fn ! testInRootArgNotStaged! -> Bool
  (let [(root (fixtureRoot! "inroot"))
        (staged (stage! root (bridgeSource "" "3") (suiteSource "")))
        (chk (aslArgs! root "check" (list (inRootFile!))))
        (_ (pathRemove root))]
    (do (assert (and staged (= chk.exit 0)) (str "an in-root file checks green from a foreign cwd: " chk.out))
        (assert (stringContains? chk.out (inRootFile!)) (str "it is named by the path given: " chk.out))
        (assert (not (leaks? chk.out)) (str "it was not staged: " chk.out))
        true))

fn ! testDirectoryArgRefusedNotStaged! -> Bool
  (let [(root (fixtureRoot! "dir"))
        (staged (stage! root (bridgeSource "" "3") (suiteSource "")))
        (chk (aslArgs! root "check" (list "kernel")))
        (_ (pathRemove root))]
    (do (assert (and staged (!= chk.exit 0)) (str "a directory argument fails: " chk.out))
        (assert (stringContains? chk.out "ERR_NO_FILE") (str "it is refused as no file, not checked: " chk.out))
        (assert (not (leaks? chk.out)) (str "it was not staged: " chk.out))
        true))

fn ! testMixedListChecksBoth! -> Bool
  (let [(root (fixtureRoot! "mixed"))
        (staged (stage! root (bridgeSource "" "(noSuchFnHere 3)") (suiteSource "")))
        (chk (aslArgs! root "check" (list "kernel/bridgeTest.asl" (inRootFile!))))
        (_ (pathRemove root))]
    (do (assert (and staged (!= chk.exit 0)) (str "the outside file's error fails the list: " chk.out))
        (assert (stringContains? chk.out "check failed: kernel/bridgeTest.asl") (str "the outside file is named as given: " chk.out))
        (assert (stringContains? chk.out (str "ok " (inRootFile!))) (str "the in-root file still checks: " chk.out))
        (assert (not (leaks? chk.out)) (str "no staged path leaks: " chk.out))
        true))

fn ! testImportedStagedPathNormalised! -> Bool
  (let [(root (fixtureRoot! "imported"))
        (staged (stage! root (bridgeSource "" "(noSuchFnHere 3)") (suiteSource "")))
        (chk (aslArgs! root "check" (list "kernel/bridgeTest.asl")))
        (_ (pathRemove root))]
    (do (assert (and staged (!= chk.exit 0)) (str "an error in the imported module fails the check: " chk.out))
        (assert (stringContains? chk.out (str root "/kernel/bridge.asl:")) (str "the imported file is named by its package path: " chk.out))
        (assert (not (leaks? chk.out)) (str "no staged path leaks: " chk.out))
        true))

fn ! testNoStaleMirrorBetweenRuns! -> Bool
  (let [(root (fixtureRoot! "stale"))
        (staged (stage! root (bridgeSource "" "3") (suiteSource "")))
        (first (aslArgs! root "check" (list "kernel/bridgeTest.asl")))
        (removed (pathRemove (str root "/kernel/bridge.asl")))
        (second (aslArgs! root "check" (list "kernel/bridgeTest.asl")))
        (_ (pathRemove root))]
    (do (assert (and staged (= first.exit 0)) (str "the first check is green: " first.out))
        (assert (ok? removed) "the imported module was deleted")
        (assert (and (!= second.exit 0) (stringContains? second.out "ERR_UNRESOLVED_IMPORT")) (str "the deleted module is gone from the mirror, not served stale: " second.out))
        true))

fn ! runTests -> Bool
  (do (assert (testAslPackageImportPassesBoth!) "asl-json import passes check and test")
      (assert (testCheckNamesTheCallersPath) "check output names the caller path, not the staged mirror")
      (assert (testUnresolvedImportFailsBoth!) "unresolved import fails check and test")
      (assert (testUnknownSymbolFailsBoth!) "unknown symbol fails check and test")
      (assert (testUnexportedTypeFailsBoth!) "unexported type fails check and test")
      (assert (testInRootArgNotStaged!) "an in-root file is not staged")
      (assert (testDirectoryArgRefusedNotStaged!) "a directory argument is refused, not staged")
      (assert (testMixedListChecksBoth!) "a mixed list checks the outside file staged and the in-root file as ever")
      (assert (testImportedStagedPathNormalised!) "an imported staged file is named by its package path")
      (assert (testNoStaleMirrorBetweenRuns!) "a deleted module does not survive in the mirror between runs")
      true)
