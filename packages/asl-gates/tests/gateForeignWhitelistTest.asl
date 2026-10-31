(module asl-gates/tests/gateForeignWhitelistTest :x [testForeignFilesPositiveWhitelist testGate5TestIntegrityVerification testDualPolarityRefutations runTests] :i [(asl-gates/gates :a g)])

fn testForeignFilesPositiveWhitelist -> Bool
  (let [(paths (list "asl/packages/foo/valid.asl" "asl/packages/foo/schema.asn" "asl/packages/foo/README.md" "asl/packages/foo/script.rb" "asl/packages/foo/binary.bin" "asl/packages/foo/module.go")) (foreign (g/findForeignFilesInPaths paths))] (assert (= (listLength foreign) 3) "Must identify exactly 3 foreign files") (assert (listContains? foreign "asl/packages/foo/script.rb") "Must detect .rb file") (assert (listContains? foreign "asl/packages/foo/binary.bin") "Must detect .bin file") (assert (listContains? foreign "asl/packages/foo/module.go") "Must detect .go file") (refute (listContains? foreign "asl/packages/foo/valid.asl") "Must not flag .asl") (refute (listContains? foreign "asl/packages/foo/schema.asn") "Must not flag .asn") (refute (listContains? foreign "asl/packages/foo/README.md") "Must not flag .md") true)

fn testGate5TestIntegrityVerification -> Bool
  (let [(validSyntax (g/verifySourceSyntax "(module test/sample :export [])")) (brokenSyntax (g/verifySourceSyntax "(module broken (:export unclosed"))] (assert validSyntax "Valid test syntax must pass verifySourceSyntax") (assert (not brokenSyntax) "Broken syntax must fail verifySourceSyntax") (refute brokenSyntax "Refute that broken syntax passes verifySourceSyntax") true)

fn testDualPolarityRefutations -> Bool
  (let [(foreign (g/findForeignFilesInPaths (list "asl/packages/foo/script.rb" "asl/packages/foo/binary.bin")))] (refute (= (listLength foreign) 0) "Refute that unlisted extensions pass findForeignFilesInPaths") (refute (g/verifySourceSyntax "((( unbalanced ((((") "Refute that unbalanced delimiters pass syntax check") true)

fn runTests -> Bool
  (do (assert (testForeignFilesPositiveWhitelist) "testForeignFilesPositiveWhitelist must pass") (assert (testGate5TestIntegrityVerification) "testGate5TestIntegrityVerification must pass") (assert (testDualPolarityRefutations) "testDualPolarityRefutations must pass") true)
