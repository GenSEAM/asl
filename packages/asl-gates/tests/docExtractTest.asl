(module asl-gates/tests/docExtractTest
  :x [testModuleDoc! testFnDoc! testFieldDoc! testEscaped! testComments! testDryRunNoWrite! testApplyRoundTrip! testMutantGuards! testNoteScan! testNoteMutantGuards! runTests]
  :i [(asl-gates/docExtract :a dx) (asl-parser/ast :a ast)])

fn fixtureDir -> String
  "asl/packages/asl-gates/tests/fixtures/docExtract"

fn fixture name: String -> String
  (str (fixtureDir) "/" name)

fn readFixture! name: String -> String
  (mt (fileReadString (fixture name))
    ((ok t) t)
    ((err _) (do (assert false (str (fixture name) " reads")) "")))

fn symbolsOf cs: (List dx/DocCandidate) -> (List String)
  (map (fn [(c dx/DocCandidate)] -> String c.symbol) cs)

fn textsOf cs: (List dx/DocCandidate) -> (List String)
  (map (fn [(c dx/DocCandidate)] -> String c.text) cs)

fn findCands! path: String text: String -> (List dx/DocCandidate)
  (mt (dx/findCandidates! path text)
    ((err e) (do (assert false (str "findCandidates! ok: " e)) (list)))
    ((ok cs) cs))

fn testModuleDoc! -> Bool
  (let [(text (readFixture! "moduleDoc.asl.txt")) (cs (findCands! "fx/moduleDoc.asl" text))]
    (do
      (assert (= (symbolsOf cs) (list "fx/moduleDoc.asl#")) "module doc keyed by path#, empty name")
      (assert (= (textsOf cs) (list "A module doc on its own line, alone")) "module doc text recovered exactly")
      (assert (ok? (ast/parse (dx/stripSource text cs))) "stripped module source still parses")
      (assert (not (stringContains? (dx/stripSource text cs) ":d ")) "the :d keyword is gone")
      true))

fn testTailrecCommentSymbol! -> Bool
  (let [(cs (findCands! "fx/tail.asl" "(module fx/tail :x [f])\n\n; (:m :why \"loop\")\nfn tailrec f -> Int64\n  1\n"))]
    (do
      (assert (= (symbolsOf cs) (list "fx/tail.asl#f")) (str "a comment before fn tailrec f is keyed by f: " (stringJoin (symbolsOf cs) " ")))
      true))

fn testInlineDocSpacing! -> Bool
  (let [(text "(module fx/inline :d \"An inline doc\" :x [f])\n")
        (cs (findCands! "fx/inline.asl" text))]
    (do
      (assert (= (dx/stripSource text cs) "(module fx/inline :x [f])\n") (str "an inline doc leaves one space, not two: " (dx/stripSource text cs)))
      true))

fn testFnDoc! -> Bool
  (let [(text (readFixture! "fnDoc.asl.txt")) (cs (findCands! "fx/fnDoc.asl" text))]
    (do
      (assert (= (symbolsOf cs) (list "fx/fnDoc.asl#addOne")) "fn doc keyed by path#name")
      (assert (= (textsOf cs) (list "Adds one to a")) "fn doc text recovered exactly")
      (assert (ok? (ast/parse (dx/stripSource text cs))) "stripped fn source still parses")
      true))

fn testFieldDoc! -> Bool
  (let [(text (readFixture! "fieldDoc.asl.txt")) (cs (findCands! "fx/fieldDoc.asl" text))]
    (do
      (assert (= (symbolsOf cs) (list "fx/fieldDoc.asl#Thing.id")) "only the documented field is found, keyed path#Type.field")
      (assert (= (textsOf cs) (list "Row identifier")) "field doc text recovered exactly")
      (let [(stripped (dx/stripSource text cs))]
        (do
          (assert (ok? (ast/parse stripped)) "stripped schema source still parses")
          (assert (stringContains? stripped "(:f label String)") "undocumented field untouched")
          (assert (not (stringContains? stripped "Row identifier")) "field doc text removed from source")
          true))))

