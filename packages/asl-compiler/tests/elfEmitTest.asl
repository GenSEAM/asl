(module asl-compiler/tests/elfEmitTest :x [testElfOutput runTests] :i [(asl-compiler/elf :a elf)])

fn testElfOutput -> Bool
  (let [(res (elf/emitElf64 (list)))] (assert (= res.target "linux-x86_64") "ELF emitter should target linux-x86_64") (refute (= res.status :error) "Status must not be error") true)

fn runTests -> Bool
  (do (assert (testElfOutput) "testElfOutput must pass") true)

