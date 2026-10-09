(module asl-hypergraph/query :x [querySymbolImpact formatImpactReceipt estimateReceiptTokens] :i [(asl-hypergraph/model :a model)])

fn deduplicateStrings xs: (List Str) -> (List Str)
  (fold (fn [(acc (List Str)) (item Str)] -> (List Str) (if (stringEmpty? item) acc (let [(exists (fold (fn [(found Bool) (existing Str)] -> Bool (or found (= item existing))) false acc))] (if exists acc (listAppend acc (list item)))))) (list) xs)

fn takeFirstN n: Int64 xs: (List Str) -> (List Str)
  (if (<= n 0) (list) (mt (listHead xs) ((some h) (cons h (takeFirstN (- n 1) (optionOr (listTail xs) (list))))) ((none) (list))))

fn querySymbolImpact idx: model/HyperIndex targetSym: Str -> model/ImpactReceipt
  (let [(edges idx.edges) (nodes idx.nodes) (nodeOpt (model/findNodeById nodes targetSym)) (directCallEdges (model/findEdgesByTarget edges targetSym (some "calls"))) (directTestEdges (model/findEdgesByTarget edges targetSym (some "tests"))) (directTypeEdges (model/findEdgesBySource edges targetSym (some "types"))) (rawCallers (map (fn [(e model/HyperEdge)] -> Str e.source) directCallEdges)) (rawTests (map (fn [(e model/HyperEdge)] -> Str e.source) directTestEdges)) (rawTypes (map (fn [(e model/HyperEdge)] -> Str e.target) directTypeEdges)) (allCallers (deduplicateStrings rawCallers)) (allTests (deduplicateStrings rawTests)) (allTypes (deduplicateStrings rawTypes)) (callersCount (listLength allCallers)) (testsCount (listLength allTests)) (boundedCallers (if (> callersCount 5) (let [(top5 (takeFirstN 5 allCallers)) (overflow (- callersCount 5)) (label (str "+" (stringFromInt64 overflow) " more callers"))] (listAppend top5 (list label))) allCallers)) (boundedTests (if (> testsCount 3) (let [(top3 (takeFirstN 3 allTests)) (overflow (- testsCount 3)) (label (str "+" (stringFromInt64 overflow) " more tests"))] (listAppend top3 (list label))) allTests)) (status (if (or (some? nodeOpt) (> callersCount 0) (> testsCount 0)) "ok" "not-found"))] (model/makeImpactReceipt targetSym boundedCallers callersCount boundedTests testsCount allTypes status))

fn formatImpactReceipt r: model/ImpactReceipt -> Str
  (let [(quotedCallers (map (fn [(s Str)] -> Str (str "\"" s "\"")) r.callers)) (quotedTests (map (fn [(s Str)] -> Str (str "\"" s "\"")) r.tests)) (quotedTypes (map (fn [(s Str)] -> Str (str "\"" s "\"")) r.types))] (str "(:impact-receipt\n" "  :symbol \"" r.symbol "\"\n" "  :callers [" (stringJoin quotedCallers " ") "]\n" "  :callersCount " (stringFromInt64 r.callersCount) "\n" "  :tests [" (stringJoin quotedTests " ") "]\n" "  :testsCount " (stringFromInt64 r.testsCount) "\n" "  :types [" (stringJoin quotedTypes " ") "]\n" "  :status :" r.status ")\n"))

fn estimateReceiptTokens receiptText: Str -> Int64
  (let [(len (stringLength receiptText))] (/ (+ len 3) 4))
