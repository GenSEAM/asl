(module asl-syntax/tests/asl/asnShard1Test
  :x [runTests]
  :i [(asl-syntax/tests/asl/asnCorpusLib :a suite)])

fn ! runTests -> Bool
  (suite/runTrackedAsnShard! 0)
