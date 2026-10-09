(module asl-parser/tests/printHostValidShard15Test
  :x [runTests]
  :i [(asl-parser/tests/printHostValidLib :a lib)])

fn ! runTests -> Bool
  (lib/runShard! "printHostValidShard15Test" 16 15)
