(module asl-checker/tests/quadGoldenTest
  :x [entries checkerRoots goldenDigests corpusText rewritten? runTests]
  :i [(asl-parser/ast :a a) (asl-checker/resolve :a r) (asl-checker/check :a chk) (asl-checker/types :a ty)])

fn entries -> (List String)
  (list "asl/packages/asl-forms/tests/checkSemanticTest.asl" "asl/packages/asl-cli/src/main.asl")

fn checkerRoots -> (List String)
  (list "asl/packages/asl-cli/src" "." "asl/packages/asl-parser/src" "asl/packages/asl-checker/src" "asl/packages/asl-compiler/src" "asl/packages/asl-eval/src" "asl/packages/asl-codegen/src" "asl/packages/asl-text/src" "asl/packages" "asl")

fn goldenDigests -> (List (Pair String String))
  (list (pair "asl/packages/asl-forms/tests/checkSemanticTest.asl" "6704790146093603440:686858")
        (pair "asl/packages/asl-cli/src/main.asl" "2312148940748687743:1456944"))

fn diagLine d: ty/Diagnostic -> String
  (str d.path ":" d.line ":" d.col " " d.code " " d.message " | " d.msg)

fn ! moduleText path: String deps: (Map String r/ModuleSummary) viaSource: Bool -> String
  (mt (fileRead path)
    ((err _) (str "(unreadable " path ")"))
    ((ok src) (mt (a/parse src)
                ((err e) (str "(parse " path " " e.msg ")"))
                ((ok forms) (str "(module " path "\n"
                                 (str (r/collectSummary forms path)) "\n"
                                 (stringJoin (map diagLine (chk/checkModule forms deps path)) "\n") "\n"
                                 (if viaSource (stringJoin (map diagLine (chk/checkSource src deps path)) "\n") "") ")")))))

fn ! corpusText entry: String -> String
  (mt (fileRead entry)
    ((err _) (str "(unreadable " entry ")"))
    ((ok src) (mt (a/parse src)
                ((err e) (str "(parse " entry " " e.msg ")"))
                ((ok forms) (let [(summary (r/collectSummary forms entry))
                                  (importPaths (r/mapValuesList summary.imports))]
                              (mt (r/loadModuleDeps! (cons (r/parentDirOf entry) (checkerRoots)) importPaths)
                                ((err e) (str "(deps " entry " " e ")"))
                                ((ok deps) (str (stringJoin (mapKeys deps) "\n") "\n"
                                                (moduleText entry deps true) "\n"
                                                (stringJoin (map (fn [(m r/ModuleSummary)] -> String (str (str m) "\n" (moduleText m.path deps false))) (filter (fn [(m r/ModuleSummary)] -> Bool (not (rewritten? m.path))) (mapValues deps))) "\n")))))))))

fn rewritten? path: String -> Bool
  (or (stringContains? path "asl-checker/src/") (stringContains? path "asl-ir/src/"))

fn ! rootRelative text: String -> String
  (mt (realPath ".")
    ((ok root) (stringReplace text (str root "/") ""))
    ((err _) text))

fn digestOf text: String -> String
  (str (stringFromInt64 (fnv1a64 text)) ":" (stringFromInt64 (stringLength text)))

fn ! goldenMismatch entry: String -> String
  (let [(text (rootRelative (corpusText entry)))
        (got (digestOf text))
        (want (optionOr (mapGet (fold (fn [(m (Map String String)) (p (Pair String String))] -> (Map String String) (mapSet m (pairFirst p) (pairSecond p))) (mapEmpty) (goldenDigests)) entry) ""))]
    (do (print (str "(quadGolden :entry " entry " :digest \"" got "\")"))
        (assert (> (stringLength text) 10000) (str entry ": the corpus must load, not collapse: " (stringLength text)))
        (if (= got want) "" (str entry ": want " want ", got " got))))

fn ! runTests -> Bool
  (let [(misses (filter (fn [(m String)] -> Bool (not (stringEmpty? m))) (map goldenMismatch (entries))))]
    (do (assert (listEmpty? misses) (str "checker summaries and diagnostics are byte-identical to the pre-QUAD-LISTGET goldens: " (stringJoin misses "; ")))
        true))
