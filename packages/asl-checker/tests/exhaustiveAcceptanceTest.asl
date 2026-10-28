(module asl-checker/tests/exhaustiveAcceptanceTest
  :x [runTests RunTests testExhaustivenessDetection testWildcardBypass testDualPolarityRefutations]
  :i [(asl-checker/exhaustive :a ex)])

fn testExhaustivenessDetection -> Bool
  (let [(variants (list "Option/some" "Option/none"))
        (goodArms (list "Option/some" "Option/none"))
        (badArms (list "Option/some"))
        (goodRep (ex/checkMatchExhaustiveness variants goodArms false))
        (badRep (ex/checkMatchExhaustiveness variants badArms false))]
    (assert goodRep.isExhaustive "covering all Option variants is exhaustive")
    (refute (not goodRep.isExhaustive) "goodRep refutes non-exhaustive")
    (assert (not badRep.isExhaustive) "missing Option/none is not exhaustive")
    (refute badRep.isExhaustive "badRep refutes exhaustive")
    (assert (listContains? badRep.missingVariants "Option/none") "missing variants contains Option/none"))
  true

fn testWildcardBypass -> Bool
  (let [(variants (list "A" "B" "C"))
        (arms (list "A"))
        (rep (ex/checkMatchExhaustiveness variants arms true))]
    (assert rep.isExhaustive "wildcard branch makes match exhaustive")
    (refute (not rep.isExhaustive) "wildcard match refutes failure"))
  true

fn testDualPolarityRefutations -> Bool
  (let [(allVars (list "North" "South" "East" "West"))
        (emptyArms (list))
        (rep (ex/checkMatchExhaustiveness allVars emptyArms false))]
    (assert (= (listLength rep.missingVariants) 4) "empty arms reports all 4 variants missing")
    (refute (!= (listLength rep.missingVariants) 4) "missing count refutes non-4"))
  true

fn runTests -> Bool
  (do
    (assert (testExhaustivenessDetection) "testExhaustivenessDetection passed")
    (assert (testWildcardBypass) "testWildcardBypass passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
