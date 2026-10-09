(module wasmE2e/trap :x [main])

fn ! main -> Int64
  (/ 7 0)
