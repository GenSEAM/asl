(module wasmE2e/mulWide :x [main])

fn pick xs: (List Int64) i: Int64 -> Int64
  (optionOr (listGet xs i) 0)

fn ! main -> Int64
  (let [(xs (list 3037000499 -3037000499 4294967296 -4294967296 -1 65536))
        (ys (list 3037000499 3037000499 2147483647 2147483647 -9223372036854775807 -140737488355328))
        (ps (map (fn [(i Int64)] -> String (stringFromInt64 (* (pick xs i) (pick ys i)))) (list 0 1 2 3 4 5)))]
    (do (print (stringJoin ps ",")) 7))
