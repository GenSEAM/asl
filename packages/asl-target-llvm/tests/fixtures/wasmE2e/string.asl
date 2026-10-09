(module wasmE2e/string :x [main])

fn ! main -> Int64
  (do (print (stringConcat (stringConcat "wasm" " ") "string\n")) 0)
