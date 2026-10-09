(module aslIntel/textScan :x [TextSection TextDocOutline TextMatchSlice scanDocOutline extractDocSection searchDocSnippets formatDocOutlineAsn formatSectionAsn] :i [])

(schema TextSection (:f title Str) (:f level I64) (:f startLine I64) (:f endLine I64) (:f linesCount I64))

(schema TextDocOutline (:f filePath Str) (:f totalLines I64) (:f sections (List TextSection)))

(schema TextMatchSlice (:f lineNumber I64) (:f preview Str))

fn parseHeaderLevel line: Str -> I64
  (let [(trimmed (stringTrim line))] (cond ((stringStartsWith? trimmed "#### ") 4) ((stringStartsWith? trimmed "### ") 3) ((stringStartsWith? trimmed "## ") 2) ((stringStartsWith? trimmed "# ") 1) (else 0)))

fn extractHeaderTitle line: Str lvl: I64 -> Str
  (let [(trimmed (stringTrim line))] (cond ((= lvl 1) (stringTrim (optionOr (stringSlice trimmed 2 (stringLength trimmed)) ""))) ((= lvl 2) (stringTrim (optionOr (stringSlice trimmed 3 (stringLength trimmed)) ""))) ((= lvl 3) (stringTrim (optionOr (stringSlice trimmed 4 (stringLength trimmed)) ""))) ((= lvl 4) (stringTrim (optionOr (stringSlice trimmed 5 (stringLength trimmed)) ""))) (else trimmed)))

fn indexLines lines: (List Str) -> (List (Pair I64 Str))
  (pairSecond (fold (fn [(acc (Pair I64 (List (Pair I64 Str)))) (x Str)] -> (Pair I64 (List (Pair I64 Str))) (let [(idx (pairFirst acc)) (items (pairSecond acc))] (pair (+ idx 1) (listAppend items (list (pair idx x)))))) (pair 0 (list)) lines))

fn scanDocOutline content: Str filePath: Str -> TextDocOutline
  (let [(lines (stringSplit content "\n")) (totLines (listLength lines))] (if (<= totLines 0) (TextDocOutline :filePath filePath :totalLines 0 :sections (list)) (let [(secs0 (list)) (indexedLines (indexLines lines)) (foundSecs (fold (fn [(acc (List TextSection)) (p (Pair I64 Str))] -> (List TextSection) (let [(idx (pairFirst p)) (line (pairSecond p)) (lvl (parseHeaderLevel line))] (if (> lvl 0) (let [(title (extractHeaderTitle line lvl)) (lineNo (+ idx 1))] (listAppend acc (list (TextSection :title title :level lvl :startLine lineNo :endLine totLines :linesCount 1)))) acc))) secs0 indexedLines))] (TextDocOutline :filePath filePath :totalLines totLines :sections foundSecs))))

fn extractDocSection content: Str sectionTitle: Str -> (Option Str)
  (let [(lines (stringSplit content "\n")) (inSection false) (captured (list)) (targetLow (stringLower sectionTitle)) (res (fold (fn [(acc (Pair Bool (Pair I64 (List Str)))) (line Str)] -> (Pair Bool (Pair I64 (List Str))) (let [(active (pairFirst acc)) (inner (pairSecond acc)) (targetLvl (pairFirst inner)) (items (pairSecond inner)) (lvl (parseHeaderLevel line))] (if active (if (and (> lvl 0) (<= lvl targetLvl)) (pair false (pair targetLvl items)) (pair true (pair targetLvl (listAppend items (list line))))) (if (> lvl 0) (let [(title (stringLower (extractHeaderTitle line lvl)))] (if (stringContains? title targetLow) (pair true (pair lvl (listAppend items (list line)))) (pair false (pair 0 items)))) (pair false (pair 0 items)))))) (pair false (pair 0 captured)) lines))] (let [(finalItems (pairSecond (pairSecond res)))] (if (listEmpty? finalItems) (none) (some (stringJoin finalItems "\n")))))

fn searchDocSnippets content: Str query: Str -> (List TextMatchSlice)
  (let [(lines (stringSplit content "\n")) (queryLow (stringLower query)) (indexed (indexLines lines))] (fold (fn [(acc (List TextMatchSlice)) (p (Pair I64 Str))] -> (List TextMatchSlice) (let [(idx (pairFirst p)) (line (pairSecond p)) (lineLow (stringLower line))] (if (stringContains? lineLow queryLow) (listAppend acc (list (TextMatchSlice :lineNumber (+ idx 1) :preview (stringTrim line)))) acc))) (list) indexed))

fn formatDocOutlineAsn outline: TextDocOutline -> Str
  (let [(base (str "(:doc-outline :path \"" outline.filePath "\" :lines " (stringFromInt64 outline.totalLines) " :sections [")) (secStr (fold (fn [(acc Str) (sec TextSection)] -> Str (str acc "(:h" (stringFromInt64 sec.level) " :title \"" sec.title "\"" " :line " (stringFromInt64 sec.startLine) ") ")) base outline.sections))] (str (stringTrim secStr) "])"))

fn formatSectionAsn filePath: Str sectionTitle: Str sectionBody: Str -> Str
  (str "(:doc-section :path \"" filePath "\" :title \"" sectionTitle "\" :body \"" sectionBody "\")")
