(module asl-checker/tests/exhaustiveTest
  :x [runTests RunTests testCompleteMatchExhaustive testMissingVariantNonExhaustive testWildcardExhaustive testDualPolarityRefutations]
  :i [(asl-checker/exhaustive :a ex)])

fn testCompleteMatchExhaustive -> Bool
  (let [(variants (list "ok" "err"))
        (arms (list "ok" "err"))
        (rep (ex/checkMatchExhaustiveness variants arms false))]
    (assert rep.isExhaustive "matching all variants is exhaustive")
    (refute (not rep.isExhaustive) "complete match refutes non-exhaustive")
    (assert (listEmpty? rep.missingVariants) "missing variants is empty")
    (refute (not (listEmpty? rep.missingVariants)) "missing variants refutes non-empty"))
  true

fn testMissingVariantNonExhaustive -> Bool
  (let [(variants (list "red" "green" "blue"))
        (arms (list "red" "green"))
        (rep (ex/checkMatchExhaustiveness variants arms false))]
    (assert (not rep.isExhaustive) "match missing blue is not exhaustive")
    (refute rep.isExhaustive "missing blue refutes exhaustive")
    (assert (= (listLength rep.missingVariants) 1) "missing list has 1 item")
    (assert (listContains? rep.missingVariants "blue") "missing list contains blue")
    (assert (stringContains? rep.diagnostic "blue") "diagnostic references missing case blue"))
  true

fn testWildcardExhaustive -> Bool
  (let [(variants (list "A" "B" "C" "D" "E"))
        (arms (list "A"))
        (rep (ex/checkMatchExhaustiveness variants arms true))]
    (assert rep.isExhaustive "wildcard match is always exhaustive")
    (refute (not rep.isExhaustive) "wildcard match refutes non-exhaustive")
    (assert rep.hasWildcard "report indicates wildcard presence"))
  true

fn testDualPolarityRefutations -> Bool
  (let [(emptyVariants (list))
        (arms (list))
        (rep (ex/checkMatchExhaustiveness emptyVariants arms false))]
    (assert rep.isExhaustive "empty variants with empty arms is vacuously exhaustive")
    (refute (not rep.isExhaustive) "empty variants refutes failure"))
  true

fn runTests -> Bool
  (do
    (assert (testCompleteMatchExhaustive) "testCompleteMatchExhaustive passed")
    (assert (testMissingVariantNonExhaustive) "testMissingVariantNonExhaustive passed")
    (assert (testWildcardExhaustive) "testWildcardExhaustive passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
