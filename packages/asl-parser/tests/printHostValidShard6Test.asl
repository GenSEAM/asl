(module asl-parser/tests/printHostValidShard6Test
  :x [runTests]
  :i [(asl-parser/tests/printHostValidLib :a lib)])

fn ! runTests -> Bool
  (lib/runShard! "printHostValidShard6Test" 16 6)
