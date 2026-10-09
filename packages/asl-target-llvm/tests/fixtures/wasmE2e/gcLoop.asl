(module wasmE2e/gcLoop :x [main])

fn ! churn start: Int64 count: Int64 -> Int64
  (if (<= count 0)
    0
    (if (= count 1)
      (stringLength (stringConcat "allocation" (stringFromInt64 start)))
      (+ (churn start (/ count 2)) (churn (+ start (/ count 2)) (- count (/ count 2))))))

fn ! main -> Int64
  (do (print (stringFromInt64 (churn 0 200000))) 0)
