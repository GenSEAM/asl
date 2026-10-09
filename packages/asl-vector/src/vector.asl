(module asl-vector/vector
  :x [Vector makeVector vectorDotProductFast vectorNormFast vectorCosineSimilarityFast]
  :i [])

(schema Vector
  (:f components (List Int64)))

fn makeVector components: (List Int64) -> Vector
  (Vector :components components)

fn dotProductLoop c1: (List Int64) c2: (List Int64) acc: Int64 -> Int64
  (let [(len1 (listLength c1))
        (len2 (listLength c2))]
    (if (or (<= len1 0) (<= len2 0))
      acc
      (if (and (>= len1 4) (>= len2 4))
        (let [(a0 (optionOr (listGet c1 0) 0))
              (b0 (optionOr (listGet c2 0) 0))
              (a1 (optionOr (listGet c1 1) 0))
              (b1 (optionOr (listGet c2 1) 0))
              (a2 (optionOr (listGet c1 2) 0))
              (b2 (optionOr (listGet c2 2) 0))
              (a3 (optionOr (listGet c1 3) 0))
              (b3 (optionOr (listGet c2 3) 0))
              (chunkSum (+ (+ (* a0 b0) (* a1 b1)) (+ (* a2 b2) (* a3 b3))))
              (rest1 (optionOr (listSlice c1 4 len1) (list)))
              (rest2 (optionOr (listSlice c2 4 len2) (list)))]
          (dotProductLoop rest1 rest2 (+ acc chunkSum)))
        (let [(a (optionOr (listHead c1) 0))
              (b (optionOr (listHead c2) 0))
              (t1 (optionOr (listTail c1) (list)))
              (t2 (optionOr (listTail c2) (list)))]
          (dotProductLoop t1 t2 (+ acc (* a b)))))))

fn vectorDotProductFast v1: Vector v2: Vector -> Int64
  (dotProductLoop v1.components v2.components 0)

fn vectorNormFast v: Vector -> Float64
  (sqrt (int64ToFloat64 (vectorDotProductFast v v)))

fn vectorCosineSimilarityFast v1: Vector v2: Vector -> Int64
  (let [(dot (vectorDotProductFast v1 v2))
        (n1 (vectorNormFast v1))
        (n2 (vectorNormFast v2))
        (denom (* n1 n2))]
    (if (<= denom 0.0)
      0
      (optionOr (float64ToInt64 (/ (int64ToFloat64 (* dot 1000)) denom)) 0)))
