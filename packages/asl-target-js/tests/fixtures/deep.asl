(module jsFixtures/deep :x [main])

fn count n: Int64 acc: Int64 -> Int64
  (if (= n 0) acc (count (- n 1) (+ acc 1)))

fn ! main -> Int64
  (do (println (str (count 1000000 0) " " (listLength (range 0 200000)) " " (listSum (map (fn [(x Int64)] -> Int64 (* x 2)) (range 0 100000))))) 0)
