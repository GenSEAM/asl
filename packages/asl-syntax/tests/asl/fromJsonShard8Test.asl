(module asl-syntax/tests/asl/fromJsonShard8Test
  :x [runTests]
  :i [(asl-syntax/tests/asl/fromJsonCorpusLib :a lib)])

fn ! runTests -> Bool
  (lib/runCorpusShard! "fromJsonShard8Test" 8 8)
