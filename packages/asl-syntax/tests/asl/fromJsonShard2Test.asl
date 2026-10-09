(module asl-syntax/tests/asl/fromJsonShard2Test
  :x [runTests]
  :i [(asl-syntax/tests/asl/fromJsonCorpusLib :a lib)])

fn ! runTests -> Bool
  (lib/runCorpusShard! "fromJsonShard2Test" 8 2)
