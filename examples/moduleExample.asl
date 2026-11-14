(module aslExamples/moduleExample
  :x [double square cube])

fn double n: Int64 -> Int64
  (+ n n)

fn square n: Int64 -> Int64
  (* n n)

fn cube n: Int64 -> Int64
  (* (square n) n)
