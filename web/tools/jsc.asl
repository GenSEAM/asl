(module aslSite/tools/jsc :x [! main] :i [(asl-target-js/main :a js)])

fn ! main -> Int64
  (let [(entry (optionOr (envGet "ENTRY") "spike/small.asl")) (out (optionOr (envGet "OUT") "/tmp/out.mjs"))]
    (mt (js/compileWithTypes! entry) ((err ds) (do (eprintln (js/diagText ds)) 1)) ((ok both) (do (fileWrite out (pairFirst both)) (fileWrite (str (stringReplace out ".mjs" "") ".d.mts") (pairSecond both)) 0))))
