(module asl-quantum/quantum
  :d "AgentScript Quantum Computing DSL: Circuit builder, universal quantum gates, and OpenQASM synthesis."
  :x [build-bell-pair
      build-ghz-state]
  :i [(circuit :a circ)
      (gates :a g)
      (emit-qasm :a qasm)])

(df build-bell-pair [] -> circ/QuantumCircuit
  :d "Constructs standard maximally entangled 2-qubit Bell EPR pair (|00> + |11>) / sqrt(2)."
  (let [(c0 (circ/make-circuit 2 2))
        (c1 (circ/h c0 0))
        (c2 (circ/cx c1 0 1))
        (c3 (circ/msr c2 0 0))
        (c4 (circ/msr c3 1 1))]
    c4))

(df build-ghz-state [] -> circ/QuantumCircuit
  :d "Constructs 3-qubit Greenberger-Horne-Zeilinger entangled state (|000> + |111>) / sqrt(2)."
  (let [(c0 (circ/make-circuit 3 3))
        (c1 (circ/h c0 0))
        (c2 (circ/cx c1 0 1))
        (c3 (circ/cx c2 1 2))]
    c3))
