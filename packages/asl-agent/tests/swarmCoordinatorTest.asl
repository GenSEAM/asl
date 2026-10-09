(module asl/packages/asl-agent/tests/swarmCoordinatorTest
  :x [runTests]
  :i [(aslAgent/swarmCoordinator :a sc)])

fn testWaveScheduling -> Bool
  (let [(tasks (list (sc/makeSwarmTask "t1" "asl/packages/asl-compiler" (list))
                     (sc/makeSwarmTask "t2" "asl/packages/asl-codegen" (list))
                     (sc/makeSwarmTask "t3" "agent-bus" (list "t1"))))
        (waves (sc/scheduleSwarmWaves tasks))]
    (do
      (assert (= (listLength waves) 2) "schedules exactly 2 parallel waves")
      (let [(w1 (optionOr (listHead waves) (list)))
            (w2 (optionOr (listGet waves 1) (list)))]
        (assert (= (listLength w1) 2) "wave 1 has 2 independent parallel tasks")
        (assert (= (listLength w2) 1) "wave 2 has dependent task")
        true)))

fn testLimitCycleCircuitBreaker -> Bool
  (let [(cb0 (sc/emptyCircuitBreaker))
        (sig "err-type-mismatch-Task56801-digest123")
        (cb1 (sc/recordFailureWitness cb0 sig "syntax error at token"))
        (cb2 (sc/recordFailureWitness cb1 sig "syntax error at token"))
        (cb3 (sc/recordFailureWitness cb2 sig "syntax error at token"))]
    (do
      (refute (sc/isLimitCycleTripped? cb1 sig) "1 failure does not trip breaker")
      (refute (sc/isLimitCycleTripped? cb2 sig) "2 failures do not trip breaker")
      (assert (sc/isLimitCycleTripped? cb3 sig) "3 identical failures trip breaker")
      (let [(witness (sc/getFailureWitness cb3 sig))]
        (assert (some? witness) "structured witness record is recorded")
        (mt witness
          ((none) (assert false "witness must exist"))
          ((some w)
            (do
              (assert (= w.failCount 3) "failure count is 3")
              (assert w.isTripped "witness status is tripped")
              true))))
      true))

fn runTests -> Bool
  (and (testWaveScheduling)
       (testLimitCycleCircuitBreaker))
