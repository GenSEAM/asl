(module asl-cli/tests/checkTestParityTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref CHECK-TEST-PARITY :do "asl check and asl test of one suite agree in a foreign workspace: an unresolved import, an unknown symbol and an unexported type fail both with the same code and the suite path:line:col; replays the inbox repros workspace-20261030-checkTestImportParity and workspace-20261028-testRunsWhatCheckRejects")
fn ! fixtureRoot! tag: String -> String
  (str "/tmp/aslCheckTestParity_" tag "_" (stringFromInt64 (monotonicNs)))

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
       (and (stringContains? chk.out code) (and (stringContains? tst.out code) (stringContains? tst.out "bridgeTest.asl:"))))

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

fn ! runTests -> Bool
  (do (assert (testUnresolvedImportFailsBoth!) "unresolved import fails check and test")
      (assert (testUnknownSymbolFailsBoth!) "unknown symbol fails check and test")
      (assert (testUnexportedTypeFailsBoth!) "unexported type fails check and test")
      true)
