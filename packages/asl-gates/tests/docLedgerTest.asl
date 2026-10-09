(module asl-gates/tests/docLedgerTest
  :x [testLoadValid! testMalformedRows! testLoadMissingIsEmpty! testFindBySymbolHitMiss! testFindByFile! testResolveRows! testRoundTripWithExtractor! testMutantGuards! runTests]
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
  (mt (dl/loadLedger! (fixture "valid.asn"))
    ((err e) (do (assert false (str "loadLedger! ok: " e)) false))
    ((ok rows)
      (do
        (assert (= (symbolsOf rows) (list "fx/thing.asl#" "fx/thing.asl#addOne")) "both rows loaded in source order")
        (assert (= (textsOf rows) (list "A tiny fixture module" "Adds one to a")) "row text recovered exactly")
        true)))

fn mustErr! path: String why: String -> Bool
  (mt (dl/loadLedger! (fixture path))
    ((err _) true)
    ((ok _) (do (assert false why) false)))

fn testMalformedRows! -> Bool
  (do
    (assert (mustErr! "malformedKey.asn" "unknown key is a typed error") "unknown key rejected")
    (assert (mustErr! "missingText.asn" "missing :text is a typed error") "missing text rejected")
    (assert (mustErr! "wrongHead.asn" "non-:doc head is a typed error") "wrong head rejected")
    true)

fn testLoadMissingIsEmpty! -> Bool
  (mt (dl/loadLedger! (fixture "noSuchLedger.asn"))
    ((err e) (do (assert false (str "loadLedger! ok on a missing file: " e)) false))
    ((ok rows) (do (assert (= (listLength rows) 0) "a ledger that was never written reads as empty, not an error") true)))

fn ! sandboxDir! -> String
  (stringTrim (processRun "mktemp -d").stdout)

fn assertHitFound! found: (Option dl/DocRow) -> Bool
  (mt found
    ((none) (do (assert false "addOne should be found") false))
    ((some row) (do (assert (= row.text "Adds one to a") "hit returns the exact ledgered text") true)))

fn ! assertHit! dir: String -> Bool
  (mt (dl/findBySymbol! dir "asl/packages/fxpkg/src/thing.asl#addOne")
    ((err e) (assert false (str "findBySymbol! ok on a hit: " e)))
    ((ok found) (assertHitFound! found)))

fn assertMissFound! found: (Option dl/DocRow) -> Bool
  (mt found
    ((none) true)
    ((some _) (do (assert false "an unledgered symbol must miss, not hit") false)))

fn ! assertMiss! dir: String -> Bool
  (mt (dl/findBySymbol! dir "asl/packages/fxpkg/src/thing.asl#noSuchFn")
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
  (mt (dl/findByFile! dir "asl/packages/fxpkg/src/a.asl")
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
  (mt (dl/checkLedger! dir "asl/packages/fxpkg/doc.asn")
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
  (mt found
    ((none) (do (assert false "the extracted doc must be recoverable via (:doc) after --apply") false))
    ((some row) (do (assert (= row.text "Adds one to a") "the ledgered text matches the original :d exactly") true)))

fn ! assertRecovered! dir: String -> Bool
  (mt (dl/findBySymbol! dir "asl/packages/fxpkg/src/thing.asl#addOne")
    ((err e) (assert false (str "findBySymbol! ok after apply: " e)))
    ((ok found) (assertRecoveredFound! found)))

fn ! assertApplied! dir: String r: dx/ExtractResult -> Bool
  (mt (dx/applyExtract! dir r)
    ((err e) (assert false (str "applyExtract! ok: " e)))
    ((ok _) (assertRecovered! dir)))

fn ! assertExtractedAndApplied! dir: String -> Bool
  (mt (dx/extractFile! dir "asl/packages/fxpkg/src/thing.asl")
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

fn testMutantGuards! -> Bool
  (do
    (assert (= (dl/renderText "a\\nb") "a\nb") "mutant guard: renderText decodes the escaped newline a reader stored verbatim")
    (assert (mustErr! "missingText.asn" "mutant guard: a :symbol-only row is still rejected, not defaulted to empty text") "missing :text stays an error")
    true)

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
    true)
