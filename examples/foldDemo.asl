(module asl/examples/foldDemo
  :x [sumLengths]
  :i [])

fn sumLengths xs: (List String) -> Int64
  (fold (fn [acc x] (+ acc (stringLength x))) 0 xs)
