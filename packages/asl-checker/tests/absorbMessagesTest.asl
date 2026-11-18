(module asl-checker/absorbMessagesTest
  :x [runTests]
  :i [(asl-parser/ast :a a) (asl-checker/check :a c) (asl-checker/types :a ty) (asl-checker/resolve :a r) (asl-checker/checkCached :a cc) (asl-tools/fleet/run :a fr)])

fn ! workDir! -> String
  (let [(path (str "/tmp/acm-absorb-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (monotonicNs))))]
    (do (assert (ok? (dirCreate path)) "work directory made") path))

fn ! write! path: String text: String -> Bool
  (let [(res (fileWrite path text))]
    (do (assert (ok? res) (str "fixture " path " written")) true))

fn scanSrc -> String
  "(module lib/scan :x [compact unescape] :i [])\n\nfn compact x: Int64 -> Int64\n  x\n\nfn unescape x: Int64 -> Int64\n  x\n"

fn midSrc -> String
  "(module lib/mid :x [other] :i [(lib/scan :a sc)])\n\nfn other x: Int64 -> Int64\n  (sc/compact x)\n"

fn userSrc name: String imports: String call: String -> String
  (str "(module " name " :x [f] :i [" imports "])\n\nfn f -> Int64\n  (" call " 1)\n")

fn ! fixtureDir! -> String
  (let [(dir (workDir!))
        (lib (dirCreate (str dir "/lib")))]
    (do (assert (ok? lib) "lib dir made")
        (write! (str dir "/.asl.config.asn") "(:asl-config :workspace \"lib\" :version \"1.0.0\")\n")
        (write! (str dir "/lib/scan.asl") (scanSrc))
        (write! (str dir "/lib/mid.asl") (midSrc))
        dir))

fn ! diagsOf! dir: String name: String imports: String call: String -> String
  (let [(path (str dir "/" name ".asl"))
        (w (write! path (userSrc (str "lib/" name) imports call)))
        (v (pairFirst (cc/checkFileCached! path (list) (cc/emptyCache))))]
    (do (assert w "importer written")
        (match v
          ((err e) (str "io " e))
          ((ok verdict) (stringJoin (map (fn [(d ty/Diagnostic)] -> String d.message) verdict.diags) "\n")))))

fn ! testRealPathImportByPath! dir: String -> Bool
  (let [(m (diagsOf! dir "byPath" "(lib/scan.asl :a ks)" "ks/compact"))
        (applied (diagsOf! dir "applied" "(lib/scan :a ks)" "ks/compact"))]
    (do (assert (stringContains? m "lib/scan.asl not declared; write lib/scan: add (lib/scan :a ks) to :i") (str "the real check path names the module and the alias the file wrote, got " m))
        (refute (stringContains? m "<alias") (str "no placeholder in the line, got " m))
        (assert (stringEmpty? applied) (str "applying the suggested import literally makes the check green, got " applied))
        true))

fn ! testRealPathStaleName! dir: String -> Bool
  (let [(m (diagsOf! dir "stale" "(oldlib/scan :a ks)" "ks/compact"))]
    (do (assert (stringContains? m "candidates: lib/scan at ") (str "the stale name still lists its candidate, got " m))
        (assert (stringContains? m "; write lib/scan: add (lib/scan :a ks) to :i") (str "a single candidate comes with the ready import line, got " m))
        true))

fn ! testNoGuessWithoutOneModule! dir: String -> Bool
  (let [(m (diagsOf! dir "none" "(lib/none.asl :a ks)" "ks/compact"))]
    (do (assert (stringContains? m "lib/none.asl not declared") (str "an unknown path stays unresolved, got " m))
        (refute (stringContains? m "write ") (str "no module to name means no suggestion, got " m))
        true))

fn ! testTopLevelPairsWithoutAlias! dir: String -> Bool
  (let [(cl (r/loadModuleDepsFrom! (list dir) (list "lib/scan.asl") (mapEmpty) (r/emptyModIndex)))
        (m (stringJoin cl.unresolved "\n"))]
    (do (assert (stringContains? m "add (lib/scan :a scan) to :i") (str "an unknown alias falls back to the last segment of the module name, got " m))
        (refute (stringContains? m "scan.asl)") (str "never the path segment, got " m))
        (refute (stringContains? m "<alias") (str "never a placeholder, got " m))
        true))

fn ! testAliasWithoutImportNamesExporter! dir: String -> Bool
  (let [(m (diagsOf! dir "viaMid" "(lib/mid :a m)" "ks/compact"))]
    (do (assert (stringContains? m "ks/compact: alias ks is not imported; only lib/scan exports compact: add (lib/scan :a ks) to :i") (str "the one exporter in the real closure, held under path and name, is named once, got " m))
        true))

fn ! testAliasAlreadyImportedElsewhere! dir: String -> Bool
  (let [(m (diagsOf! dir "twice" "(lib/scan :a scan)" "ks/compact"))]
    (do (assert (stringContains? m "lib/scan is already imported as scan: call scan/compact") (str "an existing import is named instead of a second one, got " m))
        (refute (stringContains? m "add (lib/scan") (str "no second import is proposed, got " m))
        true))

fn messagesOf src: String deps: (Map String r/ModuleSummary) -> String
  (match (a/parseForTypeCheck src)
    ((ok forms) (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) (c/checkModuleSource forms deps "probe.asl" src)) "\n"))
    ((err e) (str "parse " e.msg)))

fn depOf name: String -> (Map String r/ModuleSummary)
  (match (a/parse (str "(module " name " :x [helper])\n\nfn helper -> Int64\n  1\n"))
    ((ok forms) (mapSet (mapEmpty) "dep.asl" (r/collectSummary forms "dep.asl")))
    ((err _) (mapEmpty)))

fn testAliasWithoutExporterStaysPlain -> Bool
  (let [(m (messagesOf "(module probe :x [f])\n\nfn f -> Int64\n  (xs/other)\n" (depOf "dep/xs")))]
    (do (assert (stringContains? m "alias xs is not imported") "the alias error stays")
        (refute (stringContains? m "only ") (str "no exporter of the name means no suggestion, got " m))
        true))

fn testUnknownStringHelperNamesNearest -> Bool
  (let [(m (messagesOf "(module probe :x [f])\n\nfn f a: String b: String -> Bool\n  (stringEqual? a b)\n" (mapEmpty)))]
    (do (assert (stringContains? m "unbound symbol: stringEqual?; did you mean = (canonical asl name)") (str "an unknown stringEqual? names the canonical existing form, got " m))
        (refute (stringContains? m "write (= a b)") (str "the :fix text is not repeated here, got " m))
        true))

fn testOptionPatternOverList -> Bool
  (let [(m (messagesOf "(module probe :x [f])\n\nfn f xs: (List String) -> Int64\n  (match xs\n    ((some v) 1)\n    ((none) 0))\n" (mapEmpty)))]
    (do (assert (stringContains? m "pattern some: expected (Option") (str "the mismatch stays, got " m))
        (assert (stringContains? m "hint: the value is a List, not an Option: (listHead xs)") (str "the List value hint names listHead, got " m))
        true))

fn testOptionOverOptionHasNoListHint -> Bool
  (let [(m (messagesOf "(module probe :x [f])\n\nfn f x: (Option Int64) -> Int64\n  (match x\n    ((some v) v)\n    ((none) 0))\n" (mapEmpty)))]
    (do (refute (stringContains? m "hint: the value is a List") (str "a well-typed match gets no hint, got " m))
        true))

fn testRunTestsUnitReturn -> Bool
  (let [(m (messagesOf "(module probe :x [runTests])\n\nfn runTests -> Bool\n  (assert true \"x\")\n" (mapEmpty)))]
    (do (assert (stringContains? m "return of runTests: expected Bool, found Unit") (str "the mismatch stays, got " m))
        (assert (stringContains? m "a runTests body ends with true") (str "the Unit return hint says runTests ends with true, got " m))
        true))

fn testStrlenNamesOnlyStringForm -> Bool
  (let [(m (messagesOf "(module probe :x [f])\n\nfn f a: String -> Int64\n  (strlen a)\n" (mapEmpty)))]
    (do (assert (stringContains? m "did you mean stringLength (canonical asl name)") (str "strlen on a String names stringLength, got " m))
        (refute (stringContains? m "listLength") (str "and not the list or map forms, got " m))
        true))

fn testUnitReturnOfOtherFn -> Bool
  (let [(m (messagesOf "(module probe :x [helper])\n\nfn helper -> Bool\n  (assert true \"x\")\n" (mapEmpty)))]
    (do (assert (stringContains? m "return of helper: expected Bool, found Unit; hint: the body ends in a Unit expression; make its last expression the Bool value") (str "a non-runTests fn gets the general hint, got " m))
        (refute (stringContains? m "runTests body") (str "the runTests wording is only for runTests, got " m))
        true))

fn ! runTests -> Bool
  (let [(dir (fixtureDir!))]
    (do (assert (testRealPathImportByPath! dir) "testRealPathImportByPath")
        (assert (testRealPathStaleName! dir) "testRealPathStaleName")
        (assert (testNoGuessWithoutOneModule! dir) "testNoGuessWithoutOneModule")
        (assert (testTopLevelPairsWithoutAlias! dir) "testTopLevelPairsWithoutAlias")
        (assert (testAliasWithoutImportNamesExporter! dir) "testAliasWithoutImportNamesExporter")
        (assert (testAliasAlreadyImportedElsewhere! dir) "testAliasAlreadyImportedElsewhere")
        (assert (testAliasWithoutExporterStaysPlain) "testAliasWithoutExporterStaysPlain")
        (assert (testUnknownStringHelperNamesNearest) "testUnknownStringHelperNamesNearest")
        (assert (testStrlenNamesOnlyStringForm) "testStrlenNamesOnlyStringForm")
        (assert (testOptionPatternOverList) "testOptionPatternOverList")
        (assert (testOptionOverOptionHasNoListHint) "testOptionOverOptionHasNoListHint")
        (assert (testRunTestsUnitReturn) "testRunTestsUnitReturn")
        (assert (testUnitReturnOfOtherFn) "testUnitReturnOfOtherFn")
        (assert (ok? (fr/shellOut (str "/bin/rm -rf " dir) 5000)) "work directory removed")
        true))
