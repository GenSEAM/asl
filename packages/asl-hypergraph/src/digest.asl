(module asl-hypergraph/digest :x [PerceptionDigest makePerceptionDigest generateImpactDigest compactPerceptionReceipt estimateTokenCount] :i [(asl-hypergraph/model :a model)])

(schema PerceptionDigest (:f symbol Str) (:f totalCallers Int64) (:f totalTests Int64) (:f estimatedTokens Int64) (:f isBounded Bool) (:f receiptStr Str))

fn makePerceptionDigest sym: Str callers: Int64 tests: Int64 tokens: Int64 bounded: Bool receipt: Str -> PerceptionDigest
  (PerceptionDigest :symbol sym :totalCallers callers :totalTests tests :estimatedTokens tokens :isBounded bounded :receiptStr receipt)

fn deduplicate xs: (List Str) -> (List Str)
  (fold (fn [(acc (List Str)) (item Str)] -> (List Str) (if (stringEmpty? item) acc (let [(exists (fold (fn [(found Bool) (existing Str)] -> Bool (or found (= item existing))) false acc))] (if exists acc (listAppend acc (list item)))))) (list) xs)

fn takeN n: Int64 xs: (List Str) -> (List Str)
  (if (<= n 0) (list) (mt (listHead xs) ((some h) (cons h (takeN (- n 1) (optionOr (listTail xs) (list))))) ((none) (list))))

fn estimateTokenCount s: Str -> Int64
  (let [(chars (stringLength s))] (if (<= chars 0) 0 (let [(est (/ (+ chars 3) 4))] (if (<= est 0) 1 est))))

fn compactPerceptionReceipt rawReceipt: Str tokenBudget: Int64 -> Str
  (let [(len (stringLength rawReceipt))] (compressSpaces rawReceipt 0 len false ""))

fn compressSpaces s: Str idx: Int64 len: Int64 prevSpace: Bool acc: Str -> Str
  (if (>= idx len) acc (let [(ch (mt (stringSlice s idx (+ idx 1)) ((some c) c) ((none) "")))] (if (or (= ch " ") (or (= ch "\n") (= ch "\t"))) (if prevSpace (compressSpaces s (+ idx 1) len true acc) (compressSpaces s (+ idx 1) len true (str acc " "))) (compressSpaces s (+ idx 1) len false (str acc ch)))))

fn formatCallersList callers: (List Str) -> Str
  (if (listEmpty? callers) "[]" (let [(inner (fold (fn [(acc Str) (c Str)] -> Str (if (stringEmpty? acc) (str "\"" c "\"") (str acc " \"" c "\""))) "" callers))] (str "[" inner "]")))

fn filterMatchingEdges edges: (List model/HyperEdge) targetSym: Str rel: Str -> (List model/HyperEdge)
  (fold (fn [(acc (List model/HyperEdge)) (edge model/HyperEdge)] -> (List model/HyperEdge) (if (or (and (= edge.target targetSym) (= edge.relation rel)) (and (= edge.relation targetSym) (= edge.target rel))) (listAppend acc (list edge)) (let [(cleanTarget (fold (fn [(acc Str) (s Str)] -> Str s) targetSym (stringSplit targetSym ":")))] (if (or (and (or (= edge.target cleanTarget) (stringEndsWith? edge.target (str ":" cleanTarget))) (= edge.relation rel)) (and (or (= edge.relation cleanTarget) (stringEndsWith? edge.relation (str ":" cleanTarget))) (= edge.target rel))) (listAppend acc (list edge)) acc)))) (list) edges)

fn getCandidateEdges idx: model/HyperIndex targetSym: Str rel: Str -> (List model/HyperEdge)
  (filterMatchingEdges idx.edges targetSym rel)

fn generateImpactDigest idx: model/HyperIndex targetSym: Str tokenBudget: Int64 -> PerceptionDigest
  (let [(directCallEdges (getCandidateEdges idx targetSym "calls")) (directTestEdges (getCandidateEdges idx targetSym "tests")) (rawCallers (map (fn [(e model/HyperEdge)] -> Str e.source) directCallEdges)) (rawTests (map (fn [(e model/HyperEdge)] -> Str e.source) directTestEdges)) (allCallers (deduplicate rawCallers)) (allTests (deduplicate rawTests)) (callersCount (listLength allCallers)) (testsCount (listLength allTests)) (boundedCallers (if (> callersCount 5) (let [(top5 (takeN 5 allCallers)) (overflow (- callersCount 5)) (label (str "+" (stringFromInt64 overflow) " more callers"))] (listAppend top5 (list label))) allCallers)) (boundedTests (if (> testsCount 3) (let [(top3 (takeN 3 allTests)) (overflow (- testsCount 3)) (label (str "+" (stringFromInt64 overflow) " more tests"))] (listAppend top3 (list label))) allTests)) (callersStr (formatCallersList boundedCallers)) (testsStr (formatCallersList boundedTests)) (receipt (str "(:impact-digest :target \"" targetSym "\" :callers " callersStr " :tests " testsStr ")\n")) (tokens (estimateTokenCount receipt)) (bounded (<= tokens tokenBudget))] (makePerceptionDigest targetSym callersCount testsCount tokens bounded receipt))
