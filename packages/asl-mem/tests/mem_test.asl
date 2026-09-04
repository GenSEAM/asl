(module asl-mem/test
  :d "Unit tests for in-memory vector database, graph intelligence, and compact encoding in ASL"
  :x [run-tests]
  :i [(store :a s)
      (graph :a g)
      (compact :a c)])

(df test-vector-similarity [] -> Bool
  :d "Verifies cosine similarity calculation and vector normalization."
  (let [(v1 (list 1.0 0.0 0.0))
        (v2 (list 1.0 0.0 0.0))
        (v3 (list 0.0 1.0 0.0))
        (sim1 (s/cosine-similarity v1 v2))
        (sim2 (s/cosine-similarity v1 v3))]
    (and (> sim1 0.99)
         (< sim2 0.01))))

(df test-knowledge-graph [] -> Bool
  :d "Verifies graph construction, edge retrieval, and neighbor queries."
  (let [(n1 (g/GraphNode :id "n1" :label "entity" :content "Concept A" :timestamp-epoch 1700000000 :confidence 0.95))
        (n2 (g/GraphNode :id "n2" :label "entity" :content "Concept B" :timestamp-epoch 1700001000 :confidence 0.90))
        (e1 (g/GraphEdge :source-id "n1" :target-id "n2" :relation "implements" :weight 1.0 :timestamp-epoch 1700001000))
        (empty-graph (g/KnowledgeGraph :nodes (list) :edges (list)))
        (g1 (g/add-node empty-graph n1))
        (g2 (g/add-node g1 n2))
        (g3 (g/add-edge g2 e1))
        (neighbors (g/find-neighbors g3 "n1"))
        (found-node (g/find-node g3 "n2"))]
    (and (= (list-length neighbors) 1)
         (mt found-node
           ((none) false)
           ((some n) (= (.-id n) "n2"))))))

(df test-contradiction-resolution [] -> Bool
  :d "Verifies automatic conflict resolution favoring fresher authoritative facts."
  (let [(old-fact (g/GraphNode :id "f1" :label "price" :content "$10" :timestamp-epoch 1000 :confidence 0.85))
        (new-fact (g/GraphNode :id "f2" :label "price" :content "$12" :timestamp-epoch 2000 :confidence 0.95))
        (res (g/resolve-contradiction old-fact new-fact))]
    (and (.-has-conflict res)
         (= (.-winner-id res) "f2"))))

(df test-compact-encoding [] -> Bool
  :d "Verifies ASN frame serialization and ledger compilation."
  (let [(rec (c/encode-vector-frame "vec-1" "query test" (list 0.5 0.25 0.125)))
        (ledger (c/format-compact-ledger (list rec)))]
    (and (string-contains? (.-payload rec) "@v:{vec-1|query test|[0.5,0.25,0.125]}")
         (string-contains? ledger "@v:{vec-1"))))

(df run-tests [] -> Bool
  :d "Runs all asl-mem unit tests."
  (fold (fn [(acc Bool) (p Bool)] -> Bool (and acc p))
        true
        (list (test-vector-similarity)
              (test-knowledge-graph)
              (test-contradiction-resolution)
              (test-compact-encoding))))

