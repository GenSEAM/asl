(module asl-mem/store
  :d "In-memory vector store: L2 norm and cosine similarity over embeddings."
  :x [VectorItem VectorStore sqrt-approx dot vector-norm cosine-similarity])

(dfs VectorItem
  (:f id Str "Stable identifier for the stored item")
  (:f text Str "Text payload the vector was derived from")
  (:f vector (List F64) "Embedding vector"))

(dfs VectorStore
  (:f name Str "Store name")
  (:f dimensions I64 "Expected vector length")
  (:f items (List VectorItem) "Stored items"))

(df newton-step [(guess F64) (x F64)] -> F64
  :d "One Newton-Raphson iteration towards the square root of x."
  (* 0.5 (+ guess (/ x guess))))

(df sqrt-approx [(x F64)] -> F64
  :d "Square root by Newton-Raphson. The vocabulary has no sqrt, and a fixed
      iteration count keeps this total and identical on every backend."
  (if (<= x 0.0)
    0.0
    (fold (fn [(g F64) (i I64)] -> F64 (newton-step g x))
          x
          (range 0 24))))

(df dot [(a (List F64)) (b (List F64))] -> F64
  :d "Sum of pairwise products, truncating to the shorter vector."
  (list-sum (map (fn [(p (Pair F64 F64))] -> F64 (* (.-first p) (.-second p)))
                 (zip a b))))

(df vector-norm [(v (List F64))] -> F64
  :d "Euclidean L2 norm."
  (sqrt-approx (dot v v)))

(df cosine-similarity [(a (List F64)) (b (List F64))] -> F64
  :d "Cosine of the angle between two vectors; 0.0 when either has no length."
  (let [(denom (* (vector-norm a) (vector-norm b)))]
    (if (= denom 0.0)
      0.0
      (/ (dot a b) denom))))
