(module asl-checker/tests/depIndexTest
  :x [runTests main]
  :i [(types :a ty) (ast :a a) (resolve :a r)])

fn summaryOf name: String path: String -> r/ModuleSummary
  (r/ModuleSummary :name name :path path :hasHeader true :hasDoc true :exports (list "f") :exportedTypes (list) :imports (mapEmpty) :funs (mapEmpty) :schemas (mapEmpty) :enums (mapEmpty) :caseOwner (mapEmpty) :exportedCases (mapEmpty) :exportedFields (mapEmpty))

fn depSummary k: Int64 -> r/ModuleSummary
  (summaryOf (str "pkg/mod" (stringFromInt64 k)) (str "/x/pkg/src/mod" (stringFromInt64 k) ".asl"))

fn synthDeps d: Int64 -> (Map String r/ModuleSummary)
  (fold (fn [(m (Map String r/ModuleSummary)) (k Int64)] -> (Map String r/ModuleSummary) (mapSet m (str "/x/pkg/src/mod" (stringFromInt64 k) ".asl") (depSummary k))) (mapEmpty) (range 0 d))

fn synthSource d: Int64 q: Int64 extra: String -> String
  (str "(module syn :x [g] :i [" (stringJoin (map (fn [(k Int64)] -> String (str "(pkg/mod" (stringFromInt64 k) " :a m" (stringFromInt64 k) ")")) (range 0 d)) " ") "])\nfn g -> Int64\n  (do "
       (stringJoin (map (fn [(i Int64)] -> String (str "(m" (stringFromInt64 (mod i d)) "/f)")) (range 0 q)) " ") " " extra " 0)\n")

fn synthDiags d: Int64 q: Int64 extra: String deps: (Map String r/ModuleSummary) -> (List ty/Diagnostic)
  (mt (a/parse (synthSource d q extra))
    ((err _) (list (ty/Diagnostic :code "parse" :message "synthetic source did not parse" :msg "" :line 0 :col 0 :path "syn.asl")))
    ((ok forms) (r/resolveModule (r/collectSummary forms "syn.asl") forms deps)))

fn synthDiagsIn d: Int64 q: Int64 extra: String ix: r/DepIndex -> (List ty/Diagnostic)
  (mt (a/parse (synthSource d q extra))
    ((err _) (list (ty/Diagnostic :code "parse" :message "synthetic source did not parse" :msg "" :line 0 :col 0 :path "syn.asl")))
    ((ok forms) (r/resolveModuleIn (r/collectSummary forms "syn.asl") forms ix)))

fn trickyDeps -> (Map String r/ModuleSummary)
  (let [(helper (summaryOf "Standalone" "/some/path/helper.asl"))]
    (fold (fn [(m (Map String r/ModuleSummary)) (e (Pair String r/ModuleSummary))] -> (Map String r/ModuleSummary) (mapSet m (pairFirst e) (pairSecond e))) (mapEmpty)
      (list (pair "/pkgA/util.asl" (summaryOf "pkgA/util" "/pkgA/util.asl"))
            (pair "/pkgB/util.asl" (summaryOf "pkgB/util" "/pkgB/util.asl"))
            (pair "/custom/store.asl" (summaryOf "vendor/tool" "/custom/store.asl"))
            (pair "/some/path/helper.asl" helper)
            (pair "aliasKey" helper)
            (pair "pkg/mod1" (depSummary 1))
            (pair "pkg/mod10" (depSummary 10))
            (pair "noext" (summaryOf "raw" "/a/b/rawfile"))
            (pair "deep" (summaryOf "a/b/c" "/r/a/b/c.asl")))))

fn probes -> (List String)
  (list "util" "pkgA/util" "/pkgA/util.asl" "tool" "vendor/tool" "store" "custom/store" "helper" "path/helper" "some/path/helper" "/some/path/helper.asl"
        "aliasKey" "Standalone" "mod1" "pkg/mod1" "src/mod1" "mod10" "pkg/mod10" "od1" "rawfile" "b/rawfile" "raw" "noext" "/a/b/rawfile"
        "c" "b/c" "a/b/c" "r/a/b/c" "missing" "" "pkg" "x/pkg/src/mod1" "/x/pkg/src/mod1.asl")

fn resultText res: (Result r/ModuleSummary String) -> String
  (mt res ((ok m) (str "ok " m.name " @ " m.path)) ((err msg) (str "err " msg)))

