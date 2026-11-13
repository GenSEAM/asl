fn clampInt x: Int64 lo: Int64 hi: Int64 -> Int64
  (if (< x lo) lo (if (> x hi) hi x))
