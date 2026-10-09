(module asl-syntax/tests/asl/asnShard2Test
  :x [runTests]
  :i [(asl-syntax/tests/asl/asnCorpusLib :a suite)])

fn ! runTests -> Bool
  (suite/runTrackedAsnShard! 1)
