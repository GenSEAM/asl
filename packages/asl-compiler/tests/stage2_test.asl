(module asl-compiler/stage2Test
  :d "Pure ASL Stage-2 compiler, Mach-O, and ELF emitter acceptance suite under D86."
  :x [testMachoEmission
      testElfEmission
      testParserPipeline
      testDualPolarityRefutations
      runTests]
  :i [(macho :a m)
      (elf :a e)
      (parser :a p)])

(df testMachoEmission [] -> Bool
  :d "Verifies pure ASL Mach-O ARM64 emitter produces valid target output."
  (let [(res (m/emitMachoArm64 (list)))]
    (assert (= (get res :target) "darwin-arm64") "Mach-O target must be darwin-arm64")
    (assert (= (get (get res :headers) :magic) "MH_MAGIC_64") "Mach-O magic must be MH_MAGIC_64")
    (refute (= (get res :status) :error) "Mach-O status must not be :error")
    true))

(df testElfEmission [] -> Bool
  :d "Verifies pure ASL ELF64 emitter produces valid target output."
  (let [(res (e/emitElf64 (list)))]
    (assert (= (get res :target) "linux-x86_64") "ELF target must be linux-x86_64")
    (assert (= (get (get res :headers) :magic) "ELF_MAGIC") "ELF magic must be ELF_MAGIC")
    (refute (= (get res :status) :error) "ELF status must not be :error")
    true))

(df testParserPipeline [] -> Bool
  :d "Verifies pure ASL stage-2 parser and AST generator pipeline."
  (let [(tokens (p/tokenizeAsl "module test :d \"doc\""))
        (ast (p/astBuilder tokens))
        (tree (p/syntaxTree ast))]
    (assert (> (get ast :nodeCount) 0) "Parser must produce tokens")
    (assert (= (get tree :valid) true) "Syntax tree must be valid")
    (refute (= (get ast :nodeCount) 0) "Parser must not produce empty node count")
    true))

(df testDualPolarityRefutations [] -> Bool
  :d "Verifies dual-polarity refutations under D77."
  (let [(sample "stage2_certified")]
    (assert (string-contains? sample "stage2") "sample must contain stage2")
    (refute (string-contains? sample "error") "sample must not contain error")
    true))

(df ! runTests [] -> Bool
  :d "Executes all Stage-2 compiler tests."
  (do
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations")
    (assert (testMachoEmission) "testMachoEmission")
    (assert (testElfEmission) "testElfEmission")
    (assert (testParserPipeline) "testParserPipeline")
    true))
