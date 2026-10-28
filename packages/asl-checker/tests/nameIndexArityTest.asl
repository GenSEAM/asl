(module asl-checker/tests/nameIndexArityTest :x [runTests] :i [(asl-checker/tests/quadGoldenTest :a g)])

fn countOf text: String needle: String -> Int64
  (- (listLength (stringSplit text needle)) 1)

fn ! runTests -> Bool
  (let [(text (g/corpusText "asl/packages/asl-cli/src/main.asl"))]
    (do
      (assert (> (stringLength text) 10000) "the corpus must load")
      (assert (stringContains? text "asl-target-llvm/ssa") "the corpus includes asl-target-llvm/ssa")
      (assert (= (countOf text "type-arity NameIndex in ") 0) "no NameIndex use is written without its value type argument")
      true))
