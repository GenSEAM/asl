(module asl-syntax/tests/asl/fromJsonShard6Test
  :x [runTests]
  :i [(asl-syntax/tests/asl/fromJsonCorpusLib :a lib)])

fn ! runTests -> Bool
  (lib/runCorpusShard! "fromJsonShard6Test" 8 6)
