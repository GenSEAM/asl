(module asl-target-llvm/tests/fixtures/nativeData/gapLeaf
  :x [leafNote]
  :i [])

fn ! leafNote flag: Bool -> Bool
  (do (if flag (println "gap leaf")) true)
