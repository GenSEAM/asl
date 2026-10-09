(module asl-syntax/tests/asl/fromJsonShard4Test
  :x [runTests]
  :i [(asl-syntax/tests/asl/fromJsonCorpusLib :a lib)])

fn ! runTests -> Bool
  (lib/runCorpusShard! "fromJsonShard4Test" 8 4)
