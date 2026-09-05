(module asl-quantum/gates
  :d "Quantum logic gates, unitary operations, and measurement primitives."
  :x [GateKind
      QuantumOp
      make-h
      make-x
      make-z
      make-cx
      make-msr]
  :i [])

(dfe GateKind
  (:c g-h [] "Hadamard superposition gate")
  (:c g-x [] "Pauli-X NOT bit-flip gate")
  (:c g-z [] "Pauli-Z phase-flip gate")
  (:c g-cx [] "Controlled-NOT entanglement gate")
  (:c g-msr [] "Single-qubit measurement into classical register"))

(dfs QuantumOp
  (:f kind GateKind "Operation type")
  (:f q1 I64 "Primary target qubit index")
  (:f q2 I64 "Secondary control qubit index")
  (:f cl I64 "Target classical bit index"))

(df make-h [(q I64)] -> QuantumOp
  :d "Creates Hadamard gate on target qubit."
  (QuantumOp :kind (g-h) :q1 q :q2 -1 :cl -1))

(df make-x [(q I64)] -> QuantumOp
  :d "Creates Pauli-X bit-flip gate on target qubit."
  (QuantumOp :kind (g-x) :q1 q :q2 -1 :cl -1))

(df make-z [(q I64)] -> QuantumOp
  :d "Creates Pauli-Z phase-flip gate on target qubit."
  (QuantumOp :kind (g-z) :q1 q :q2 -1 :cl -1))

(df make-cx [(ctrl I64) (target I64)] -> QuantumOp
  :d "Creates Controlled-NOT gate with control and target qubits."
  (QuantumOp :kind (g-cx) :q1 target :q2 ctrl :cl -1))

(df make-msr [(q I64) (cl I64)] -> QuantumOp
  :d "Creates measurement operation mapping qubit to classical register bit."
  (QuantumOp :kind (g-msr) :q1 q :q2 -1 :cl cl))
