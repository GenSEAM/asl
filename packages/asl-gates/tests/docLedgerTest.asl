(module asl-gates/tests/docLedgerTest
  :x [testLoadValid! testMalformedRows! testLoadMissingIsEmpty! testFindBySymbolHitMiss! testFindByFile! testResolveRows! testRoundTripWithExtractor! testMutantGuards! testExportGaps! testCoverageRatchet! testPackageGaps! testPackageRatchet! runTests]
  :i [(asl-gates/docLedger :a dl) (asl-gates/docExtract :a dx)])

fn fixtureDir -> String
  "asl/packages/asl-gates/tests/fixtures/docLedger"

fn fixture name: String -> String
  (str (fixtureDir) "/" name)

fn symbolsOf rows: (List dl/DocRow) -> (List String)
  (map (fn [(r dl/DocRow)] -> String r.symbol) rows)

fn textsOf rows: (List dl/DocRow) -> (List String)
  (map (fn [(r dl/DocRow)] -> String r.text) rows)

fn testLoadValid! -> Bool
  (match (dl/loadLedger! (fixture "valid.asn"))
    ((err e) (do (assert false (str "loadLedger! ok: " e)) false))
    ((ok rows)
      (do
        (assert (= (symbolsOf rows) (list "fx/thing.asl#" "fx/thing.asl#addOne")) "both rows loaded in source order")
        (assert (= (textsOf rows) (list "A tiny fixture module" "Adds one to a")) "row text recovered exactly")
        true)))

fn mustErr! path: String why: String -> Bool
  (match (dl/loadLedger! (fixture path))
    ((err _) true)
    ((ok _) (do (assert false why) false)))

fn testMalformedRows! -> Bool
  (do
    (assert (mustErr! "malformedKey.asn" "unknown key is a typed error") "unknown key rejected")
    (assert (mustErr! "missingText.asn" "missing :text is a typed error") "missing text rejected")
    (assert (mustErr! "wrongHead.asn" "non-:doc head is a typed error") "wrong head rejected")
    true)

fn testLoadMissingIsEmpty! -> Bool
  (match (dl/loadLedger! (fixture "noSuchLedger.asn"))
    ((err e) (do (assert false (str "loadLedger! ok on a missing file: " e)) false))
    ((ok rows) (do (assert (= (listLength rows) 0) "a ledger that was never written reads as empty, not an error") true)))

fn ! sandboxDir! -> String
  (stringTrim (processRun "mktemp -d").stdout)

fn assertHitFound! found: (Option dl/DocRow) -> Bool
  (match found
    ((none) (do (assert false "addOne should be found") false))
    ((some row) (do (assert (= row.text "Adds one to a") "hit returns the exact ledgered text") true)))

fn ! assertHit! dir: String -> Bool
  (match (dl/findBySymbol! dir "asl/packages/fxpkg/src/thing.asl#addOne")
    ((err e) (assert false (str "findBySymbol! ok on a hit: " e)))
    ((ok found) (assertHitFound! found)))

fn assertMissFound! found: (Option dl/DocRow) -> Bool
  (match found
    ((none) true)
    ((some _) (do (assert false "an unledgered symbol must miss, not hit") false)))

fn ! assertMiss! dir: String -> Bool
  (match (dl/findBySymbol! dir "asl/packages/fxpkg/src/thing.asl#noSuchFn")
    ((err e) (assert false (str "findBySymbol! ok on a miss: " e)))
    ((ok found) (assertMissFound! found)))

fn ! testFindBySymbolHitMiss! -> Bool
  (let [(dir (sandboxDir!))
        (made1 (processRun (str "mkdir -p '" dir "/asl/packages/fxpkg/src'")))
        (made2 (ok? (fileWrite (str dir "/asl/packages/fxpkg/src/thing.asl") "(module asl-replay/fx/thing :x [addOne] :i [])\n\nfn addOne a: Int64 -> Int64\n  (+ a 1)\n")))
        (made3 (ok? (fileWrite (str dir "/asl/packages/fxpkg/doc.asn") "(:doc :symbol \"asl/packages/fxpkg/src/thing.asl#addOne\" :text \"Adds one to a\")\n")))]
    (do
      (assert (= made1.exitCode 0) "sandbox src dir made")
      (assert made2 "sandbox source written")
      (assert made3 "sandbox ledger written")
      (assert (assertHit! dir) "hit case")
      (assert (assertMiss! dir) "miss case")
      (assert (= (processRun (str "rm -rf '" dir "'")).exitCode 0) "sandbox removed")
      true))

