(module asl-parser/tests/printHostValidShard8Test
  :x [runTests]
  :i [(asl-parser/tests/printHostValidLib :a lib)])

fn ! runTests -> Bool
  (lib/runShard! "printHostValidShard8Test" 16 8)
