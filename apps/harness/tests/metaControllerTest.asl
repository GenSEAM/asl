(module aslHarness/metaControllerTest :x [testTaskEntropyFormula testTaskEntropyBoundaries testTierRoutingBoundaries testProfileAlias runTests] :i [(metaController :a mc)])

fn testTaskEntropyFormula -> Bool
  (let [(eZero (mc/computeTaskEntropy 0 0.0 0.0 0.0)) (eSingle (mc/computeTaskEntropy 1 0.1 0.2 0.1)) (eLarge (mc/computeTaskEntropy 10 1.0 1.0 1.0))] (do (assert (= eZero 0.0)) (assert (>= eSingle 0.99)) (assert (<= eSingle 1.01)) (assert (= eLarge 9.0)) true))

fn testTaskEntropyBoundaries -> Bool
  (let [(tierBelow15 (mc/selectExecutionTier 1.49)) (tierExact15 (mc/selectExecutionTier 1.50)) (tierBelow40 (mc/selectExecutionTier 3.99)) (tierExact40 (mc/selectExecutionTier 4.00))] (do (assert (= tierBelow15 "fast-path")) (assert (= tierExact15 "balanced")) (assert (= tierBelow40 "balanced")) (assert (= tierExact40 "deep-reflex")) true))

fn testTierRoutingBoundaries -> Bool
  (let [(tZero (mc/selectExecutionTier 0.0)) (tLow (mc/selectExecutionTier 1.2)) (tMid (mc/selectExecutionTier 2.5)) (tHigh (mc/selectExecutionTier 5.5))] (do (assert (= tZero "fast-path")) (assert (= tLow "fast-path")) (assert (= tMid "balanced")) (assert (= tHigh "deep-reflex")) true))

fn testProfileAlias -> Bool
  (let [(pFast (mc/selectExecutionProfile 1.0)) (pBal (mc/selectExecutionProfile 2.0)) (pDeep (mc/selectExecutionProfile 4.5))] (do (assert (= pFast "fast-path")) (assert (= pBal "balanced")) (assert (= pDeep "deep-reflex")) (assert (= (mc/selectExecutionProfile 1.2) (mc/selectExecutionTier 1.2))) (assert (= (mc/selectExecutionProfile 2.5) (mc/selectExecutionTier 2.5))) (assert (= (mc/selectExecutionProfile 6.0) (mc/selectExecutionTier 6.0))) true))

fn runTests -> Bool
  (do (assert (testTaskEntropyFormula)) (assert (testTaskEntropyBoundaries)) (assert (testTierRoutingBoundaries)) (assert (testProfileAlias)) true)
