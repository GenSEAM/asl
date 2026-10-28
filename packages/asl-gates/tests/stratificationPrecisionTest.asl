(module asl-gates/tests/stratificationPrecisionTest :x [testStratificationPrecisionAndDummyEradication! testSubtreeLayerMapping testDualPolarityRefutations! runTests] :i [(asl-gates/stratification :a st)])

fn testStratificationPrecisionAndDummyEradication! -> Bool
  (let [(lDummy (st/moduleLayer "dummy")) (lDummyParser (st/moduleLayer "my-dummy-parser")) (source (match (fileReadString "asl/packages/asl-gates/src/stratification.asl") ((ok c) c) ((err _) "")))] (assert (= lDummy 0) "moduleLayer 'dummy' must evaluate to 0 (substrate default)") (assert (= lDummyParser 0) "moduleLayer 'my-dummy-parser' must evaluate to 0") (assert (not (stringContains? source "\"dummy\"")) "stratification.asl must not contain string 'dummy'") true)

fn testSubtreeLayerMapping -> Bool
  (do (assert (= (st/moduleLayer "asl-parser") 0) "asl-parser is Layer 0") (assert (= (st/moduleLayer "asl/packages/asl-parser/src/lexer.asl") 0) "asl-parser path is Layer 0") (assert (= (st/moduleLayer "intel") 1) "intel is Layer 1") (assert (= (st/moduleLayer "asl/packages/asl-vfs/src/vfs.asl") 1) "vfs path is Layer 1") (assert (= (st/moduleLayer "agent") 2) "agent is Layer 2") (assert (= (st/moduleLayer "asl/packages/asl-router/src/router.asl") 2) "router path is Layer 2") (assert (= (st/moduleLayer "asl-gates") 3) "asl-gates is Layer 3") (assert (= (st/moduleLayer "asl/packages/asl-gates/src/gates.asl") 3) "gates path is Layer 3") true)

fn testDualPolarityRefutations! -> Bool
  (let [(source (match (fileReadString "asl/packages/asl-gates/src/stratification.asl") ((ok c) c) ((err _) "")))] (refute (= (st/moduleLayer "dummy") 1) "Refute that dummy maps to Layer 1") (refute (= (st/moduleLayer "my-dummy-parser") 1) "Refute that my-dummy-parser maps to Layer 1") (refute (stringContains? source "\"dummy\"") "Refute that dummy appears in stratification source") true)

fn ! runTests -> Bool
  (do (assert (testStratificationPrecisionAndDummyEradication!) "testStratificationPrecisionAndDummyEradication must pass") (assert (testSubtreeLayerMapping) "testSubtreeLayerMapping must pass") (assert (testDualPolarityRefutations!) "testDualPolarityRefutations must pass") true)
