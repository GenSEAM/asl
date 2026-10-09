(module aslHarness/budgetTest :x [testBudgetTracking testBudgetLimits runTests] :i [(budget :a b)])

fn testBudgetTracking -> Bool
  (let [(bt0 (b/makeBudget 1000 10 5000)) (bt1 (b/recordTurn bt0 250 120))] (do (assert (= bt1.usedTokens 250) "used tokens is 250") (assert (= bt1.usedTurns 1) "used turns is 1") (assert (not (b/isBudgetExceeded? bt1)) "budget not exceeded") true))

fn testBudgetLimits -> Bool
  (let [(bt0 (b/makeBudget 100 2 1000)) (bt1 (b/recordTurn bt0 150 100))] (do (assert (b/isBudgetExceeded? bt1) "bt1 budget exceeded") (assert (not (b/isBudgetExceeded? bt0)) "bt0 budget not exceeded") true))

fn runTests -> Bool
  (do (assert (testBudgetTracking)) (assert (testBudgetLimits)) true)
