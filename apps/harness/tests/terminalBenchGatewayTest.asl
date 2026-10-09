(module aslHarness/tests/terminalBenchGatewayTest :x [testGatewayConfig testThinkQuarantine testEshInterception testBudgetCeilingEnforcement testCtrfSubtestGradient testSolvableChallengePass runTests] :i [(provider :a prov) (sovereignRunner :a sr) (modelCalibration :a mc)])

fn testGatewayConfig -> Bool
  (let [(cfg (prov/defaultGatewayConfig))] (do (assert (= cfg.model "gemma-4-31b-it") "model is gemma-4-31b-it") (assert (= cfg.maxTokens 4096) "max tokens budget is 4096") true))

fn testThinkQuarantine -> Bool
  (let [(raw "<think>\nInvestigating crash in custom-memory-heap-crash\nFound double free in slab allocator\n</think>\nIdentified memory corruption root cause.") (resp (prov/parseModelResponse raw false))] (do (assert (= resp.text "Identified memory corruption root cause.") "user text is stripped of think block") (assert (= resp.finishReason "stop") "finish reason is stop") true))

fn testEshInterception -> Bool
  (let [(raw "Task complete. All tests pass cleanly.") (resp (prov/parseModelResponse raw false))] (do (assert (= resp.finishReason "esh_rejected") "unverified verbal claim rejected as esh_rejected") (assert (not (= resp.finishReason "stop")) "finish reason is not stop") true))

fn testBudgetCeilingEnforcement -> Bool
  (let [(rail (sr/makeDefaultGuardrail)) (trace (sr/runGuardedEpistemicTask "TB4-HARD-04" 3 10000 rail))] (do (assert (<= trace.totalTokens 35000) "token consumption strictly bounded below 35k ceiling") (assert trace.circuitTripped "circuit breaker trips on hard challenge loop threshold") true))

fn testCtrfSubtestGradient -> Bool
  (let [(ctrfRaw "{\"results\":{\"summary\":{\"tests\":6,\"passed\":4,\"failed\":2,\"pending\":0,\"skipped\":0,\"other\":0}}}") (summary (mc/parseCtrfSummary ctrfRaw)) (progress summary.progressRatio) (loss (mc/computeScalarLoss "subtest-failure" (- 1.0 progress) 0.0))] (do (assert (> progress 0.5) "progress ratio reflects 4/6 passed subtests (> 0.5)") (assert (< progress 1.0) "progress ratio reflects incomplete resolution (< 1.0)") (assert (< loss.normalizedLoss 0.5) "ceiling loss is reduced below 0.5 on partial pass") true))

fn testSolvableChallengePass -> Bool
  (let [(trace (sr/runEpistemicTask "TB4-SOLV-01" 2 10000))] (do (assert trace.passed "solvable task TB4-SOLV-01 passes verification") (assert (= trace.mode 2) "mode 2 standard epistemic loop executed") (assert (< trace.totalTokens 2000) "token economy strictly below 2000 tokens") true))

fn runTests -> Bool
  (do (testGatewayConfig) (testThinkQuarantine) (testEshInterception) (testBudgetCeilingEnforcement) (testCtrfSubtestGradient) (testSolvableChallengePass) true)
