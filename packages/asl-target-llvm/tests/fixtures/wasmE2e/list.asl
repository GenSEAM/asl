(module wasmE2e/list :x [main])

fn ! main -> Int64
  (let [(values (list 10 20 30 40))
        (selected (+ (optionOr (listGet values 0) 0) (optionOr (listGet values 3) 0)))]
    (do (print (stringFromInt64 (+ selected (listLength values)))) 4))
