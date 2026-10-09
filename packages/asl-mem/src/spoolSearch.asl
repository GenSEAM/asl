(module aslMem/spoolSearch :x [SpoolMatch spoolIndexLines spoolQueryBm25 spoolSearchIndex formatSpoolMatches] :i [(bm25 :a bm)])

(schema SpoolMatch (:f lineNo I64) (:f text Str) (:f score F64))

fn makeLineDoc line: Str idx: I64 -> bm/Bm25Doc
  (let [(lineNo (+ idx 1)) (terms (bm/tokenizeTerms line)) (tLen (listLength terms)) (len (if (= tLen 0) 1 tLen))] (bm/Bm25Doc :id (stringFromInt64 lineNo) :terms terms :length len))

fn indexLinesLoop lines: (List Str) idx: I64 acc: (List bm/Bm25Doc) -> (List bm/Bm25Doc)
  (if (listEmpty? lines) acc (let [(l (optionOr (listHead lines) "")) (rest (optionOr (listTail lines) (list))) (doc (makeLineDoc l idx))] (indexLinesLoop rest (+ idx 1) (listAppend acc (list doc)))))

fn spoolIndexLines lines: (List Str) -> bm/Bm25Index
  (let [(docs (indexLinesLoop lines 0 (list)))] (bm/makeBm25Index docs))

fn buildMatchesLoop scores: (List bm/Bm25Score) lines: (List Str) acc: (List SpoolMatch) -> (List SpoolMatch)
  (if (listEmpty? scores) acc (let [(s (optionOr (listHead scores) (bm/Bm25Score :docId "" :score 0.0))) (rest (optionOr (listTail scores) (list))) (scoreVal s.score)] (if (<= scoreVal 0.0) (buildMatchesLoop rest lines acc) (let [(lineNo (optionOr (stringToInt64 s.docId) 0)) (text (if (> lineNo 0) (optionOr (listGet lines (- lineNo 1)) "") "")) (m (SpoolMatch :lineNo lineNo :text text :score scoreVal))] (buildMatchesLoop rest lines (listAppend acc (list m)))))))

fn spoolSearchIndex index: bm/Bm25Index lines: (List Str) query: Str topK: I64 -> (List SpoolMatch)
  (let [(scores (bm/rankBm25 index query topK))] (buildMatchesLoop scores lines (list)))

fn spoolQueryBm25 rawText: Str query: Str topK: I64 -> (List SpoolMatch)
  (if (stringEmpty? (stringTrim rawText)) (list) (let [(norm (stringReplace rawText "\r\n" "\n")) (lines (stringSplit norm "\n")) (index (spoolIndexLines lines))] (spoolSearchIndex index lines query topK)))

fn formatSpoolMatches matches: (List SpoolMatch) -> Str
  (if (listEmpty? matches) "Zero matches found." (let [(rows (map (fn [(m SpoolMatch)] -> Str (str "  L" (stringFromInt64 m.lineNo) ": " m.text)) matches))] (stringJoin rows "\n")))