fn testEscaped! -> Bool
  (let [(text (readFixture! "escaped.asl.txt")) (cs (findCands! "fx/escaped.asl" text))
        (expected "First line\\nSecond line with a \\\"quoted\\\" word and a backslash \\\\ here")]
    (do
      (assert (= (listLength cs) 1) "one doc candidate in the escaped fixture")
      (assert (= (textsOf cs) (list expected)) "escapes and embedded quotes survive exactly, unexpanded")
      (assert (ok? (ast/parse (dx/stripSource text cs))) "stripped escaped source still parses")
      true))

fn kindsAt cs: (List dx/DocCandidate) idx: Int64 -> String
  (optionOr (listGet (textsOf cs) idx) "")

fn testComments! -> Bool
  (let [(text (readFixture! "comments.asl.txt")) (cs (findCands! "fx/comments.asl" text))]
    (do
      (assert (= (listLength cs) 4) "why-only, why-with-ref, free comment and a trailing comment")
      (assert (listContains? (symbolsOf cs) "fx/comments.asl#stripIt") "why-only form keyed by the next fn")
      (assert (listContains? (textsOf cs) "strip outer quotes from docstring") "why-only text recovered")
      (assert (listContains? (textsOf cs) "a free comment about addOne") "free comment text recovered")
      (assert (listContains? (textsOf cs) "kept form test") "why text recovered even when the form keeps other keys")
      (assert (listAny? (fn [(s String)] -> Bool (stringStartsWith? s "fx/comments.asl#L")) (symbolsOf cs)) "a comment with no following definition keys by line")
      (let [(stripped (dx/stripSource text cs))]
        (do
          (assert (ok? (ast/parse stripped)) "stripped comments source still parses")
          (assert (stringContains? stripped "(:m :ref gates)") "the (:m) form survives minus :why when other keys remain")
          (assert (not (stringContains? stripped ":why")) "no :why key remains anywhere")
          (assert (not (stringContains? stripped "strip outer quotes")) "why-only comment line fully removed")
          true))))

fn testDryRunNoWrite! -> Bool
  (let [(made (processRun "mktemp -d")) (dir (stringTrim made.stdout))
        (dst (str dir "/moduleDoc.asl")) (src (fixture "moduleDoc.asl.txt"))]
    (do
      (assert (= made.exitCode 0) "temp dir made")
      (assert (ok? (fileWrite dst (readFixture! "moduleDoc.asl.txt"))) "fixture copied")
      (mt (dx/extractFile! dir "moduleDoc.asl")
        ((err e) (assert false (str "extractFile! ok: " e)))
        ((ok r)
          (do
            (assert (= r.unchanged false) "candidates were found")
            (assert (= (readFixture! "moduleDoc.asl.txt") (resultOr (fileRead dst) src)) "dry run touched nothing on disk"))))
      (assert (= (processRun (str "rm -rf '" dir "'")).exitCode 0) "temp dir removed")
      true))

fn fileTextOr! path: String -> String
  (mt (fileReadString path) ((ok t) t) ((err _) ""))

fn testApplyRoundTrip! -> Bool
  (let [(made (processRun "mktemp -d")) (dir (stringTrim made.stdout))
        (pkgDir (str dir "/asl/packages/fxpkg")) (mk (processRun (str "mkdir -p '" pkgDir "'")))
        (dst (str pkgDir "/src.asl"))]
    (do
      (assert (= made.exitCode 0) "temp dir made")
      (assert (= mk.exitCode 0) "package dir made")
      (assert (ok? (fileWrite dst (readFixture! "fnDoc.asl.txt"))) "fixture copied into a package layout")
      (mt (dx/extractFile! dir "asl/packages/fxpkg/src.asl")
        ((err e) (assert false (str "extractFile! ok: " e)))
        ((ok r)
          (mt (dx/applyExtract! dir r)
            ((err e) (assert false (str "applyExtract! ok: " e)))
            ((ok ledgerRel)
              (do
                (assert (= ledgerRel "asl/packages/fxpkg/doc.asn") "ledger lives beside the package, per D150")
                (assert (= (fileTextOr! dst) r.stripped) "the file on disk matches the computed stripped text")
                (assert (not (stringContains? (fileTextOr! dst) ":d ")) "the :d keyword is gone from the written file")
                (assert (stringContains? (fileTextOr! (str dir "/" ledgerRel)) "Adds one to a") "the ledger on disk carries the doc text")
                (assert (= (processRun (str "asl/host/out/asl-host check '" dst "'")).exitCode 0) "asl-host check passes on the stripped file"))))))
      (assert (= (processRun (str "rm -rf '" dir "'")).exitCode 0) "temp dir removed")
      true))

