(module asl-parser/tests/printReparseTest
  :x [runTests]
  :i [(asl-parser/tests/printReparseLib :a lib)])

fn runTests -> Bool
  (lib/testMutantGuards)
