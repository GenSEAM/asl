(module asl-proc/tests/scratch :x [main runTests] :i [(asl-proc/process :a proc) (reducer :a red) (sh :a sh) (apm :a apm)])

fn ! main -> Bool
  (do (println (proc/makeProcessReceipt 0 10 20 "path" "sum")) true)

fn runTests -> Bool
  (let [(rcpt (proc/makeProcessReceipt 0 10 20 "path" "sum"))]
    (assert (= rcpt.durationMs 10) "receipt must carry its fields")
    true)
