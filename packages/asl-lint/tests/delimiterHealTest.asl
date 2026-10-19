(module asl/packages/asl-lint/tests/delimiterHealTest
  :x [runTests RunTests testC1BalanceCertification testOneCounterDelimiterHealing testSmellClassificationAndHealing testDualPolarityProbes]
  :i [(asl-lint/core :a lnt)
      (asl-forms/heal :a heal)])

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
  (let [(raw "(module m :x [compute])\n\nfn compute x: Int64 -> Int64\n  (let [(a x)] (+ a 10\n")
        (res (heal/healSource raw "m.asl"))]
    (assert (stringEndsWith? res.text "(+ a 10))\n") "the heal pipeline closes the 2 unclosed parens")
    (refute (not (listContains? res.repaired "delimiterBalance")) "the receipt names delimiterBalance")
    (let [(checkHealed (lnt/checkC1Balance res.text))]
      (assert checkHealed.balanced "healed text satisfies C1 balance")
      (refute (not checkHealed.balanced) "healed text refutes imbalance")))
  (let [(alreadyBal "(module m :x [f])\n\nfn f -> Int64\n  42\n")
        (healedBal (heal/healSource alreadyBal "m.asl"))]
    (assert (= healedBal.text alreadyBal) "already checking code is unchanged by the heal pipeline")
    (refute healedBal.changed "already checking code refutes modification"))
  (let [(deepUnbal "(module m :x [f])\n\nfn f n: Int64 -> Int64\n  (+ (+ (+ n 1) 2) 3\n")
        (healedDeep (heal/healSource deepUnbal "m.asl"))]
    (assert (= healedDeep.text "(module m :x [f])\n\nfn f n: Int64 -> Int64\n  (+ (+ (+ n 1) 2) 3)\n") "deeply unclosed code is healed with the exact closure")
    (refute (not (listEmpty? healedDeep.left)) "deeply unclosed code leaves nothing over"))
  true

fn testSmellClassificationAndHealing -> Bool
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