fn testIndexAgreesWithScan -> Bool
  (let [(deps (trickyDeps)) (ix (r/depIndexOf deps)) (scan (r/depScanOf deps))
        (differs (filter (fn [(p String)] -> Bool (or (!= (resultText (r/resolveDepIn p ix)) (resultText (r/resolveDepTarget p deps))) (!= (resultText (r/resolveDepIn p scan)) (resultText (r/resolveDepTarget p deps))))) (probes)))]
    (do (assert (listEmpty? differs) (str "indexed and scanning lookups agree on every probe; differing: " (stringJoin differs ", ")))
        (assert (stringContains? (resultText (r/resolveDepIn "util" ix)) "ERR_AMBIGUOUS_MODULE") "util matches both pkgA/util and pkgB/util through the index")
        (assert (= (resultText (r/resolveDepIn "mod1" ix)) "ok pkg/mod1 @ /x/pkg/src/mod1.asl") "mod1 resolves pkg/mod1, not pkg/mod10")
        (assert (= (resultText (r/resolveDepIn "helper" ix)) "ok Standalone @ /some/path/helper.asl") "one summary under two keys is not ambiguous")
        (assert (= (resultText (r/resolveDepIn "tool" ix)) "ok vendor/tool @ /custom/store.asl") "a name tail matches")
        (assert (= (resultText (r/resolveDepIn "noext" ix)) "ok raw @ /a/b/rawfile") "a deps key that no rule matches falls back to the key lookup")
        (assert (= (resultText (r/resolveDepIn "rawfile" ix)) "err ERR_NOT_FOUND: no module matches rawfile") "a path without .asl has no path-tail keys")
        (assert (= (resultText (r/resolveDepIn "" ix)) "err ERR_NOT_FOUND: empty module path") "an empty path is an error")
        true))

fn testCandidatesIndependentOfDepCount -> Bool
  (let [(small (synthDeps 40)) (large (synthDeps 80))]
    (do (assert (= (listLength (r/depCandidates "pkg/mod3" (r/depIndexOf small))) 1) "an indexed lookup among 40 deps reads one candidate")
        (assert (= (listLength (r/depCandidates "pkg/mod3" (r/depIndexOf large))) 1) "an indexed lookup among 80 deps still reads one candidate")
        (assert (= (listLength (r/depCandidates "mod3" (r/depIndexOf large))) 1) "a path tail reads one candidate")
        (assert (= (listLength (r/depCandidates "pkg/mod3" (r/depScanOf large))) 80) "the unindexed lookup still scans all 80 deps")
        true))

fn testResolveModuleDiagnostics -> Bool
  (let [(deps (synthDeps 12))
        (clean (synthDiags 12 40 "" deps))
        (bad (synthDiags 12 40 "(m1/g) (zz/f)" deps))
        (texts (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) bad))]
    (do (assert (listEmpty? clean) (str "qualified references to exported members resolve: " (stringJoin (map (fn [(d ty/Diagnostic)] -> String d.message) clean) "; ")))
        (assert (listContains? texts "rule-9 ERR_NOT_EXPORTED: g is not exported by pkg/mod1") (str "an unexported member is reported against its module: " (stringJoin texts "; ")))
        (assert (listContains? texts "rule-9 zz/f: alias zz is not imported") (str "an unimported alias is reported: " (stringJoin texts "; ")))
        (assert (= (listLength bad) 2) (str "exactly the two seeded diagnostics: " (stringJoin texts "; ")))
        true))

fn testResolverReadsTheIndex -> Bool
  (let [(deps (synthDeps 12))
        (real (r/depIndexOf deps))
        (forged (with real :byKey (mapSet real.byKey "pkg/mod1" (list (with (depSummary 1) :exports (list "f" "g"))))))
        (codes (fn [(ds (List ty/Diagnostic))] -> String (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) ds) "; ")))
        (viaForged (synthDiagsIn 12 40 "(m1/g)" forged))
        (viaScan (synthDiagsIn 12 40 "(m1/g)" (r/depScanOf deps)))
        (viaIndex (synthDiagsIn 12 40 "(m1/g)" (r/depIndexOf deps)))
        (viaModule (synthDiags 12 40 "(m1/g)" deps))]
    (do (assert (listEmpty? viaForged) (str "resolveModuleIn reads pkg/mod1 from the index bucket, which exports g: " (codes viaForged)))
        (assert (= (codes viaIndex) "rule-9 ERR_NOT_EXPORTED: g is not exported by pkg/mod1") (str "a real index reads the map, where g is not exported: " (codes viaIndex)))
        (assert (= (codes viaScan) "ERR_INTERNAL resolveModuleIn needs an indexed DepIndex (depIndexOf), got a scan") (str "a whole module is never resolved over a scan: " (codes viaScan)))
        (assert (= (codes viaModule) (codes viaIndex)) "resolveModule reports what resolveModuleIn over depIndexOf reports")
        true))

fn ! runTests -> Bool
  (do (assert (testResolverReadsTheIndex) "the resolver reads lookups from the index it is given")
      (assert (testIndexAgreesWithScan) "the dep index answers every lookup exactly as the scan")
      (assert (testCandidatesIndependentOfDepCount) "an indexed lookup reads only matching candidates")
      (assert (testResolveModuleDiagnostics) "resolveModule over the index keeps its diagnostics")
      true)

fn ! main args: (List String) -> (Result Int64 String)
  (let [(d (optionOr (mt (listHead args) ((some s) (stringToInt64 s)) ((none) (none))) 50))]
    (do (println (str "diags " (stringFromInt64 (listLength (synthDiags d 2000 "" (synthDeps d)))))) (ok 0)))
