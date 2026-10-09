(module aslHarness/compactor :x [stripCodeFences truncateOutput compactHistory extractSexpr compactReceipt compactAtWatermark] :i [])

fn stripCodeFences text: Str -> Str
  (let [(s1 (stringReplace text "```asl\n" "")) (s2 (stringReplace s1 "```asl" "")) (s3 (stringReplace s2 "```lisp\n" "")) (s4 (stringReplace s3 "```lisp" "")) (s5 (stringReplace s4 "```scheme\n" "")) (s6 (stringReplace s5 "```scheme" "")) (s7 (stringReplace s6 "```\n" "")) (s8 (stringReplace s7 "```" ""))] (stringTrim s8))

fn truncateOutput out: Str maxLines: I64 -> Str
  (let [(lines (stringSplit out "\n")) (total (listLength lines))] (if (<= total maxLines) out (let [(headCount (/ maxLines 2)) (tailCount (/ maxLines 2)) (headLines (listTake lines headCount)) (tailLines (listDrop lines (- total tailCount))) (omittedCount (- total (+ headCount tailCount))) (notice (str "\n... [" (stringFromInt64 omittedCount) " lines omitted] ...\n")) (headStr (stringJoin headLines "\n")) (tailStr (stringJoin tailLines "\n"))] (str headStr notice tailStr))))

fn extractSexpr text: Str -> Str
  (let [(clean (stripCodeFences text))] (if (stringStartsWith? clean "(") clean (let [(firstParen (stringIndexOf clean "("))] (mt firstParen ((some idx) (optionOr (stringSlice clean idx (stringLength clean)) clean)) ((none) clean)))))

fn compactReceipt entry: Str -> Str
  (cond ((stringContains? entry "ast-patch") "[Turn: ast-patch executed cleanly]") ((stringContains? entry "fs-write") "[Turn: fs-write completed]") ((stringContains? entry "fs-read") "[Turn: fs-read file cached]") ((stringContains? entry "exec-cmd") "[Turn: exec-cmd verified gate]") (else (str "[Turn: " (optionOr (stringSlice entry 0 (min 40 (stringLength entry))) entry) "...]")))

fn compactHistory history: (List Str) keepRecent: I64 -> (List Str)
  (let [(total (listLength history))] (if (<= total keepRecent) history (let [(compactCount (- total keepRecent)) (older (listTake history compactCount)) (recent (listDrop history compactCount)) (compactedOlder (map compactReceipt older))] (listAppend compactedOlder recent))))

fn compactAtWatermark history: (List Str) currentTokens: I64 budget: I64 -> (List Str)
  (if (<= budget 0) history (let [(pct (/ (* currentTokens 100) budget))] (cond ((>= pct 80) (compactHistory history 2)) ((>= pct 60) (compactHistory history 5)) (else history))))
