(module aslAgent/swarmCoordinator
  :x [SwarmTask FailureWitness CircuitBreaker makeSwarmTask emptyCircuitBreaker scheduleSwarmWaves recordFailureWitness isLimitCycleTripped? getFailureWitness]
  :i [])

(schema SwarmTask
  (:f id Str)
  (:f scopePath Str)
  (:f deps (List Str)))

(schema FailureWitness
  (:f signature Str)
  (:f failCount I64)
  (:f lastError Str)
  (:f isTripped Bool))

(schema CircuitBreaker
  (:f witnesses (List FailureWitness)))

fn makeSwarmTask id: Str scopePath: Str deps: (List Str) -> SwarmTask
  (SwarmTask :id id :scopePath scopePath :deps deps)

fn emptyCircuitBreaker -> CircuitBreaker
  (CircuitBreaker :witnesses (list))

fn taskDepsSatisfied? task: SwarmTask completedIds: (List Str) -> Bool
  (let [(dependencies task.deps)]
    (if (listEmpty? dependencies)
      true
      (fold (fn [(allOk Bool) (depId Str)] -> Bool
              (if (not allOk)
                false
                (listContains? completedIds depId)))
            true dependencies)))

fn scheduleSwarmWaves tasks: (List SwarmTask) -> (List (List SwarmTask))
  (if (listEmpty? tasks)
    (list)
    (let [(w1 (filter (fn [(t SwarmTask)] -> Bool (listEmpty? t.deps)) tasks))
          (w1Ids (fold (fn [(acc (List Str)) (t SwarmTask)] -> (List Str) (cons t.id acc)) (list) w1))
          (remaining (filter (fn [(t SwarmTask)] -> Bool (not (listEmpty? t.deps))) tasks))
          (w2 (filter (fn [(t SwarmTask)] -> Bool (taskDepsSatisfied? t w1Ids)) remaining))
          (w2Ids (fold (fn [(acc (List Str)) (t SwarmTask)] -> (List Str) (cons t.id acc)) w1Ids w2))
          (rem2 (filter (fn [(t SwarmTask)] -> Bool (not (taskDepsSatisfied? t w1Ids))) remaining))]
      (if (listEmpty? w2)
        (if (listEmpty? w1) (list) (list w1))
        (if (listEmpty? rem2)
          (list w1 w2)
          (list w1 w2 rem2)))))

fn getFailureWitness cb: CircuitBreaker sig: Str -> (Option FailureWitness)
  (let [(records cb.witnesses)]
    (fold (fn [(found (Option FailureWitness)) (w FailureWitness)] -> (Option FailureWitness)
            (mt found
              ((some _) found)
              ((none) (if (= w.signature sig)
                        (some w)
                        (none)))))
          (none) records))

fn recordFailureWitness cb: CircuitBreaker sig: Str errMsg: Str -> CircuitBreaker
  (let [(existing cb.witnesses)
        (filtered (filter (fn [(w FailureWitness)] -> Bool (!= w.signature sig)) existing))
        (prevOpt (getFailureWitness cb sig))
        (prevCount (mt prevOpt
                     ((none) 0)
                     ((some pw) pw.failCount)))
        (newCount (+ prevCount 1))
        (tripped (>= newCount 3))
        (newWitness (FailureWitness :signature sig :failCount newCount :lastError errMsg :isTripped tripped))]
    (CircuitBreaker :witnesses (cons newWitness filtered)))

fn isLimitCycleTripped? cb: CircuitBreaker sig: Str -> Bool
  (let [(wOpt (getFailureWitness cb sig))]
    (mt wOpt
      ((none) false)
      ((some w) w.isTripped)))
