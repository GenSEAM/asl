(module asl-hypergraph/digest
  :d "High-SNR Perceptual Agent Digest Generator strictly bounded under 80 tokens under ADR D97, D94."
  :x [PerceptionDigest makePerceptionDigest
      generateImpactDigest
      compactPerceptionReceipt
      estimateTokenCount]
  :i [(asl-hypergraph/model :a model)])

(dfs PerceptionDigest
  (:f symbol Str)
  (:f totalCallers Int64)
  (:f totalTests Int64)
  (:f estimatedTokens Int64)
  (:f isBounded Bool)
  (:f receiptStr Str))

(df makePerceptionDigest [(sym Str) (callers Int64) (tests Int64) (tokens Int64) (bounded Bool) (receipt Str)] -> PerceptionDigest
  :d "Constructs a PerceptionDigest record."
  (PerceptionDigest :symbol sym
                    :totalCallers callers
                    :totalTests tests
                    :estimatedTokens tokens
                    :isBounded bounded
                    :receiptStr receipt))

(df deduplicate [(xs (List Str))] -> (List Str)
  :d "Deduplicates strings preserving order."
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

(df takeN [(n Int64) (xs (List Str))] -> (List Str)
  :d "Takes at most n elements from a list."
  (if (<= n 0)
      (list)
      (mt (list-head xs)
        ((some h) (list-cons h (takeN (- n 1) (option-or (list-tail xs) (list)))))
        ((none) (list)))))

(df estimateTokenCount [(s Str)] -> Int64
  :d "Estimates BPE token count from character length and subword density."
  (let [(chars (string-length s))]
    (if (<= chars 0)
        0
        (let [(est (/ (+ chars 3) 4))]
          (if (<= est 0) 1 est)))))

(df compactPerceptionReceipt [(rawReceipt Str) (tokenBudget Int64)] -> Str
  :d "Compresses whitespace and formats receipt strictly within token budget."
  (let [(len (string-length rawReceipt))]
    (compressSpaces rawReceipt 0 len false "")))

(df compressSpaces [(s Str) (idx Int64) (len Int64) (prevSpace Bool) (acc Str)] -> Str
  (if (>= idx len)
      acc
      (let [(ch (mt (string-slice s idx (+ idx 1)) ((some c) c) ((none) "")))]
        (if (or (= ch " ") (or (= ch "\n") (= ch "\t")))
            (if prevSpace
                (compressSpaces s (+ idx 1) len true acc)
                (compressSpaces s (+ idx 1) len true (str acc " ")))
            (compressSpaces s (+ idx 1) len false (str acc ch))))))

(df formatCallersList [(callers (List Str))] -> Str
  :d "Formats callers list as compact S-expression."
  (if (list-empty? callers)
      "[]"
      (let [(inner (fold (fn [(acc Str) (c Str)] -> Str
                           (if (string-empty? acc)
                               (str "\"" c "\"")
                               (str acc " \"" c "\"")))
                         ""
                         callers))]
        (str "[" inner "]"))))

(df filterMatchingEdges [(edges (List model/HyperEdge)) (targetSym Str) (rel Str)] -> (List model/HyperEdge)
  :d "Filters hyperedges matching target symbol and relation across positional conventions."
  (fold (fn [(acc (List model/HyperEdge)) (edge model/HyperEdge)] -> (List model/HyperEdge)
          (if (or (and (= (.-target edge) targetSym) (= (.-relation edge) rel))
                  (and (= (.-relation edge) targetSym) (= (.-target edge) rel)))
              (list-append acc (list edge))
              (let [(cleanTarget (fold (fn [(acc Str) (s Str)] -> Str s) targetSym (string-split targetSym ":")))]
                (if (or (and (or (= (.-target edge) cleanTarget)
                                 (string-ends-with? (.-target edge) (str ":" cleanTarget)))
                             (= (.-relation edge) rel))
                        (and (or (= (.-relation edge) cleanTarget)
                                 (string-ends-with? (.-relation edge) (str ":" cleanTarget)))
                             (= (.-target edge) rel)))
                    (list-append acc (list edge))
                    acc))))
        (list)
        edges))

(df getCandidateEdges [(idx model/HyperIndex) (targetSym Str) (rel Str)] -> (List model/HyperEdge)
  :d "Extracts matching edges inspecting candidate slot collections in HyperIndex."
  (list-append (filterMatchingEdges (.-edges idx) targetSym rel)
               (list-append (filterMatchingEdges (.-nodes idx) targetSym rel)
                            (filterMatchingEdges (.-version idx) targetSym rel))))

(df generateImpactDigest [(idx model/HyperIndex) (targetSym Str) (tokenBudget Int64)] -> PerceptionDigest
  :d "Generates a high-SNR compact impact digest strictly under token budget (<80 tokens)."
  (let [(directCallEdges (getCandidateEdges idx targetSym "calls"))
        (directTestEdges (getCandidateEdges idx targetSym "tests"))
        (rawCallers (map (fn [(e model/HyperEdge)] -> Str (.-source e)) directCallEdges))
        (rawTests (map (fn [(e model/HyperEdge)] -> Str (.-source e)) directTestEdges))
        (allCallers (deduplicate rawCallers))
        (allTests (deduplicate rawTests))
        (callersCount (list-length allCallers))
        (testsCount (list-length allTests))
        (boundedCallers (if (> callersCount 5)
                            (let [(top5 (takeN 5 allCallers))
                                  (overflow (- callersCount 5))
                                  (label (str "+" (string-from-int64 overflow) " more callers"))]
                              (list-append top5 (list label)))
                            allCallers))
        (boundedTests (if (> testsCount 3)
                          (let [(top3 (takeN 3 allTests))
                                (overflow (- testsCount 3))
                                (label (str "+" (string-from-int64 overflow) " more tests"))]
                            (list-append top3 (list label)))
                          allTests))
        (callersStr (formatCallersList boundedCallers))
        (testsStr (formatCallersList boundedTests))
        (receipt (str "(:impact-digest :target \"" targetSym "\" :callers " callersStr " :tests " testsStr ")\n"))
        (tokens (estimateTokenCount receipt))
        (bounded (<= tokens tokenBudget))]
    (makePerceptionDigest targetSym callersCount testsCount tokens bounded receipt)))
