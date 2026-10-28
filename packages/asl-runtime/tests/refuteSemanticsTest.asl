(module asl-runtime/tests/refuteSemanticsTest :x [runTests testRefuteFalseComputedValues testRefuteBooleanExpressions testRefuteCountedSeparately] :i [])

fn testRefuteFalseComputedValues -> Bool
  (let [(items (list 1))] (do (refute (listEmpty? items) "refute on a false computed value must pass") (refute (= (listLength items) 0) "refute on a false computed comparison must pass") true))

fn testRefuteBooleanExpressions -> Bool
  (let [(msg "refutation test payload") (prefix (optionOr (stringSlice msg 0 4) ""))] (do (refute (stringContains? msg "nonexistent keyword") "refute substring mismatch must pass") (refute (stringEmpty? msg) "refute on non-empty string must pass") (refute (= prefix "void") "refute mismatching slice must pass") true))

fn testRefuteCountedSeparately -> Bool
  (let [(items (list "alpha" "beta" "gamma")) (total (listLength items))] (do (assert (= total 3) "list length must equal 3") (refute (listEmpty? items) "populated list must not be empty") (assert (not (listEmpty? items)) "inverted empty check must succeed") (refute (= total 0) "refute on a false comparison must succeed") true))

fn runTests -> Bool
  (do (assert (testRefuteFalseComputedValues) "test-refute-false-computed-values must pass") (assert (testRefuteBooleanExpressions) "test-refute-boolean-expressions must pass") (assert (testRefuteCountedSeparately) "test-refute-counted-separately must pass") true)