fn ! testFindByFile! -> Bool
  (let [(dir (sandboxDir!))
        (made1 (processRun (str "mkdir -p '" dir "/asl/packages/fxpkg/src'")))
        (ledger (str "(:doc :symbol \"asl/packages/fxpkg/src/a.asl#\" :text \"doc for a\")\n"
                     "(:doc :symbol \"asl/packages/fxpkg/src/b.asl#\" :text \"doc for b\")\n"))
        (made2 (ok? (fileWrite (str dir "/asl/packages/fxpkg/doc.asn") ledger)))]
    (do
      (assert (= made1.exitCode 0) "sandbox src dir made")
      (assert made2 "shared package ledger written")
      (assert (assertFileRows! dir) "findByFile! case")
      (assert (= (processRun (str "rm -rf '" dir "'")).exitCode 0) "sandbox removed")
      true))

fn assertFileRowsOk! rows: (List dl/DocRow) -> Bool
  (do
    (assert (= (listLength rows) 1) "only a.asl's own row is returned, not b.asl's")
    (assert (= (symbolsOf rows) (list "asl/packages/fxpkg/src/a.asl#")) "the returned row is a's module doc")
    true)

fn ! assertFileRows! dir: String -> Bool
  (match (dl/findByFile! dir "asl/packages/fxpkg/src/a.asl")
    ((err e) (assert false (str "findByFile! ok: " e)))
    ((ok rows) (assertFileRowsOk! rows)))

fn assertUnresolvedRows! unresolved: (List String) -> Bool
  (do
    (assert (= (listLength unresolved) 2) "exactly the two stale rows are flagged")
    (assert (listContains? unresolved "asl/packages/fxpkg/src/thing.asl#removedFn") "a removed fn is unresolved")
    (assert (listContains? unresolved "asl/packages/fxpkg/src/thing.asl#Thing.removedField") "a removed field is unresolved")
    (assert (not (listContains? unresolved "asl/packages/fxpkg/src/thing.asl#")) "the module doc resolves")
    (assert (not (listContains? unresolved "asl/packages/fxpkg/src/thing.asl#addOne")) "the fn doc resolves")
    (assert (not (listContains? unresolved "asl/packages/fxpkg/src/thing.asl#Thing.id")) "the field doc resolves")
    (assert (not (listContains? unresolved "asl/packages/fxpkg/src/thing.asl#L7")) "a line-anchored comment always resolves")
    true)

fn ! assertCheckLedger! dir: String -> Bool
  (match (dl/checkLedger! dir "asl/packages/fxpkg/doc.asn")
    ((err e) (assert false (str "checkLedger! ok: " e)))
    ((ok unresolved) (assertUnresolvedRows! unresolved)))

fn ! testResolveRows! -> Bool
  (let [(dir (sandboxDir!))
        (made1 (processRun (str "mkdir -p '" dir "/asl/packages/fxpkg/src'")))
        (src (str "(module asl-replay/fx/thing :x [addOne Thing] :i [])\n\n"
                  "(schema Thing (:f id Int64) (:f label String))\n\n"
                  "fn addOne a: Int64 -> Int64\n  (+ a 1)\n"))
        (made2 (ok? (fileWrite (str dir "/asl/packages/fxpkg/src/thing.asl") src)))
        (ledger (str "(:doc :symbol \"asl/packages/fxpkg/src/thing.asl#\" :text \"module doc\")\n"
                     "(:doc :symbol \"asl/packages/fxpkg/src/thing.asl#addOne\" :text \"fn doc\")\n"
                     "(:doc :symbol \"asl/packages/fxpkg/src/thing.asl#Thing.id\" :text \"field doc\")\n"
                     "(:doc :symbol \"asl/packages/fxpkg/src/thing.asl#removedFn\" :text \"stale fn\")\n"
                     "(:doc :symbol \"asl/packages/fxpkg/src/thing.asl#Thing.removedField\" :text \"stale field\")\n"
                     "(:doc :symbol \"asl/packages/fxpkg/src/thing.asl#L7\" :text \"a trailing comment\")\n"))
        (made3 (ok? (fileWrite (str dir "/asl/packages/fxpkg/doc.asn") ledger)))]
    (do
      (assert (= made1.exitCode 0) "sandbox src dir made")
      (assert made2 "sandbox source written")
      (assert made3 "sandbox ledger written")
      (assert (assertCheckLedger! dir) "checkLedger! case")
      (assert (= (processRun (str "rm -rf '" dir "'")).exitCode 0) "sandbox removed")
      true))

