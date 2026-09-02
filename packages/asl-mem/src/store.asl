(module asl-mem/store
  :d "In-memory vector database and cosine similarity in ASL"
  :x [VectorItem VectorStore vector-norm cosine-similarity])

(dfs VectorItem
  (:f id String "id")
  (:f text String "text payload")
  (:f vector (List Float) "embedding vector"))

(dfs VectorStore
  (:f name String "store name")
  (:f dimensions Int64 "vector dimensions")
  (:f items (List VectorItem) "stored items"))

(df vector-norm [(v (List Float))] -> Float
  :d "Calculates Euclidean L2 norm of a vector"
  (sqrt (list-sum (list-zip-with * v v))))

(df cosine-similarity [(a (List Float)) (b (List Float))] -> Float
  :d "Calculates cosine similarity"
  (let [(dot (list-sum (list-zip-with * a b)))
        (denom (* (vector-norm a) (vector-norm b)))]
    (if (== denom 0.0)
      0.0
      (/ dot denom))))
