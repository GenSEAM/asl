(module asl-parser/tests/printHostValidShard12Test
  :x [runTests]
  :i [(asl-parser/tests/printHostValidLib :a lib)])

fn ! runTests -> Bool
  (lib/runShard! "printHostValidShard12Test" 16 12)
