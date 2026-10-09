(module asl-parser/tests/printHostValidShard7Test
  :x [runTests]
  :i [(asl-parser/tests/printHostValidLib :a lib)])

fn ! runTests -> Bool
  (lib/runShard! "printHostValidShard7Test" 16 7)
