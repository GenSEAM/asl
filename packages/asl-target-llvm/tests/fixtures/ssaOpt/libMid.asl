(module asl-target-llvm/tests/fixtures/ssaOpt/libMid
  :x [initLine]
  :i [(asl-target-llvm/tests/fixtures/ssaOpt/libLeaf :a leaf)])

fn initLine -> String
  (str "init " (= (leaf/noneOf) (none)) " " (leaf/shadeName (leaf/dark)) " " (= (leaf/dark) (leaf/dark)) " " (= (leaf/dark) (leaf/light)) " " (leaf/twice (leaf/incBy) 40))

(println (initLine))
