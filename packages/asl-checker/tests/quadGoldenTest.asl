(module asl-checker/tests/quadGoldenTest
  :x [entries checkerRoots goldenFileFor corpusText rewritten? runTests]
  :i [(asl-parser/ast :a a) (asl-checker/resolve :a r) (asl-checker/check :a chk) (asl-checker/types :a ty)])

fn entries -> (List String)
  (list "asl/packages/asl-forms/tests/checkSemanticTest.asl" "asl/packages/asl-cli/src/main.asl")

fn checkerRoots -> (List String)
  (list "asl/packages/asl-cli/src" "." "asl/packages/asl-parser/src" "asl/packages/asl-checker/src" "asl/packages/asl-compiler/src" "asl/packages/asl-codegen/src" "asl/packages/asl-text/src" "asl/packages" "asl")

; (:m :ref CHKFIX :do "the golden is the full checker summary text in fixtures/quadGolden, not just its digest, so a mismatch prints a reviewable line diff instead of two opaque numbers; re-recorded after PRELPASS/Perceus/TGTTRIM merged, asl-eval/src dropped from checkerRoots since that package is deleted")
; (:m :ref TOKDEFFIX :do "both goldens re-recorded from corpusText on sh/TOKDEFM: only the summary lines of asl-parser/ast and asl-parser/astPrinter (TOKEN-DEFAULTS fns) and, in main.golden, asl-target-llvm/rc and ssa (QW-ALLOC from main) changed, each by added exports and calls")
fn goldenFileFor entry: String -> String
  (cond ((= entry "asl/packages/asl-forms/tests/checkSemanticTest.asl") "asl/packages/asl-checker/tests/fixtures/quadGolden/checkSemanticTest.golden.txt")
        ((= entry "asl/packages/asl-cli/src/main.asl") "asl/packages/asl-checker/tests/fixtures/quadGolden/main.golden.txt")
        (else (str "asl/packages/asl-checker/tests/fixtures/quadGolden/" (stringReplace (stringReplace entry "/" "_") "." "_") ".golden.txt")))

fn diagLine d: ty/Diagnostic -> String
  (str d.path ":" d.line ":" d.col " " d.code " " d.message " | " d.msg)

fn ! moduleText path: String deps: (Map String r/ModuleSummary) viaSource: Bool -> String
  (match (fileReadString path)
    ((err _) (str "(unreadable " path ")"))
    ((ok src) (match (a/parse src)
                ((err e) (str "(parse " path " " e.msg ")"))
                ((ok forms) (str "(module " path "\n"
                                 (str (r/collectSummary forms path)) "\n"
                                 (stringJoin (map diagLine (chk/checkModule forms deps path)) "\n") "\n"
                                 (if viaSource (stringJoin (map diagLine (chk/checkSource src deps path)) "\n") "") ")")))))

fn ! corpusText entry: String -> String
  (match (fileReadString entry)
    ((err _) (str "(unreadable " entry ")"))
    ((ok src) (match (a/parse src)
                ((err e) (str "(parse " entry " " e.msg ")"))
                ((ok forms) (let [(summary (r/collectSummary forms entry))
                                  (importPaths (r/mapValuesList summary.imports))]
                              (match (r/loadModuleDeps! (cons (r/parentDirOf entry) (checkerRoots)) importPaths)
                                ((err e) (str "(deps " entry " " e ")"))
                                ((ok deps) (str (stringJoin (mapKeys deps) "\n") "\n"
                                                (moduleText entry deps true) "\n"
                                                (stringJoin (map (fn [(m r/ModuleSummary)] -> String (str (str m) "\n" (moduleText m.path deps false))) (filter (fn [(m r/ModuleSummary)] -> Bool (not (rewritten? m.path))) (mapValues deps))) "\n")))))))))

fn rewritten? path: String -> Bool
  (or (stringContains? path "asl-checker/src/") (stringContains? path "asl-ir/src/"))

fn ! rootRelative text: String -> String
  (match (realPath ".")
    ((ok root) (stringReplace text (str root "/") ""))
    ((err _) text))

fn digestOf text: String -> String
  (str (stringFromInt64 (fnv1a64 text)) ":" (stringFromInt64 (stringLength text)))

fn truncateLine s: String -> String
  (if (> (stringLength s) 160) (str (optionOr (stringSlice s 0 160) s) "...") s)

fn lineDiffAt i: Int64 wantLines: (List String) gotLines: (List String) -> String
  (let [(w (optionOr (listGet wantLines i) "<eof>"))
        (g (optionOr (listGet gotLines i) "<eof>"))]
    (if (= w g) "" (str "  L" (stringFromInt64 i) " want: " (truncateLine w) "\n  L" (stringFromInt64 i) " got:  " (truncateLine g))))

; (:m :ref CHKFIX :do "short reviewable diff between the stored golden text and the live corpus text: line-by-line, truncated, capped at 6 shown mismatches so a real drift is readable at a glance")
fn shortDiff want: String got: String -> String
  (let [(wantLines (stringSplit want "\n"))
        (gotLines (stringSplit got "\n"))
        (n (max (listLength wantLines) (listLength gotLines)))
        (allDiffs (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (map (fn [(i Int64)] -> String (lineDiffAt i wantLines gotLines)) (range 0 n))))
        (shown (listTake allDiffs 6))]
    (if (listEmpty? allDiffs) ""
      (str (stringFromInt64 (listLength allDiffs)) " line(s) differ of " (stringFromInt64 n) " (showing up to 6):\n" (stringJoin shown "\n"))))

fn ! goldenMismatch entry: String -> String
  (let [(text (rootRelative (corpusText entry)))
        (got (digestOf text))
        (path (goldenFileFor entry))
        (want (match (fileReadString path) ((ok s) s) ((err _) "")))]
    (do (print (str "(quadGolden :entry " entry " :digest \"" got "\")"))
        (assert (> (stringLength text) 10000) (str entry ": the corpus must load, not collapse: " (stringLength text)))
        (if (= want text) "" (str entry ": drifted from " path " (want " (digestOf want) ", got " got ")\n" (shortDiff want text)))))

fn ! runTests -> Bool
  (let [(misses (filter (fn [(m String)] -> Bool (not (stringEmpty? m))) (map goldenMismatch (entries))))]
    (do (assert (listEmpty? misses) (str "checker summaries and diagnostics are byte-identical to their golden fixtures: " (stringJoin misses "; ")))
        true))
