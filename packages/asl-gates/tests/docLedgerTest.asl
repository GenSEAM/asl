(module asl-gates/tests/docLedgerTest
  :x [testLoadValid! testMalformedRows! testLoadMissingIsEmpty! testFindBySymbolHitMiss! testFindByFile! testResolveRows! testRoundTripWithExtractor! testMutantGuards! testTextRules testAddedRows testRowFindings! testTreeHoldsTheRule! runTests]
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

; (:m :ref DOC-THIN :do "the text rules on their own: a name echo, a signature paraphrase, a repeat of the (:m), a second sentence and a text over the cap are refused; a row that says why passes")
fn testTextRules -> Bool
  (let [(why "Waits on HTTP 503 so the caller retries instead of failing the turn")
        (long (stringRepeat "word " 41))]
    (do (assert (dl/nameEcho? "asl/packages/asl-mem/src/store.asl#VectorStore.name" "Store name") "a field row that repeats its own words is an echo")
        (assert (dl/nameEcho? "asl/packages/fxpkg/src/shm.asl#bufferId" "Identifier of the buffer") "id and identifier are one word")
        (assert (not (dl/nameEcho? "asl/packages/fxpkg/src/shm.asl#bufferId" why)) "a row with words of its own is not an echo")
        (assert (dl/paraphrase? "Returns the list of rows") "returns X without a reason is a paraphrase")
        (assert (dl/paraphrase? "true when the queue is empty") "true when X without a reason is a paraphrase")
        (assert (not (dl/paraphrase? "Returns 503 so that the caller waits instead of failing")) "a reason marker keeps it")
        (assert (not (dl/paraphrase? why)) "a row that does not open with a signature verb is no paraphrase")
        (assert (dl/paraphrase? "An index from its rows") "an X from its Y is a paraphrase")
        (assert (dl/paraphrase? "True for a closed queue") "true for X is a paraphrase")
        (assert (dl/paraphrase? "The size of the buffer in bytes") "the X of Y is a paraphrase")
        (assert (dl/paraphrase? "cfg: reads the sched level") "a lone word with a colon is a paraphrase")
        (assert (not (dl/paraphrase? "The size of the buffer, kept so that a reader never waits")) "the X of Y with a reason is kept")
        (assert (not (dl/paraphrase? "Trust model: the key is the bearer")) "two words before the colon are no lone name")
        (assert (listContains? (dl/textReasons "asl/packages/fxpkg/src/c.asl#choleskyRcond" "choleskyRcond n a l: an estimate the caller weighs" "") "paraphrase") "a text opening with its own name and arguments is a paraphrase even with a marker")
        (assert (dl/nameLead? "asl/packages/fxpkg/src/c.asl#abc!" "abc: x") "a three-letter name with a colon is a lead")
        (assert (not (dl/nameLead? "asl/packages/fxpkg/src/c.asl#ab" "ab is short")) "a name of two letters is too short to judge")
        (assert (not (dl/nameLead? "asl/packages/fxpkg/src/c.asl#choleskyRcond" "choleskyRcondX estimate")) "a longer word that starts with the name is no lead")
        (assert (not (dl/nameLead? "asl/packages/fxpkg/src/c.asl#" "x: module")) "a module row has no name to lead with")
        (assert (not (dl/nameLead? "asl/packages/fxpkg/src/c.asl#choleskyRcond" "Hager-Higham: choleskyRcond near 1e-16 means no digit is right")) "the name later in the text is no lead")
        (assert (dl/metaEcho? "keeps the cache warm for the next reader" "Keeps the cache warm for the next reader.") "a row equal to its (:m) is a repeat")
        (assert (not (dl/metaEcho? "" why)) "no (:m), no repeat")
        (assert (not (dl/metaEcho? "parses the header once" why)) "a different (:m) is no repeat")
        (assert (= (dl/sentenceCount "One. Two here.") 2) "two sentences counted")
        (assert (= (dl/sentenceCount "Uses e.g. Bytes for speed.") 1) "e.g. does not end a sentence")
        (assert (= (dl/textReasons "asl/packages/fxpkg/src/shm.asl#bufferId" why "") (list)) "the why row has no reason against it")
        (assert (listContains? (dl/textReasons "asl/packages/fxpkg/src/shm.asl#bufferId" long "") "overCap") (str "a text over " (stringFromInt64 (dl/rowCap)) " chars is refused"))
        (assert (= (dl/kindReason true "check" (list "check")) "testFile") "a test file row is refused")
        (assert (= (dl/kindReason false "Thing.id" (list "Thing")) "field") "a field row is refused")
        (assert (= (dl/kindReason false "helper" (list "pub")) "internal") "a row of a name the module does not export is refused")
        (assert (= (dl/kindReason false "" (list "pub")) "") "a module row of a source file may exist")
        (assert (= (dl/kindReason false "main" (list "main")) "plumbing") "an exported main carries no row")
        (assert (not (dl/testSource? "asl/tools/nativeTest.asl" (resultOr (fileReadString "asl/tools/nativeTest.asl") ""))) "asl/tools/nativeTest.asl, the runner, is not a test file")
        (assert (not (dl/testSource? "asl/tools/fooTest.asl" "(module x :x [helper runTests])\nfn helper -> Bool\n  true\n")) "a Test.asl name that exports a library beside runTests is no test file")
        (assert (dl/testSource? "asl/tools/mergeRows/mergeRowsTest.asl" "(module x :x [runTests])\nfn ! runTests -> Bool\n  true\n") "a file that exports only runTests is a test file")
        (assert (dl/testSource? "bench/aep/acceptanceTest.asl" "(module x :x [testA suiteWallS runTests])\n") "a suite exporting its test functions and wall is one too")
        (assert (dl/testSource? "asl/packages/p/tests/a.asl" "") "a file under tests/ is a test file")
        (assert (and (dl/ledgerPath? "asl/packages/p/doc.asn") (and (dl/ledgerPath? "asl/doc/tools.asn") (and (dl/ledgerPath? ".asl/mem/docs/harness.asn") (dl/ledgerPath? "tests/agentEval/doc.asn")))) "the ledger homes are ledgers")
        (assert (not (or (dl/ledgerPath? "asl/doc/web.asn") (or (dl/ledgerPath? "asl/packages/p/src/doc.asn") (dl/ledgerPath? "asl/doc/sub/x.asn")))) "asl/doc/web.asn and nested doc.asn files are not")
        (assert (dl/testSource? "asl/packages/p/fixtures/a.asl" "") "a file under fixtures/ is a test file")
        (assert (not (dl/testSource? "asl/packages/p/src/a.asl" "(module x :x [f])\n; :x [runTests] in a comment\n")) "a module that does not export runTests is no test file")
        true))

fn testAddedRows -> Bool
  (let [(diff (str "diff --git a/asl/packages/fxpkg/doc.asn b/asl/packages/fxpkg/doc.asn\n--- a/asl/packages/fxpkg/doc.asn\n+++ b/asl/packages/fxpkg/doc.asn\n@@ -1,0 +2 @@\n"
                   "+(:doc :symbol \"asl/packages/fxpkg/src/a.asl#pub\" :text \"why\")\n-(:doc :symbol \"asl/packages/fxpkg/src/a.asl#old\" :text \"x\")\n"))
        (rows (resultOr (dl/addedRows diff) (list)))]
    (do (assert (= (listLength rows) 1) (str "only the added row is taken: " (stringFromInt64 (listLength rows))))
        (assert (= (map (fn [(lr (Pair String dl/DocRow))] -> String (pairFirst lr)) rows) (list "asl/packages/fxpkg/doc.asn")) "with the ledger it was added to")
        (assert (not (ok? (dl/addedRows "+++ b/x/doc.asn\n+(:doc :bogus 1)\n"))) "a malformed added row is an error, not skipped")
        true))

fn fxSrcA -> String
  (str "(module fxpkg/a\n  :x [pub pub2 internalOnly]\n  :i [])\n\n"
       "fn pub -> Int64\n  1\n\n"
       "; (:m :do \"keeps the cache warm for the next reader\")\n"
       "fn pub2 -> Int64\n  2\n\n"
       "fn internalOnly -> Int64\n  3\n")

fn fxSrcB -> String
  "(module otherpkg/b\n  :x [use]\n  :i [(fxpkg/a :a fa)])\n\nfn use -> Int64\n  (+ (fa/pub) (fa/pub2))\n"

fn fxRow name: String text: String -> (Pair String dl/DocRow)
  (pair "asl/packages/fxpkg/doc.asn" (dl/DocRow :symbol (str "asl/packages/fxpkg/src/a.asl#" name) :text text))

fn whysOf fs: (List dl/RowFinding) name: String -> (List String)
  (map (fn [(f dl/RowFinding)] -> String f.why) (filter (fn [(f dl/RowFinding)] -> Bool (= f.sym (str "asl/packages/fxpkg/src/a.asl#" name))) fs))

; (:m :ref DOC-THIN :do "rowFindings! on a sandbox tree where otherpkg/b uses fxpkg/a pub and pub2 but not internalOnly: no row is required (a touched file whose exports have no rows owes nothing), an added row with a reason on a used export passes, and a name echo, a paraphrase, a repeat of the (:m), a row on an export no other package uses and a row of a removed symbol are each refused")
fn ! testRowFindings! -> Bool
  (let [(dir (sandboxDir!))
        (made (and (ok? (dirCreate (str dir "/asl/packages/fxpkg/src"))) (ok? (dirCreate (str dir "/asl/packages/otherpkg/src")))))
        (wa (ok? (fileWrite (str dir "/asl/packages/fxpkg/src/a.asl") (fxSrcA))))
        (wb (ok? (fileWrite (str dir "/asl/packages/otherpkg/src/b.asl") (fxSrcB))))
        (wd (ok? (fileWrite (str dir "/asl/packages/fxpkg/doc.asn") "(:doc :symbol \"asl/packages/fxpkg/src/a.asl#gone\" :text \"Kept for the old wire format readers\")\n")))
        (none (dl/rowFindings! dir (list) (list "asl/packages/otherpkg/src/b.asl")))
        (good (dl/rowFindings! dir (list (fxRow "pub" "Counts once per batch so that retries do not double the bill")) (list)))
        (fs (dl/rowFindings! dir (list (fxRow "pub" "pub") (fxRow "pub2" "Keeps the cache warm for the next reader") (fxRow "internalOnly" "Counts once per batch so that retries do not double the bill")) (list "asl/packages/fxpkg/src/a.asl")))
        (used (dl/crossUsed! dir (list "asl/packages/fxpkg/src/a.asl#pub" "asl/packages/fxpkg/src/a.asl#internalOnly" "asl/packages/fxpkg/src/a.asl#")))
        (para (dl/rowFindings! dir (list (fxRow "pub" "Returns the count of rows")) (list)))
        (gone (ok? (pathRemove dir)))]
    (do (assert (and made (and wa (and wb wd))) "sandbox written")
        (assert (listEmpty? none) (str "no row is required: an untouched ledger and exports without rows owe nothing: " (stringJoin (map (fn [(f dl/RowFinding)] -> String f.why) none) " ")))
        (assert (listEmpty? good) (str "a row on a used export that says why passes: " (stringJoin (map (fn [(f dl/RowFinding)] -> String f.why) good) " ")))
        (assert (mapHas? used "asl/packages/fxpkg/src/a.asl#pub") "pub is used from otherpkg")
        (assert (mapHas? used "asl/packages/fxpkg/src/a.asl#") "a module with a used export is public")
        (assert (not (mapHas? used "asl/packages/fxpkg/src/a.asl#internalOnly")) "internalOnly is used by no other package")
        (assert (listContains? (whysOf fs "pub") "nameEcho") (str "a name echo is refused: " (stringJoin (whysOf fs "pub") " ")))
        (assert (listContains? (whysOf para "pub") "paraphrase") "a signature paraphrase is refused")
        (assert (listContains? (whysOf fs "pub2") "metaEcho") (str "a repeat of the symbol's (:m) is refused: " (stringJoin (whysOf fs "pub2") " ")))
        (assert (= (whysOf fs "internalOnly") (list "notPublic")) (str "a row on an export no other package uses is refused: " (stringJoin (whysOf fs "internalOnly") " ")))
        (assert (= (whysOf fs "gone") (list "removed")) (str "a row of a removed symbol in a touched file is stale: " (stringJoin (whysOf fs "gone") " ")))
        (assert gone "sandbox removed")
        true))

; (:m :ref DOC-THIN :do "the invariant of rule docs on this tree: no row of any ledger is refused or stale by its own text and source file; docLedger.asl --check prints the findings")
fn ! testTreeHoldsTheRule! -> Bool
  (let [(fs (dl/treeFindings! "."))]
    (do (assert (> (listLength (dl/ledgerFiles! ".")) 50) (str "the ledgers are found: " (stringFromInt64 (listLength (dl/ledgerFiles! ".")))))
        (assert (listEmpty? fs) (str (stringFromInt64 (listLength fs)) " rows break rule docs, run asl run asl/packages/asl-gates/src/docLedger.asl --check: " (stringJoin (map (fn [(f dl/RowFinding)] -> String (str f.sym " " f.why)) (listTake fs 8)) "; ")))
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
    (assert (testTextRules) "testTextRules")
    (assert (testAddedRows) "testAddedRows")
    (assert (testRowFindings!) "testRowFindings!")
    (assert (testTreeHoldsTheRule!) "testTreeHoldsTheRule!")
    true)
