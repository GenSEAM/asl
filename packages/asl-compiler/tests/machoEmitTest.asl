(module asl-compiler/tests/machoEmitTest :x [testMachoOutput runTests] :i [(asl-compiler/macho :a macho)])

fn testMachoOutput -> Bool
  (let [(res (macho/emitMachoArm64 (list)))] (assert (= res.target "darwin-arm64") "Mach-O emitter should target darwin-arm64") (refute (= res.status :error) "Status must not be error") true)

fn runTests -> Bool
  (do (assert (testMachoOutput) "testMachoOutput must pass") true)