fn assertRecoveredFound! found: (Option dl/DocRow) -> Bool
  (match found
    ((none) (do (assert false "the extracted doc must be recoverable via (:doc) after --apply") false))
    ((some row) (do (assert (= row.text "Adds one to a") "the ledgered text matches the original :d exactly") true)))

fn ! assertRecovered! dir: String -> Bool
  (match (dl/findBySymbol! dir "asl/packages/fxpkg/src/thing.asl#addOne")
    ((err e) (assert false (str "findBySymbol! ok after apply: " e)))
    ((ok found) (assertRecoveredFound! found)))

fn ! assertApplied! dir: String r: dx/ExtractResult -> Bool
  (match (dx/applyExtract! dir r)
    ((err e) (assert false (str "applyExtract! ok: " e)))
    ((ok _) (assertRecovered! dir)))

fn ! assertExtractedAndApplied! dir: String -> Bool
  (match (dx/extractFile! dir "asl/packages/fxpkg/src/thing.asl")
    ((err e) (assert false (str "extractFile! ok: " e)))
    ((ok r) (assertApplied! dir r)))

fn ! testRoundTripWithExtractor! -> Bool
  (let [(dir (sandboxDir!))
        (made1 (processRun (str "mkdir -p '" dir "/asl/packages/fxpkg/src'")))
        (src (str "(module asl-replay/fx/thing :x [addOne] :i [])\n\n"
                  "fn addOne a: Int64 -> Int64\n  :d \"Adds one to a\"\n  (+ a 1)\n"))
        (made2 (ok? (fileWrite (str dir "/asl/packages/fxpkg/src/thing.asl") src)))]
    (do
      (assert (= made1.exitCode 0) "sandbox src dir made")
      (assert made2 "sandbox source written")
      (assert (assertExtractedAndApplied! dir) "extract+apply+recover case")
      (assert (= (processRun (str "rm -rf '" dir "'")).exitCode 0) "sandbox removed")
      true))

; (:m :ref CHK-PRINT-TEMP-LEAK :do "a dot file named like the print-host-valid temp (.asl_chk_print_pPID_NS_0.asl) beside a source is not listed by aslFilesUnder!, so its exports are never counted as missing doc rows; the plain source beside it still is")
fn ! testDotFilesSkipped! -> Bool
  (let [(dir (sandboxDir!))
        (a (fileWrite (str dir "/a.asl") "(module m/a\n  :x [f])\nfn f -> Bool\n  true\n"))
        (b (fileWrite (str dir "/.asl_chk_print_p1_2_0.asl") "(module m/a\n  :x [f])\nfn f -> Bool\n  true\n"))
        (listed (dl/aslFilesUnder! dir ""))
        (cleaned (pathRemove dir))]
    (do
      (assert (and (ok? a) (ok? b)) "the sandbox files are written")
      (assert (= (resultOr listed (list "error")) (list "/a.asl")) (str "only the plain source is listed: " (match listed ((ok l) (stringJoin l " ")) ((err e) e))))
      (assert (ok? cleaned) "the sandbox is removed")
      true))

fn testMutantGuards! -> Bool
  (do
    (assert (= (dl/renderText "a\\nb") "a\nb") "mutant guard: renderText decodes the escaped newline a reader stored verbatim")
    (assert (mustErr! "missingText.asn" "mutant guard: a :symbol-only row is still rejected, not defaulted to empty text") "missing :text stays an error")
    true)

fn testExportGaps! -> Bool
  (let [(rows (list (dl/DocRow :symbol "asl/tools/x.asl#kept" :text "documented")))
        (gaps (dl/exportGaps rows "asl/tools/x.asl" (list "kept" "missing!")))
        (parsed (dl/exportsOf "(module ws/x\n  :x [alpha beta!]\n  :i [])\n\nfn alpha -> Int64\n  1\n\nfn beta! -> Int64\n  2\n"))
        (broken (dl/exportsOf "(module ws/x :x [a]"))]
    (do (assert (= gaps (list "asl/tools/x.asl#missing!")) (str "only the export without a row is a gap: " (stringJoin gaps " ")))
        (assert (= parsed (list "alpha" "beta!")) (str "exports come from the module :x list: " (stringJoin parsed " ")))
        (assert (= broken (list "!parse")) (str "a file that does not parse is a gap, not skipped: " (stringJoin broken " ")))
        true))

