(module aslHarness/circuitBreaker :x [CircuitState CircuitBreaker makeCircuitBreaker recordSuccess recordFailure isTripped? resolveEscalation resetCircuit] :i [])

(enum CircuitState (:c stClosed [] "Normal operating state: executions permitted") (:c stOpen [] "Tripped state: anti-thrash circuit open, execution suspended") (:c stHalfOpen [] "Probe state: testing recovery after cooldown"))

(schema CircuitBreaker (:f threshold I64) (:f failCount I64) (:f state CircuitState) (:f lastError Str) (:f tier I64))

fn makeCircuitBreaker threshold: I64 -> CircuitBreaker
  (CircuitBreaker :threshold threshold :failCount 0 :state (stClosed) :lastError "" :tier 0)

fn recordSuccess cb: CircuitBreaker -> CircuitBreaker
  (with cb :failCount 0 :state (stClosed) :lastError "" :tier 0)

fn recordFailure cb: CircuitBreaker err: Str -> CircuitBreaker
  (let [(newCount (+ cb.failCount 1)) (tripped? (>= newCount cb.threshold)) (newTier (if (>= newCount (* cb.threshold 2)) 2 (if tripped? 1 0))) (newState (if tripped? (stOpen) (stClosed)))] (with cb :failCount newCount :state newState :lastError err :tier newTier))

fn isTripped? cb: CircuitBreaker -> Bool
  (mt cb.state ((stOpen) true) ((stClosed) false) ((stHalfOpen) false))

fn resolveEscalation cb: CircuitBreaker -> Str
  (cond ((= cb.tier 2) "human-operator") ((= cb.tier 1) "approver") (true "none"))

fn resetCircuit cb: CircuitBreaker -> CircuitBreaker
  (makeCircuitBreaker cb.threshold)
