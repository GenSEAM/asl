(module asl-compiler/stage2Test :x [testMachoEmission testElfEmission testDualPolarityRefutations runTests] :i [(macho :a m) (elf :a e)])

fn testMachoEmission -> Bool
  (let [(res (m/emitMachoArm64 (list)))] (assert (= res.target "darwin-arm64") "Mach-O target must be darwin-arm64") (assert (= res.headers.magic "MH_MAGIC_64") "Mach-O magic must be MH_MAGIC_64") (refute (= res.status :error) "Mach-O status must not be :error") true)

fn testElfEmission -> Bool
  (let [(res (e/emitElf64 (list)))] (assert (= res.target "linux-x86_64") "ELF target must be linux-x86_64") (assert (= res.headers.magic "ELF_MAGIC") "ELF magic must be ELF_MAGIC") (refute (= res.status :error) "ELF status must not be :error") true)

fn testDualPolarityRefutations -> Bool
  (let [(sample "stage2_certified")] (assert (stringContains? sample "stage2") "sample must contain stage2") (refute (stringContains? sample "error") "sample must not contain error") true)

fn ! runTests -> Bool
  (do (assert (testDualPolarityRefutations) "testDualPolarityRefutations") (assert (testMachoEmission) "testMachoEmission") (assert (testElfEmission) "testElfEmission") true)
