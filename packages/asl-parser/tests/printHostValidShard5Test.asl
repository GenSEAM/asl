(module asl-parser/tests/printHostValidShard5Test
  :x [runTests]
  :i [(asl-parser/tests/printHostValidLib :a lib)])

fn ! runTests -> Bool
  (lib/runShard! "printHostValidShard5Test" 16 5)
