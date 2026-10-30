(module aslMem/spoolSearchTest :x [runTests] :i [(spoolSearch :a ss) (bm25 :a bm)])

fn testSpoolIndexing -> Bool
  (let [(lines (list "building packages/asl-sh" "compiling src/reducer.asl" "compiling src/ansi.asl" "all modules compiled cleanly")) (idx (ss/spoolIndexLines lines))] (assert (= idx.docCount 4) "Index must contain 4 documents") (assert (> idx.avgDocLength 0.0) "Average document length must be positive") (assert (mapHas? idx.termDocCounts "compiling") "Term doc counts must index compiling") (assert (= (optionOr (mapGet idx.termDocCounts "compiling") 0) 2) "Compiling appears in 2 documents") true)

fn testSpoolQueryExact -> Bool
  (let [(lines (list "[INFO] Starting test suite" "[DEBUG] Initializing sandbox" "FAILED tests/unit_test.py::test_math - AssertionError: 1 != 2" "[INFO] Summary: 1 failed")) (idx (ss/spoolIndexLines lines)) (matches (ss/spoolSearchIndex idx lines "AssertionError" 5))] (assert (= (listLength matches) 1) "Exactly 1 line matches AssertionError") (let [(m (optionOr (listHead matches) (ss/SpoolMatch :lineNo 0 :text "" :score 0.0)))] (assert (= m.lineNo 3) "Matching line number must be 3") (assert (stringContains? m.text "FAILED") "Matched text must contain FAILED") (assert (> m.score 0.0) "Match score must be positive")) true)

fn testSpoolQueryRelevance -> Bool
  (let [(lines (list "[INFO] Compiling sources cleanly" "src/main.rs:10:4 - error[E0308]: mismatched types" "warning: unused variable `x`" "error[E0382]: borrow of moved value `v`" "[INFO] Build finished")) (idx (ss/spoolIndexLines lines)) (matches (ss/spoolSearchIndex idx lines "error mismatched types" 2))] (assert (= (listLength matches) 2) "Two lines match error query") (let [(top (optionOr (listHead matches) (ss/SpoolMatch :lineNo 0 :text "" :score 0.0))) (second (optionOr (listGet matches 1) (ss/SpoolMatch :lineNo 0 :text "" :score 0.0)))] (assert (= top.lineNo 2) "Top match must be line 2 containing mismatched types") (assert (> top.score second.score) "Top match must outscore second match") (assert (stringContains? top.text "mismatched") "Top match text must contain mismatched")) true)

fn testSpoolQueryNoMatch -> Bool
  (let [(lines (list "line one" "line two" "line three")) (idx (ss/spoolIndexLines lines)) (matches (ss/spoolSearchIndex idx lines "nonexistentkeywordxyz" 5))] (assert (listEmpty? matches) "Absent terms must produce zero matches") (assert (= (listLength matches) 0) "Match length must be 0") true)

fn testSpoolFormatMatches -> Bool
  (let [(m1 (ss/SpoolMatch :lineNo 12 :text "syntax error" :score 1.5)) (m2 (ss/SpoolMatch :lineNo 45 :text "fatal failure" :score 1.2)) (formatted (ss/formatSpoolMatches (list m1 m2))) (emptyFmt (ss/formatSpoolMatches (list)))] (assert (stringContains? formatted "L12: syntax error") "Formatted output must contain L12") (assert (stringContains? formatted "L45: fatal failure") "Formatted output must contain L45") (assert (= emptyFmt "Zero matches found.") "Empty format must report zero matches") true)

fn testSpoolDirectQuery -> Bool
  (let [(raw (str "Step 1: Init\n" "Step 2: Processing batch\n" "Step 3: Fatal panic during allocation\n" "Step 4: Cleanup\n")) (matches (ss/spoolQueryBm25 raw "panic allocation" 1))] (assert (= (listLength matches) 1) "Direct query must find 1 match") (let [(m (optionOr (listHead matches) (ss/SpoolMatch :lineNo 0 :text "" :score 0.0)))] (assert (= m.lineNo 3) "Matched line must be line 3") (assert (stringContains? m.text "Fatal panic") "Matched text must contain Fatal panic") (assert (> m.score 0.0) "Score must be positive")) true)

fn runTests -> Bool
  (and (testSpoolIndexing) (and (testSpoolQueryExact) (and (testSpoolQueryRelevance) (and (testSpoolQueryNoMatch) (and (testSpoolFormatMatches) (testSpoolDirectQuery))))))
