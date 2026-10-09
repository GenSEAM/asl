(module asl-parser/tests/printHostValidShard9Test
  :x [runTests]
  :i [(asl-parser/tests/printHostValidLib :a lib)])

fn ! runTests -> Bool
  (lib/runShard! "printHostValidShard9Test" 16 9)
