(module aslIntel/tests/preloadRankingTest
  :x [testPreloadRankingSourceIntegrity! testPreloadGrammarRegistration! testPreloadSyntaxAndDelimiters! testPreloadBm25Computation! runTests RunTests!]
  :i [])

fn testPreloadRankingSourceIntegrity! -> Bool
  (let [(pRes (fileRead "asl/packages/asl-intel/src/preload.asl"))]
    (mt pRes
      ((err e) (assert false (str "Failed to read asl/packages/asl-intel/src/preload.asl: " e)))
      ((ok src)
        (do
          (assert (stringContains? src "fn scoreStubBm25") "preload.asl defines scoreStubBm25")
          (assert (stringContains? src "fn computeStubSimHash") "preload.asl defines computeStubSimHash")
          (assert (stringContains? src "fn areStubsNearDuplicates?") "preload.asl defines areStubsNearDuplicates?")
          (assert (stringContains? src "fn dedupStubs") "preload.asl defines dedupStubs")
          (assert (stringContains? src "fn rankStubsByRelevance") "preload.asl defines rankStubsByRelevance")
          (assert (stringContains? src "fn updateStubBm25Incremental") "preload.asl defines updateStubBm25Incremental")
          (assert (stringContains? src "fn scoreStubBm25Enhanced") "preload.asl defines scoreStubBm25Enhanced")
          (refute (stringContains? src "Mach-O") "Zero Mach-O binary emission in intel preload")
          (refute (stringContains? src "ELF64") "Zero ELF64 binary emission in intel preload"))))
    true)

fn testPreloadGrammarRegistration! -> Bool
  (let [(gRes (fileRead "asl/packages/asl-intel/manifest.asn"))]
    (mt gRes
      ((err ge) (assert false (str "Failed to read asl/packages/asl-intel/manifest.asn: " ge)))
      ((ok gSrc)
        (do
          (assert (stringContains? gSrc "aslIntel/preload") "manifest registers aslIntel/preload module")
          (refute (stringContains? gSrc "asl_intel") "Strict camelCase in manifest registration"))))
    true)

fn testPreloadSyntaxAndDelimiters! -> Bool
  (let [(chkCmd "./bin/asl check asl/packages/asl-intel/src/preload.asl")
        (chkRes (processRun chkCmd))]
    (assert (= chkRes.exitCode 0) "asl check exits 0 on asl/packages/asl-intel/src/preload.asl")
    (assert (stringContains? chkRes.stdout "(:check :id balance :status :passed)") "preload.asl delimiter balance verified cleanly")
    (refute (stringContains? chkRes.stdout "Syntax error") "Zero syntax errors in preload.asl")
    (refute (stringContains? chkRes.stdout "unbalanced") "Zero unbalanced delimiters in preload.asl")
    true)

fn testPreloadBm25Computation! -> Bool
  (let [(evalMatchCmd "./bin/asl eval '(let [(sym \"app/processOrder\") (sig \"(fn processOrder [id] -> Order)\") (doc \"Executes billing\") (t \"processOrder\") (s1 (if (stringContains? sym t) 100 0)) (s2 (if (stringContains? sig t) 50 0)) (s3 (if (stringContains? doc t) 25 0))] (+ s1 (+ s2 s3)))'")
        (evalMatchRes (processRun evalMatchCmd))
        (evalDisjointCmd "./bin/asl eval '(let [(sym \"app/unrelatedQuery\") (t \"processOrder\")] (if (stringContains? sym t) 100 0))'")
        (evalDisjointRes (processRun evalDisjointCmd))]
    (assert (= evalMatchRes.exitCode 0) "asl eval exits 0 on matching stub BM25 computation")
    (assert (stringContains? evalMatchRes.stdout "150") "Matching stub computes 150 BM25 score")
    (refute (stringStartsWith? evalMatchRes.stdout "0") "Matching stub score must not start with zero")
    (assert (= evalDisjointRes.exitCode 0) "asl eval exits 0 on disjoint stub BM25 computation")
    (assert (stringContains? evalDisjointRes.stdout "0") "Disjoint stub computes 0 BM25 score")
    (refute (stringContains? evalDisjointRes.stdout "100") "Disjoint stub must not score 100")
    true)

fn testIncrementalBm25Update! -> Bool
  (let [(evalIncCmd "./bin/asl eval '(let [(s0 (list 0 0 1)) (d1 50) (s1 (list (+ (listGet s0 0) 1) (+ (listGet s0 1) d1) (/ (+ (listGet s0 1) d1) (+ (listGet s0 0) 1))))] s1)'")
        (evalIncRes (processRun evalIncCmd))]
    (assert (= evalIncRes.exitCode 0) "asl eval exits 0 on incremental BM25 stats calculation")
    (assert (stringContains? evalIncRes.stdout "50") "Incremental stats computes 50 average doc length")
    (refute (stringContains? evalIncRes.stdout "nil") "Stats computation must refute nil")
    true)

fn ! runTests -> Bool
  (do
    (assert (testPreloadRankingSourceIntegrity!) "Preload ranking source integrity passed")
    (assert (testPreloadGrammarRegistration!) "Preload grammar registration passed")
    (assert (testPreloadSyntaxAndDelimiters!) "Preload syntax and delimiters passed")
    (assert (testPreloadBm25Computation!) "Preload BM25 computation passed")
    (assert (testIncrementalBm25Update!) "Incremental BM25 update passed")
    true)

fn RunTests! -> Bool
  (runTests)
