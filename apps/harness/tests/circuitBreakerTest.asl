(module aslHarness/circuitBreakerTest :x [testCircuitBreakerLifecycle testEscalationTiers runTests] :i [(circuitBreaker :a cb)])

fn testCircuitBreakerLifecycle -> Bool
  (let [(c0 (cb/makeCircuitBreaker 3))] (assert (not (cb/isTripped? c0)) "New breaker must be closed") (let [(c1 (cb/recordFailure c0 "Error 1"))] (assert (not (cb/isTripped? c1)) "1 failure must not trip threshold 3") (let [(c2 (cb/recordFailure c1 "Error 2"))] (assert (not (cb/isTripped? c2)) "2 failures must not trip threshold 3") (let [(c3 (cb/recordFailure c2 "Error 3"))] (assert (cb/isTripped? c3) "3 failures must trip circuit") (assert (= (cb/resolveEscalation c3) "approver") "Tier 1 must escalate to approver") (let [(cClean (cb/recordSuccess c3))] (assert (not (cb/isTripped? cClean)) "Success must reset circuit") true)))))

fn testEscalationTiers -> Bool
  (let [(c0 (cb/makeCircuitBreaker 2)) (c1 (cb/recordFailure c0 "Err 1")) (c2 (cb/recordFailure c1 "Err 2")) (c3 (cb/recordFailure c2 "Err 3")) (c4 (cb/recordFailure c3 "Err 4"))] (assert (cb/isTripped? c2) "Breaker tripped at count 2") (assert (= (cb/resolveEscalation c2) "approver") "Count 2 escalates to approver") (assert (= (cb/resolveEscalation c4) "human-operator") "Count 4 escalates to human operator") true)

fn testResetCircuit -> Bool
  (let [(c0 (cb/makeCircuitBreaker 2)) (c1 (cb/recordFailure (cb/recordFailure c0 "err") "err"))] (assert (cb/isTripped? c1) "Tripped") (let [(c2 (cb/resetCircuit c1))] (assert (not (cb/isTripped? c2)) "Reset should close circuit") true))

fn runTests -> Bool
  (and (testCircuitBreakerLifecycle) (and (testEscalationTiers) (testResetCircuit)))
