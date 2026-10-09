(module asl-parser/tests/printHostValidShard16Test
  :x [runTests]
  :i [(asl-parser/tests/printHostValidLib :a lib)])

fn ! runTests -> Bool
  (lib/runShard! "printHostValidShard16Test" 16 16)
