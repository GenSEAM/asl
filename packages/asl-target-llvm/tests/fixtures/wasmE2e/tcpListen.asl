(module wasmE2e/tcpListen :x [main])

fn ! main -> Int64
  (mt (tcpListen 0) ((ok _) 0) ((err _) 1))
