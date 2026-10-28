fn churn k: Int64 n: Int64 acc: Int64 -> Int64
  (if (= k n) acc
    (churn (+ k 1) n (+ acc (i64ArraySum (i64ArrayGenerate 200 (fn [(i Int64)] -> Int64 (+ i k)))))))

fn main
  (println (stringFromInt64 (churn 0 2000 0)))
