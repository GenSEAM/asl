(module wasmE2e/hello :x [main])

fn ! main -> Int64
  (do (print "hello wasm\n") 0)
