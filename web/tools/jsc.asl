(module aslSite/tools/jsc :x [! main] :i [(asl-target-js/main :a js)])

fn ! main -> Int64
  (let [(entry (optionOr (envGet "ENTRY") "spike/small.asl")) (out (optionOr (envGet "OUT") "/tmp/out.mjs"))]
    (mt (js/compileEntry! entry) ((err ds) (do (eprintln (js/diagText ds)) 1)) ((ok text) (do (fileWrite out text) 0))))
