(module asl-parser/tests/printHostValidShard1Test
  :x [runTests]
  :i [(asl-parser/tests/printHostValidLib :a lib)])

fn ! runTests -> Bool
  (lib/runShard! "printHostValidShard1Test" 16 1)
