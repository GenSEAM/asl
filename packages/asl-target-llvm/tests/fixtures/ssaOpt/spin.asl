(module asl-target-llvm/tests/fixtures/ssaOpt/spin
  :x [main]
  :i [])

fn step x: (Option Int64) f: (fn [Int64] -> Int64) acc: Int64 -> Int64
  (mt x ((none) (f acc)) ((some v) (+ v acc)))

fn spin i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (spin (+ i 1) n (step (none) (fn [(k Int64)] -> Int64 (+ k 1)) acc)))

fn ! main -> (Result Int64 String)
  (do (println (str "spin " (spin 0 1000000 0))) (ok 0))
