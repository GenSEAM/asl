(module asl-mem/store
  :doc "In-memory vector database and cosine similarity in ASL Nano"
  :export [VectorItem VectorStore cosine-similarity])

(dfs VectorItem
  (:field id Str "id")
  (:field text Str "text payload")
  (:field vector (List F64) "embedding vector"))

(dfs VectorStore
  (:field name Str "store name")
  (:field dimensions I64 "vector dimensions")
  (:field items (List VectorItem) "stored items"))

(df cosine-similarity [(a (List F64)) (b (List F64))] -> F64
  :doc "Calculates cosine similarity"
  (let [(dot (list-sum (list-zip-with * a b)))
        (norm-a (sqrt (list-sum (list-zip-with * a a))))
        (norm-b (sqrt (list-sum (list-zip-with * b b))))]
    (if (= (* norm-a norm-b) 0.0)
        0.0
        (/ dot (* norm-a norm-b)))))
