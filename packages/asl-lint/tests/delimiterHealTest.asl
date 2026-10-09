(module asl/packages/asl-lint/tests/delimiterHealTest
  :x [runTests RunTests testC1BalanceCertification testOneCounterDelimiterHealing testSmellClassificationAndHealing testDualPolarityProbes]
  :i [(asl-lint/core :a lnt)
      (asl-lint/heal :a hl)])

fn testC1BalanceCertification -> Bool
  (let [(bal1 (lnt/checkC1Balance "(fn add x: I64 y: I64 -> I64 (+ x y))"))]
    (assert bal1.balanced "pure Dyck-1 code satisfies C1 balance")
    (refute (not bal1.balanced) "pure Dyck-1 code refutes C1 imbalance")
    (assert (= bal1.openParens 0) "pure Dyck-1 code has 0 unclosed parens")
    (refute (!= bal1.openParens 0) "pure Dyck-1 code refutes non-zero unclosed parens"))
  (let [(bal2 (lnt/checkC1Balance "(let ((a 1) (b 2)) (* a b))"))]
    (assert bal2.balanced "pure Dyck-1 let satisfies C1 balance")
    (refute (not bal2.balanced) "pure Dyck-1 let refutes imbalance"))
  (let [(unbal1 (lnt/checkC1Balance "(fn unclosed x: I64 -> I64 (+ x 1"))]
    (assert (not unbal1.balanced) "unclosed expression fails C1 balance")
    (refute unbal1.balanced "unclosed expression refutes balanced")
    (assert (> unbal1.openParens 0) "unclosed expression reports positive open parens")
    (refute (<= unbal1.openParens 0) "unclosed expression refutes non-positive open parens"))
  (let [(unbal2 (lnt/checkC1Balance "())"))]
    (assert (not unbal2.balanced) "early closing paren fails C1 balance")
    (refute unbal2.balanced "early closing paren refutes balanced")
    (assert (< unbal2.openParens 0) "early closing paren reports negative depth")
    (refute (>= unbal2.openParens 0) "early closing paren refutes non-negative depth"))
  true

fn testOneCounterDelimiterHealing -> Bool
  (let [(raw "(fn compute x: I64 -> I64 (let ((a x)) (+ a 10")
        (healed (hl/healDelimiters raw))]
    (assert (stringEndsWith? healed "))") "healed string closes 2 unclosed parens")
    (refute (not (stringEndsWith? healed "))")) "healed string refutes missing closures")
    (let [(checkHealed (lnt/checkC1Balance healed))]
      (assert checkHealed.balanced "healed string satisfies C1 balance")
      (refute (not checkHealed.balanced) "healed string refutes imbalance")))
  (let [(alreadyBal "(ok 42)")
        (healedBal (hl/healDelimiters alreadyBal))]
    (assert (= healedBal alreadyBal) "already balanced code is unchanged by healDelimiters")
    (refute (!= healedBal alreadyBal) "already balanced code refutes modification"))
  (let [(deepUnbal "((((a b")
        (healedDeep (hl/healDelimiters deepUnbal))]
    (assert (= healedDeep "((((a b))))") "deeply unclosed code is healed with exact count of closures")
    (refute (!= healedDeep "((((a b))))") "deeply unclosed code refutes closure count mismatch"))
  true

fn testSmellClassificationAndHealing -> Bool
  (assert (hl/canAutoRepair (hl/canonicalizeFormatting)) "canonicalizeFormatting is auto-repairable")
  (refute (not (hl/canAutoRepair (hl/canonicalizeFormatting))) "canonicalizeFormatting refutes non-repairable")
  (let [(desc (hl/formatFixDescription (hl/canonicalizeFormatting)))]
    (assert (> (stringLength desc) 0) "formatFixDescription produces non-empty description")
    (refute (= (stringLength desc) 0) "formatFixDescription refutes empty description"))
  (let [(score (lnt/calculateQualityScore 0 0))]
    (assert (= score 100) "clean code scores 100")
    (refute (!= score 100) "clean code refutes non-100 score"))
  (let [(penalized (lnt/calculateQualityScore 1 2))]
    (assert (= penalized 65) "1 error and 2 warnings score 65 (100 - 25 - 10)")
    (refute (!= penalized 65) "penalized score refutes mismatch"))
  true

fn testDualPolarityProbes -> Bool
  (let [(emptyCode "")
        (resEmpty (lnt/checkC1Balance emptyCode))]
    (assert resEmpty.balanced "empty code is balanced")
    (refute (not resEmpty.balanced) "empty code refutes imbalance"))
  (let [(resBlocked (lnt/shouldBlockGate (lnt/QualityMetrics :totalNodes 10 :maxNesting 2 :errorCount 1 :warningCount 0 :score 75)))]
    (assert resBlocked "errorCount > 0 blocks gate")
    (refute (not resBlocked) "errorCount > 0 refutes gate pass"))
  (let [(resPassed (lnt/shouldBlockGate (lnt/QualityMetrics :totalNodes 10 :maxNesting 2 :errorCount 0 :warningCount 1 :score 95)))]
    (assert (not resPassed) "clean metrics allow gate pass")
    (refute resPassed "clean metrics refute gate block"))
  true

fn runTests -> Bool
  (do
    (assert (testC1BalanceCertification) "testC1BalanceCertification passed")
    (assert (testOneCounterDelimiterHealing) "testOneCounterDelimiterHealing passed")
    (assert (testSmellClassificationAndHealing) "testSmellClassificationAndHealing passed")
    (assert (testDualPolarityProbes) "testDualPolarityProbes passed")
    true)

fn RunTests -> Bool
  (runTests)
