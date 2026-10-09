(module aslMem/test :x [runTests testDriverCosineSimilarity] :i [(store :a s) (graph :a g) (compact :a c) (driver :a d) (math :a m)])

fn testVectorSimilarity -> Bool
  (let [(v1 (list 1.0 0.0 0.0)) (v2 (list 1.0 0.0 0.0)) (v3 (list 0.0 1.0 0.0)) (sim1 (m/cosineSimilarity v1 v2)) (sim2 (m/cosineSimilarity v1 v3))] (assert (> sim1 0.99) "Identical vectors similarity must be > 0.99") (assert (< sim2 0.01) "Orthogonal vectors similarity must be < 0.01") true)

fn testDriverCosineSimilarity -> Bool
  (let [(r1 (d/createRecord "doc-1" "First Document" (list 1.0 0.0))) (r2 (d/createRecord "doc-2" "Second Document" (list 0.0 1.0))) (fused (d/fuseRanksRrf (list "doc-1" "doc-2") (list "doc-2" "doc-3") 60))] (assert (= r1.id "doc-1") "Driver VectorRecord id must match") (assert (= r2.content "Second Document") "Driver VectorRecord content must match") (assert (>= (listLength fused) 2) "Fused rank list must contain candidates") (let [(top (optionOr (listHead fused) (d/RrfScore :docId "" :rrfScore 0.0 :denseRank 0 :bm25Rank 0)))] (assert (= top.docId "doc-2") "Doc-2 appearing in both dense and lexical lists must win highest RRF score") (assert (> top.rrfScore 0.0) "Top RRF score must be positive") true))

fn testKnowledgeGraph -> Bool
  (let [(n1 (g/GraphNode :id "n1" :label "entity" :content "Concept A" :timestampEpoch 1700000000 :confidence 0.95)) (n2 (g/GraphNode :id "n2" :label "entity" :content "Concept B" :timestampEpoch 1700001000 :confidence 0.90)) (e1 (g/GraphEdge :sourceId "n1" :targetId "n2" :relation "implements" :weight 1.0 :timestampEpoch 1700001000)) (emptyGraph (g/KnowledgeGraph :nodes (list) :edges (list))) (g1 (g/addNode emptyGraph n1)) (g2 (g/addNode g1 n2)) (g3 (g/addEdge g2 e1)) (neighbors (g/findNeighbors g3 "n1")) (foundNode (g/findNode g3 "n2"))] (assert (= (listLength neighbors) 1) "Neighbors count must be 1") (assert (mt foundNode ((none) false) ((some n) (= n.id "n2"))) "Node n2 must be found") true)

fn testContradictionResolution -> Bool
  (let [(oldFact (g/GraphNode :id "f1" :label "price" :content "$10" :timestampEpoch 1000 :confidence 0.85)) (newFact (g/GraphNode :id "f2" :label "price" :content "$12" :timestampEpoch 2000 :confidence 0.95)) (res (g/resolveContradiction oldFact newFact))] (assert res.hasConflict "Must report conflict") (assert (= res.winnerId "f2") "Fresher fact must win conflict") true)

fn testCompactEncoding -> Bool
  (let [(rec (c/encodeVectorFrame "vec-1" "query test" (list 0.5 0.25 0.125))) (ledger (c/formatCompactLedger (list rec)))] (assert (stringContains? rec.payload "(:vector") "Payload must contain vector frame") (assert (stringContains? ledger "(:vector") "Ledger must contain vector frame") true)

fn testGraphNodeRemoval -> Bool
  (let [(n1 (g/GraphNode :id "a" :label "node" :content "A" :timestampEpoch 1000 :confidence 1.0)) (n2 (g/GraphNode :id "b" :label "node" :content "B" :timestampEpoch 1000 :confidence 1.0)) (e1 (g/GraphEdge :sourceId "a" :targetId "b" :relation "links" :weight 1.0 :timestampEpoch 1000)) (g0 (g/KnowledgeGraph :nodes (list n1 n2) :edges (list e1))) (gAfter (g/removeNode g0 "a"))] (assert (= (listLength gAfter.nodes) 1) "Remaining nodes count must be 1") (assert (= (listLength gAfter.edges) 0) "Remaining edges count must be 0") (assert (= (optionOr (listHead gAfter.nodes) n1).id "b") "Remaining node must be b") true)

fn testVectorDimensionCheck -> Bool
  (let [(store (s/VectorStore :name "dim-test" :dimensions 3 :items (list))) (validItem (s/VectorItem :id "v1" :text "good" :vector (list 1.0 2.0 3.0))) (invalidItem (s/VectorItem :id "v2" :text "bad" :vector (list 1.0 2.0))) (resOk (s/safeInsertItem store validItem)) (resBad (s/safeInsertItem store invalidItem)) (isOk (mt resOk ((some _) true) ((none) false))) (isRejected (mt resBad ((some _) false) ((none) true)))] (assert isOk "Valid item insertion must succeed") (assert isRejected "Mismatched dimension item must be rejected") true)

fn testVectorSlabOperations -> Bool
  (let [(slab0 (s/makeVectorSlab 3 10)) (off0 (s/slabSlotOffset 0 3)) (off2 (s/slabSlotOffset 2 3)) (resOk (s/slabInsert slab0 "vec-0" (list 0.1 0.2 0.3))) (resBad (s/slabInsert slab0 "bad" (list 0.1 0.2))) (isOk (mt resOk ((some s) (and (= s.count 1) (= (listLength s.data) 3))) ((none) false))) (isBad (mt resBad ((some _) false) ((none) true)))] (assert (= off0 0) "Offset 0 must be 0") (assert (= off2 6) "Offset 2 must be 6") (assert isOk "Slab insert valid must succeed") (assert isBad "Slab insert invalid must fail") true)

fn runTests -> Bool
  (fold (fn [(acc Bool) (p Bool)] -> Bool (and acc p)) true (list (testVectorSimilarity) (testDriverCosineSimilarity) (testKnowledgeGraph) (testContradictionResolution) (testCompactEncoding) (testGraphNodeRemoval) (testVectorDimensionCheck) (testVectorSlabOperations)))
