(module wasmE2e/mulTrap :x [main])

fn pick xs: (List Int64) i: Int64 -> Int64
  (optionOr (listGet xs i) 0)

fn ! main -> Int64
  (let [(xs (list 3037000500 -4294967296))
        (ys (list 3037000500 -2147483648))]
    (if (> (* (pick xs 0) (pick ys 0)) 0) 2 (* (pick xs 1) (pick ys 1))))
