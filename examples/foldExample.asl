(module aslExamples/foldExample
  :x [sumOf product doubled evens])

fn sumOf xs: (List Int64) -> Int64
  (fold (fn [sum x] (+ sum x)) 0 xs)

fn product xs: (List Int64) -> Int64
  (fold (fn [acc x] (* acc x)) 1 xs)

fn doubled xs: (List Int64) -> (List Int64)
  (map (fn [x] (* x 2)) xs)

fn evens xs: (List Int64) -> (List Int64)
  (filter (fn [x] (= (mod x 2) 0)) xs)
