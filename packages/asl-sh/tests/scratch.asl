(module asl-sh/tests/scratch
  :x [main]
  :i [(asl-sh/process :a proc)
      (reducer      :a red)
      (sh           :a sh)
      (apm          :a apm)])

(df main [] -> Bool
  (do
    (println (proc/makeProcessReceipt 0 10 20 "path" "sum"))
    true))
