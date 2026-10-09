(module aslMem/subtreeCache :x [SubtreeEntry SubtreeCache indexSubtrees lookupSubtree reconcileIncrementalDiff] :i [(vfs :a v)])

(schema SubtreeEntry (:f hash Str) (:f name Str) (:f kind Str) (:f astNode Str))

(schema SubtreeCache (:f entries (Map Str SubtreeEntry)))

fn computeSubtreeHash content: Str -> Str
  (let [(chars (stringChars content)) (len (stringLength content)) (h (fold (fn [(acc I64) (ch Str)] -> I64 (mod (+ (* acc 31) (v/charToCode ch)) 2147483647)) 5381 chars))] (str "cas-" (stringFromInt64 h) "-" (stringFromInt64 len)))

fn countParensLoop chars: (List Str) depth: I64 -> I64
  (if (listEmpty? chars) depth (let [(c (optionOr (listHead chars) "")) (rest (optionOr (listTail chars) (list))) (delta (cond ((= c "(") 1) ((= c ")") -1) (else 0)))] (countParensLoop rest (+ depth delta))))

fn netParens line: Str -> I64
  (countParensLoop (stringChars line) 0)

fn extractKindAndName form: Str -> (List Str)
  (let [(trimmed (stringTrim form)) (afterP (if (stringStartsWith? trimmed "(") (optionOr (stringSlice trimmed 1 (stringLength trimmed)) "") trimmed)) (words (stringSplit (stringTrim afterP) " ")) (cleanWords (filter (fn [(w Str)] -> Bool (> (stringLength w) 0)) words)) (k (optionOr (listGet cleanWords 0) "unknown")) (n (optionOr (listGet cleanWords 1) "anonymous"))] (list k n))

fn makeSubtreeEntry formText: Str -> SubtreeEntry
  (let [(kn (extractKindAndName formText)) (k (optionOr (listGet kn 0) "unknown")) (n (optionOr (listGet kn 1) "anonymous")) (h (computeSubtreeHash formText))] (SubtreeEntry :hash h :name n :kind k :astNode formText))

fn parseFormsLoop lines: (List Str) curLines: (List Str) curDepth: I64 acc: (List SubtreeEntry) -> (List SubtreeEntry)
  (if (listEmpty? lines) (if (listEmpty? curLines) acc (let [(entry (makeSubtreeEntry (stringJoin curLines "\n")))] (listAppend acc (list entry)))) (let [(line (optionOr (listHead lines) "")) (rest (optionOr (listTail lines) (list))) (trimmed (stringTrim line))] (if (listEmpty? curLines) (if (stringStartsWith? trimmed "(") (let [(np (netParens trimmed))] (if (<= np 0) (let [(entry (makeSubtreeEntry trimmed))] (parseFormsLoop rest (list) 0 (listAppend acc (list entry)))) (parseFormsLoop rest (list line) np acc))) (parseFormsLoop rest (list) 0 acc)) (let [(np (netParens line)) (newDepth (+ curDepth np)) (newLines (listAppend curLines (list line)))] (if (<= newDepth 0) (let [(entry (makeSubtreeEntry (stringJoin newLines "\n")))] (parseFormsLoop rest (list) 0 (listAppend acc (list entry)))) (parseFormsLoop rest newLines newDepth acc))))))

fn buildCacheMap entries: (List SubtreeEntry) acc: (Map Str SubtreeEntry) -> (Map Str SubtreeEntry)
  (if (listEmpty? entries) acc (let [(entry (optionOr (listHead entries) (SubtreeEntry :hash "" :name "" :kind "" :astNode ""))) (rest (optionOr (listTail entries) (list))) (h entry.hash) (nextAcc (mapSet acc h entry))] (buildCacheMap rest nextAcc)))

fn indexSubtrees source: Str -> SubtreeCache
  (let [(lines (stringSplit source "\n")) (entries (parseFormsLoop lines (list) 0 (list))) (entriesMap (buildCacheMap entries (mapEmpty)))] (SubtreeCache :entries entriesMap))

fn lookupSubtree cache: SubtreeCache hash: Str -> (Option SubtreeEntry)
  (mapGet cache.entries hash)

fn findUnchangedEntries entries: (List SubtreeEntry) oldCache: SubtreeCache acc: (List SubtreeEntry) -> (List SubtreeEntry)
  (if (listEmpty? entries) acc (let [(entry (optionOr (listHead entries) (SubtreeEntry :hash "" :name "" :kind "" :astNode ""))) (rest (optionOr (listTail entries) (list))) (h entry.hash) (cached (lookupSubtree oldCache h))] (mt cached ((some oldEntry) (findUnchangedEntries rest oldCache (listAppend acc (list oldEntry)))) ((none) (findUnchangedEntries rest oldCache acc)))))

fn reconcileIncrementalDiff oldCache: SubtreeCache newSource: Str -> (Pair (List SubtreeEntry) SubtreeCache)
  (let [(newCache (indexSubtrees newSource)) (allEntries (mapValues newCache.entries)) (unchanged (findUnchangedEntries allEntries oldCache (list)))] (pair unchanged newCache))