fn baselinePath -> String
  "asl/packages/asl-gates/tests/docCoverageBaseline.asn"

fn ! baseline! -> (List String)
  (map (fn [(l String)] -> String (stringReplace (stringReplace l "(:gap \"" "") "\")" ""))
       (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:gap \"")) (stringLines (resultOr (fileReadString (baselinePath)) ""))))

fn ! docAreas! -> (List String)
  (map (fn [(n String)] -> String (stringReplace n ".asn" ""))
       (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asn")) (listSort (resultOr (dirList "asl/doc") (list)))))

; (:m :ref DOCLEDGER-TOOLS-COVERAGE :do "every export under asl/<area> has a row in asl/doc/<area>.asn, one area per asl/doc/*.asn, except the gaps already listed in the ratchet baseline; a baseline row that is no longer a gap is red (DOCLEDGER-STALE-RED), so the list shrinks by regeneration")
fn ! testCoverageRatchet! -> Bool
  (let [(known (baseline!))
        (areas (docAreas!))
        (results (map (fn [(a String)] -> (Pair String (Result (List String) String)) (pair a (dl/coverageGaps! "." a))) areas))
        (failed (filter (fn [(r (Pair String (Result (List String) String)))] -> Bool (not (ok? (pairSecond r)))) results))
        (gaps (fold (fn [(acc (List String)) (r (Pair String (Result (List String) String)))] -> (List String) (listAppend acc (resultOr (pairSecond r) (list)))) (list) results))
        (fresh (filter (fn [(g String)] -> Bool (not (listContains? known g))) gaps))
        (stale (dl/staleGaps known gaps))]
    (do (assert (listContains? areas "tools") (str "asl/doc/tools.asn is one of the areas: " (stringJoin areas " ")))
        (assert (> (listLength known) 0) (str "the baseline loads from " (baselinePath)))
        (assert (listEmpty? failed) (str "every area scans: " (stringJoin (map (fn [(r (Pair String (Result (List String) String)))] -> String (pairFirst r)) failed) " ")))
        (assert (listEmpty? fresh) (str "every export has a doc row in its asl/doc home or is in the baseline; missing: " (stringJoin (listTake fresh 10) " ")))
        (assert (listEmpty? stale) (str "every area baseline row is still a gap, else regenerate docCoverageBaseline.asn with asl run asl/packages/asl-gates/src/docLedger.asl --gaps " (stringJoin areas " ") "; covered or gone: " (stringJoin (listTake stale 10) " ")))
        true))

fn packageBaselinePath -> String
  "asl/packages/asl-gates/tests/docPackageBaseline.asn"

fn ! gapSet! path: String -> (Map String Bool)
  (fold (fn [(m (Map String Bool)) (l String)] -> (Map String Bool) (if (stringStartsWith? l "(:gap \"") (mapSet m (stringReplace (stringReplace l "(:gap \"" "") "\")" "") true) m))
        (mapEmpty) (stringLines (resultOr (fileReadString path) "")))

fn ! testPackageGaps! -> Bool
  (let [(dir (sandboxDir!))
        (made (and (ok? (dirCreate (str dir "/asl/packages/fxpkg/src"))) (and (ok? (dirCreate (str dir "/asl/packages/fxpkg/tests"))) (ok? (dirCreate (str dir "/asl/packages/nodoc/src"))))))
        (doc (ok? (fileWrite (str dir "/asl/packages/fxpkg/doc.asn") "(:doc :symbol \"asl/packages/fxpkg/src/thing.asl#kept\" :text \"documented\")\n")))
        (src (ok? (fileWrite (str dir "/asl/packages/fxpkg/src/thing.asl") "(module fxpkg/thing\n  :x [kept fresh]\n  :i [])\n\nfn kept -> Int64\n  1\n\nfn fresh -> Int64\n  2\n")))
        (tst (ok? (fileWrite (str dir "/asl/packages/fxpkg/tests/thingTest.asl") "(module fxpkg/tests/thingTest\n  :x [runTests]\n  :i [])\n\nfn runTests -> Bool\n  true\n")))
        (bare (ok? (fileWrite (str dir "/asl/packages/nodoc/src/x.asl") "(module nodoc/x\n  :x [y]\n  :i [])\n\nfn y -> Int64\n  1\n")))
        (gaps (resultOr (dl/packageGaps! dir "fxpkg") (list "!scan")))
        (pkgs (dl/docPackages! dir))
        (stale (dl/staleGaps (list "asl/packages/fxpkg/src/thing.asl#kept" "asl/packages/fxpkg/src/thing.asl#fresh" "asl/packages/fxpkg/src/thing.asl#removed") gaps))
        (gone (ok? (pathRemove dir)))]
    (do (assert (and made (and doc (and src (and tst bare)))) "package fixture written")
        (assert (= gaps (list "asl/packages/fxpkg/src/thing.asl#fresh" "asl/packages/fxpkg/tests/thingTest.asl#runTests")) (str "a package export without a row in its doc.asn is a gap, src and tests alike: " (stringJoin gaps " ")))
        (assert (= stale (list "asl/packages/fxpkg/src/thing.asl#kept" "asl/packages/fxpkg/src/thing.asl#removed")) (str "a baseline row whose export has a doc row or is gone is stale and named: " (stringJoin stale " ")))
        (assert (= pkgs (list "fxpkg")) (str "only packages with a doc.asn are scanned: " (stringJoin pkgs " ")))
        (assert gone "package fixture removed")
        true))

; (:m :ref DOCLEDGER-SCOPE-GAP :do "every export under a package with a doc.asn has a row there, except the gaps listed in docPackageBaseline.asn on its date; a baseline row that is no longer a gap is red (DOCLEDGER-STALE-RED), so the list shrinks by regeneration")
fn ! testPackageRatchet! -> Bool
  (let [(known (gapSet! (packageBaselinePath)))
        (pkgs (dl/docPackages! "."))
        (results (map (fn [(p String)] -> (Pair String (Result (List String) String)) (pair p (dl/packageGaps! "." p))) pkgs))
        (failed (filter (fn [(r (Pair String (Result (List String) String)))] -> Bool (not (ok? (pairSecond r)))) results))
        (gaps (fold (fn [(acc (List String)) (r (Pair String (Result (List String) String)))] -> (List String) (listAppend acc (resultOr (pairSecond r) (list)))) (list) results))
        (fresh (filter (fn [(g String)] -> Bool (not (mapHas? known g))) gaps))
        (stale (dl/staleGaps (mapKeys known) gaps))]
    (do (assert (listContains? pkgs "asl-gates") (str "asl-gates has a doc.asn: " (stringJoin pkgs " ")))
        (assert (> (listLength (mapKeys known)) 0) (str "the package baseline loads from " (packageBaselinePath)))
        (assert (listEmpty? failed) (str "every package scans: " (stringJoin (map (fn [(r (Pair String (Result (List String) String)))] -> String (pairFirst r)) failed) " ")))
        (assert (listEmpty? fresh) (str "every package export has a row in its doc.asn or is in the package baseline; missing: " (stringJoin (listTake fresh 10) " ")))
        (assert (listEmpty? stale) (str "every package baseline row is still a gap, else regenerate docPackageBaseline.asn with asl run asl/packages/asl-gates/src/docLedger.asl --gaps packages; covered or gone: " (stringJoin (listTake stale 10) " ")))
        true))

fn ! runTests -> Bool
  (do
    (assert (testLoadValid!) "testLoadValid!")
    (assert (testMalformedRows!) "testMalformedRows!")
    (assert (testLoadMissingIsEmpty!) "testLoadMissingIsEmpty!")
    (assert (testFindBySymbolHitMiss!) "testFindBySymbolHitMiss!")
    (assert (testFindByFile!) "testFindByFile!")
    (assert (testResolveRows!) "testResolveRows!")
    (assert (testRoundTripWithExtractor!) "testRoundTripWithExtractor!")
    (assert (testMutantGuards!) "testMutantGuards!")
    (assert (testDotFilesSkipped!) "a temp dot file is not a source")
    (assert (testExportGaps!) "testExportGaps!")
    (assert (testCoverageRatchet!) "testCoverageRatchet!")
    (assert (testPackageGaps!) "testPackageGaps!")
    (assert (testPackageRatchet!) "testPackageRatchet!")
    true)
