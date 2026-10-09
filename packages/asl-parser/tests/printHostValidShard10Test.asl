(module asl-parser/tests/printHostValidShard10Test
  :x [runTests]
  :i [(asl-parser/tests/printHostValidLib :a lib)])

fn ! runTests -> Bool
  (lib/runShard! "printHostValidShard10Test" 16 10)
