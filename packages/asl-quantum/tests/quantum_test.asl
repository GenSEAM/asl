(module asl-quantum/tests/quantum_test
  :d "Unit test suite for Quantum DSL: circuit construction, gate application, and OpenQASM 3.0 generation."
  :x [test-bell-circuit
      test-ghz-circuit
      test-openqasm-header]
  :i [(quantum :a q)
      (circuit :a circ)
      (emit-qasm :a qasm)])

(df test-bell-circuit [] -> Bool
  :d "Verifies Bell pair circuit has 2 qubits and 2 classical bits."
  (let [(bell (q/build-bell-pair))]
    (and
      (== (.-num-qubits bell) 2)
      (== (.-num-clbits bell) 2))))

(df test-ghz-circuit [] -> Bool
  :d "Verifies GHZ state circuit has 3 qubits."
  (let [(ghz (q/build-ghz-state))]
    (== (.-num-qubits ghz) 3)))

(df test-openqasm-header [] -> Bool
  :d "Verifies synthesized OpenQASM contains version header and register declarations."
  (let [(bell (q/build-bell-pair))
        (code (qasm/emit-openqasm bell))]
    (and
      (string-contains? code "OPENQASM 3.0;")
      (string-contains? code "qubit[2] q;"))))
