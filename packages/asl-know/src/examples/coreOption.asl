(module asl-know/examples/coreOption :x [parsePort selfTest] :i [])

fn parsePort s: String -> (Result Int64 String)
  (mt (stringToInt64 s)
    ((none) (err (str "not a number: " s)))
    ((some n) (if (and (> n 0) (< n 65536)) (ok n) (err "out of range"))))

fn selfTest -> Bool
  (and (= (resultOr (parsePort "8080") 0) 8080) (err? (parsePort "x")) (= (resultOr (parsePort "70000") 0) 0)
       (= (optionOr (resultToOption (parsePort "1")) 0) 1))