fn testMutantGuards! -> Bool
  (let [(text (readFixture! "comments.asl.txt")) (cs (findCands! "fx/comments.asl" text))]
    (do
      (assert (listAll? (fn [(t String)] -> Bool (not (stringStartsWith? t "\""))) (textsOf cs)) "mutant guard: :text never keeps its quotes")
      (assert (stringContains? (dx/stripSource text cs) ":ref gates") "mutant guard: sibling keys of :why survive")
      true))

fn noteSymbolsOf cs: (List dx/NoteCandidate) -> (List String)
  (map (fn [(c dx/NoteCandidate)] -> String c.symbol) cs)

fn noteTextsOf cs: (List dx/NoteCandidate) -> (List String)
  (map (fn [(c dx/NoteCandidate)] -> String c.text) cs)

fn scanNotes! path: String -> (List dx/NoteCandidate)
  (dx/noteScanAll path (readFixture! "noteScan.asl.txt"))

fn testNoteScan! -> Bool
  (let [(cs (scanNotes! "fx/noteScan.asl"))]
    (do
      (assert (= (noteSymbolsOf cs) (list "fx/noteScan.asl#h" "fx/noteScan.asl#f" "fx/noteScan.asl#k" "fx/noteScan.asl#"))
              (str "a note is keyed by the decl that follows it, or by path# when none follows: " (stringJoin (noteSymbolsOf cs) " ")))
      (assert (listContains? (noteTextsOf cs) "Banner note with nothing else before the first real decl.") "a single note before a decl is recovered")
      (assert (listContains? (noteTextsOf cs) "First note for f. Second note for f, still joined with a space.") "consecutive notes before one decl join with a space")
      (assert (listContains? (noteTextsOf cs) "Edge case: a quote like \"this\" inside the note,\nspanning two physical lines in one literal.") "a note whose literal spans two physical lines, with an embedded escaped quote, is recovered whole and unescaped")
      (assert (listContains? (noteTextsOf cs) "Trailing note with nothing after it.") "a trailing note with no following decl is keyed by path# alone")
      true))

fn testNoteMutantGuards! -> Bool
  (let [(cs (scanNotes! "fx/noteScan.asl"))]
    (do
      (assert (listAll? (fn [(t String)] -> Bool (not (stringStartsWith? t "\""))) (noteTextsOf cs)) "mutant guard: a note's :text never keeps its surrounding quotes")
      (assert (listAll? (fn [(t String)] -> Bool (not (stringContains? t "\\\""))) (noteTextsOf cs)) "mutant guard: an escaped quote inside a note is unescaped to a plain quote, not left as a literal backslash-quote pair")
      true))

fn ! runTests -> Bool
  (do
    (assert (testModuleDoc!) "testModuleDoc!")
    (assert (testInlineDocSpacing!) "testInlineDocSpacing!")
    (assert (testTailrecCommentSymbol!) "testTailrecCommentSymbol!")
    (assert (testFnDoc!) "testFnDoc!")
    (assert (testFieldDoc!) "testFieldDoc!")
    (assert (testEscaped!) "testEscaped!")
    (assert (testComments!) "testComments!")
    (assert (testDryRunNoWrite!) "testDryRunNoWrite!")
    (assert (testApplyRoundTrip!) "testApplyRoundTrip!")
    (assert (testMutantGuards!) "testMutantGuards!")
    (assert (testNoteScan!) "testNoteScan!")
    (assert (testNoteMutantGuards!) "testNoteMutantGuards!")
    true)
