(module asl-quantum/tests/simulator_test
  :d "Unit test suite for pure ASL quantum state-vector simulation."
  :x [test-ground-state-prob
      test-bell-state-entanglement]
  :i [(simulator :a sim)])

(df test-ground-state-prob [] -> Bool
  :d "Verifies |00> ground state has probability 1.0."
  (let [(st (sim/make-zero-state 2))
        (p0 (sim/state-prob (list-head (.-amplitudes st))))]
    (== p0 1.0)))

(df test-bell-state-entanglement [] -> Bool
  :d "Verifies Bell state (|00> + |11>)/sqrt(2) has 50% probability in |00> and |11>."
  (let [(s0 (sim/make-zero-state 2))
        (s1 (sim/apply-h s0 0))
        (s2 (sim/apply-cx s1 0 1))
        (amps (.-amplitudes s2))
        (p00 (sim/state-prob (list-head amps)))]
    (and
      (> p00 0.49)
      (< p00 0.51))))
