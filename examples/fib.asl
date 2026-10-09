(module aslExamples/fib :x [fib main] :i [])

fn fib n: Int64 -> Int64   (if (<= n 1) n (+ (fib (- n 1)) (fib (- n 2))))

fn main -> Int64   (+ (fib 9) 8)
