(module wasmE2e/arithmetic :x [main])

fn ! main -> Int64
  (do (print (stringFromInt64 (+ (* 6 7) (- 100 58)))) 42)
