(module asl-hypergraph/query
  :d "Sub-80-token blast radius impact query engine and receipt formatter under ADR D94."
  :x [querySymbolImpact
      formatImpactReceipt
      estimateReceiptTokens]
  :i [(asl-hypergraph/model :a model)])

(df deduplicateStrings [(xs (List Str))] -> (List Str)
  :d "Deduplicates a list of strings preserving initial order."
  (fold (fn [(acc (List Str)) (item Str)] -> (List Str)
          (if (string-empty? item)
              acc
              (let [(exists (fold (fn [(found Bool) (existing Str)] -> Bool
                                    (or found (= item existing)))
                                  false
                                  acc))]
                (if exists acc (list-append acc (list item))))))
        (list)
        xs))

(df takeFirstN [(n Int64) (xs (List Str))] -> (List Str)
  :d "Takes first n items from a list."
  (if (<= n 0)
      (list)
      (mt (list-head xs)
        ((some h) (list-cons h (takeFirstN (- n 1) (option-or (list-tail xs) (list)))))
        ((none) (list)))))

(df querySymbolImpact [(idx model/HyperIndex) (targetSym Str)] -> model/ImpactReceipt
  :d "Queries inbound callers, test suites, and type references, bounding results under 80 tokens."
  (let [(edges (.-edges idx))
        (nodes (.-nodes idx))
        (nodeOpt (model/findNodeById nodes targetSym))
        (directCallEdges (model/findEdgesByTarget edges targetSym (some "calls")))
        (directTestEdges (model/findEdgesByTarget edges targetSym (some "tests")))
        (directTypeEdges (model/findEdgesBySource edges targetSym (some "types")))
        (rawCallers (map (fn [(e model/HyperEdge)] -> Str (.-source e)) directCallEdges))
        (rawTests (map (fn [(e model/HyperEdge)] -> Str (.-source e)) directTestEdges))
        (rawTypes (map (fn [(e model/HyperEdge)] -> Str (.-target e)) directTypeEdges))
        (allCallers (deduplicateStrings rawCallers))
        (allTests (deduplicateStrings rawTests))
        (allTypes (deduplicateStrings rawTypes))
        (callersCount (list-length allCallers))
        (testsCount (list-length allTests))
        (boundedCallers (if (> callersCount 5)
                            (let [(top5 (takeFirstN 5 allCallers))
                                  (overflow (- callersCount 5))
                                  (label (str "+" (string-from-int64 overflow) " more callers"))]
                              (list-append top5 (list label)))
                            allCallers))
        (boundedTests (if (> testsCount 3)
                          (let [(top3 (takeFirstN 3 allTests))
                                (overflow (- testsCount 3))
                                (label (str "+" (string-from-int64 overflow) " more tests"))]
                            (list-append top3 (list label)))
                          allTests))
        (status (if (or (option-some? nodeOpt) (> callersCount 0) (> testsCount 0))
                    "ok"
                    "not-found"))]
    (model/makeImpactReceipt targetSym boundedCallers callersCount boundedTests testsCount allTypes status)))

(df formatImpactReceipt [(r model/ImpactReceipt)] -> Str
  :d "Formats an ImpactReceipt into compact sub-80-token ASN representation."
  (let [(quotedCallers (map (fn [(s Str)] -> Str (str "\"" s "\"")) (.-callers r)))
        (quotedTests (map (fn [(s Str)] -> Str (str "\"" s "\"")) (.-tests r)))
        (quotedTypes (map (fn [(s Str)] -> Str (str "\"" s "\"")) (.-types r)))]
    (str "(:impact-receipt\n"
         "  :symbol \"" (.-symbol r) "\"\n"
         "  :callers [" (string-join quotedCallers " ") "]\n"
         "  :callersCount " (string-from-int64 (.-callersCount r)) "\n"
         "  :tests [" (string-join quotedTests " ") "]\n"
         "  :testsCount " (string-from-int64 (.-testsCount r)) "\n"
         "  :types [" (string-join quotedTypes " ") "]\n"
         "  :status :" (.-status r) ")\n")))

(df estimateReceiptTokens [(receiptText Str)] -> Int64
  :d "Estimates token density of formatted receipt text."
  (let [(len (string-length receiptText))]
    (/ (+ len 3) 4)))
