(module range/band :x [band])

fn mark b: Bool -> String
  (if b "T" "F")

fn band lo: Int64 x: Int64 hi: Int64 -> String
  (str (mark (<= lo x)) (mark (>= hi x)) (mark (< lo x)) (mark (> hi x)) (mark (!= x lo)) (mark (and (!= x lo) (>= hi x))) (mark (or (= x lo) (> x hi))) (mark (not (and (<= lo x) (>= hi x)))))
