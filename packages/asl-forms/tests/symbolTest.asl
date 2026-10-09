(module asl-forms/tests/symbolTest :x [runTests] :i [(asl-forms/symbol :a sy) (asl-forms/kernel :a k) (asl-forms/ops :a ops)])

fn fixture! -> String
  (resultOr (fileReadString "asl/packages/asl-forms/tests/fixtures/ws/symbols.asn") "")

fn span! name: String -> String
  (let [(text (fixture!))]
    (mt (pairFirst (sy/findSymbol text name))
      ((none) "none")
      ((some d) (str d.kind " " (stringFromInt64 d.start) "-" (stringFromInt64 d.end) " depth " (stringFromInt64 d.depth)
                     " lines " (stringFromInt64 (sy/lineOf text d.start)) "-" (stringFromInt64 (sy/lineOf text (max d.start (- d.end 1))))))))

fn testParenDefs! -> Bool
  (do
    (assert (= (span! "alpha") "fn 69-135 depth 0 lines 4-6") "a top-level fn spans its form")
    (assert (= (span! "inner") "fn 117-133 depth 2 lines 6-6") "a nested fn records its depth")
    (assert (= (span! "Beta") "schema 137-164 depth 0 lines 8-8") "a schema")
    true)

fn testKeywordDefs! -> Bool
  (do
    (assert (= (span! "read") "op 166-200 depth 0 lines 10-10") "(:op :read ...) names read")
    (assert (= (span! ":read") "op 166-200 depth 0 lines 10-10") "a leading colon is dropped")
    (assert (= (span! "T-1") "task 202-239 depth 0 lines 12-12") "(:task :id \"T-1\") names T-1")
    (assert (= (span! "second") "rule 241-267 depth 0 lines 14-14") "(:rule :id second) names second")
    true)

fn testIndentAndExclusions! -> Bool
  (do
    (assert (= (span! "indented") "defn 269-309 depth 0 lines 16-19") "a column-0 def owns its indented lines across a blank")
    (assert (= (span! "fake") "none") "a definition inside a string is not indexed")
    (assert (= (span! "commentedOut") "none") "a definition inside a comment is not indexed")
    (assert (= (listLength (pairSecond (sy/findSymbol (fixture!) "x"))) 7) "seven definitions are indexed")
    true)

fn testLanguage! -> Bool
  (do
    (assert (= (sy/languageOf! "x/.asl.config.asn") "asn") "a dotted basename keeps its last extension")
    (assert (= (sy/languageOf! "a.ASL") "asl") "extensions compare lower-cased")
    (assert (= (sy/languageOf! "scripts/retiredTool.py") "") "Python source is not a ported forms language")
    true)

fn readLine! form: String -> String
  (optionOr (listHead (ops/runStep! (resultOr (realPath "asl/packages/asl-forms/tests/fixtures/ws") "") 1 form).lines) "")

fn testReadSymbolLines! -> Bool
  (do
    (assert (stringContains? (readLine! "(:read :file \"symbols.asn\" :symbol \"indented\")") ":kind \"defn\" :language \"asn\" :start 16 :end 19 :content") "the read receipt names lines 16 to 19 for the indented def")
    (assert (stringContains? (readLine! "(:read :file \"symbols.asn\" :symbol \"alpha\")") ":start 4 :end 6 :content") "the read receipt names lines 4 to 6 for alpha")
    true)

fn ! runTests -> Bool
  (do
    (assert (testParenDefs!) "testParenDefs")
    (assert (testKeywordDefs!) "testKeywordDefs")
    (assert (testIndentAndExclusions!) "testIndentAndExclusions")
    (assert (testLanguage!) "testLanguage")
    (assert (testReadSymbolLines!) "testReadSymbolLines")
    true)
