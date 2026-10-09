(module asl-target-llvm/tests/fixtures/nativeData/gapMain
  :x [main]
  :i [(asl/packages/asl-target-llvm/tests/fixtures/nativeData/gapLeaf :a leaf)])

fn ! main -> (Result Unit String)
  (do (leaf/leafNote true) (if true (println "gap main")) (ok ()))
