(module asl-target-llvm/tests/fixtures/ssaOpt/semantics
  :x [main lines]
  :i [(asl-target-llvm/tests/fixtures/ssaOpt/libLeaf :a leaf)
      (asl-target-llvm/tests/fixtures/ssaOpt/libMid :a mid)])

fn optName o: (Option Int64) -> String
  (mt o ((none) "none") ((some v) (str "some" v)))

fn workerLine x: Int64 -> String
  (str (= (leaf/noneOf) (none)) " " (leaf/shadeName (if (> x 1) (leaf/dark) (leaf/light))) " " (leaf/twice (leaf/incBy) x))

fn lines -> (List String)
  (list (mid/initLine)
        (str "eq " (= (none) (none)) " " (= (leaf/noneOf) (none)) " " (= (leaf/dark) (leaf/dark)) " " (= (leaf/dark) (leaf/light)) " " (= (some 1) (none)) " " (= (leaf/dark) (leaf/shadeTinted 0)))
        (str "mt " (optName (none)) " " (optName (leaf/noneOf)) " " (optName (some 7)) " " (leaf/shadeName (leaf/light)) " " (leaf/shadeName (leaf/shadeTinted 3)))
        (str "fn " (leaf/twice leaf/inc 1) " " (leaf/twice (leaf/incBy) 2) " " (leaf/twice (fn [(k Int64)] -> Int64 (* k 3)) 2) " " (stringJoin (map (fn [(k Int64)] -> String (str (+ k 10))) (list 1 2)) ","))
        (str "par " (stringJoin (parMap workerLine (list 1 2 3) 2) "|"))
        (str "parLambda " (stringJoin (map optName (parMap (fn [(x Int64)] -> (Option Int64) (if (> x 1) (none) (some x))) (list 1 2 3) 2)) ",")))

fn ! main -> (Result Int64 String)
  (do (println (stringJoin (lines) "\n")) (ok 0))
