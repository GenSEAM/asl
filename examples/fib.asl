(module asl-examples/fib
  :d "Fibonacci calculation in pure AgentScript."
  :x [fib main]
  :i [])

(df fib [(n I64)] -> I64
  (if (<= n 1)
    n
    (+ (fib (- n 1)) (fib (- n 2)))))

(df main [] -> I64
  (+ (fib 9) 8))
