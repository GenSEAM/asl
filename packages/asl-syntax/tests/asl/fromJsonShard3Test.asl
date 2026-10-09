(module asl-syntax/tests/asl/fromJsonShard3Test
  :x [runTests]
  :i [(asl-syntax/tests/asl/fromJsonCorpusLib :a lib)])

fn ! runTests -> Bool
  (lib/runCorpusShard! "fromJsonShard3Test" 8 3)
