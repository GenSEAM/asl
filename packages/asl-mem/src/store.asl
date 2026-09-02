(module asl-mem/store
  :doc "In-memory vector database and cosine similarity in ASL"
  :export [VectorItem VectorStore vector-norm cosine-similarity])

(defschema VectorItem
  (:field id String "id")
  (:field text String "text payload")
  (:field vector (List Float) "embedding vector"))

(defschema VectorStore
  (:field name String "store name")
  (:field dimensions Int64 "vector dimensions")
  (:field items (List VectorItem) "stored items"))

(defun vector-norm [(v (List Float))] -> Float
  :doc "Calculates Euclidean L2 norm of a vector"
  (sqrt (list-sum (list-zip-with * v v))))

(defun cosine-similarity [(a (List Float)) (b (List Float))] -> Float
  :doc "Calculates cosine similarity"
  (let [(dot (list-sum (list-zip-with * a b)))
        (denom (* (vector-norm a) (vector-norm b)))]
    (if (== denom 0.0)
      0.0
      (/ dot denom))))
