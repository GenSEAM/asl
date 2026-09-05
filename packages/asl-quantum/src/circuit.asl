(module asl-quantum/circuit
  :d "Quantum circuit representations, register allocation, and pipeline builder."
  :x [QuantumCircuit
      make-circuit
      add-op
      h
      x
      z
      cx
      msr]
  :i [(gates :a g)])

(dfs QuantumCircuit
  (:f num-qubits I64 "Total allocated quantum register count")
  (:f num-clbits I64 "Total allocated classical register count")
  (:f ops (List g/QuantumOp) "Sequential gate operation queue"))

(df make-circuit [(q I64) (c I64)] -> QuantumCircuit
  :d "Constructs an empty quantum circuit with specified qubit and classical bit widths."
  (QuantumCircuit :num-qubits q :num-clbits c :ops (list)))

(df add-op [(c QuantumCircuit) (op g/QuantumOp)] -> QuantumCircuit
  :d "Appends a quantum operation to the circuit pipeline."
  (QuantumCircuit
    :num-qubits (.-num-qubits c)
    :num-clbits (.-num-clbits c)
    :ops (list-append (.-ops c) (list op))))

(df h [(c QuantumCircuit) (q I64)] -> QuantumCircuit
  :d "Applies Hadamard gate to qubit."
  (add-op c (g/make-h q)))

(df x [(c QuantumCircuit) (q I64)] -> QuantumCircuit
  :d "Applies Pauli-X NOT gate to qubit."
  (add-op c (g/make-x q)))

(df z [(c QuantumCircuit) (q I64)] -> QuantumCircuit
  :d "Applies Pauli-Z phase gate to qubit."
  (add-op c (g/make-z q)))

(df cx [(c QuantumCircuit) (ctrl I64) (target I64)] -> QuantumCircuit
  :d "Applies Controlled-NOT gate across control and target qubits."
  (add-op c (g/make-cx ctrl target)))

(df msr [(c QuantumCircuit) (q I64) (cl I64)] -> QuantumCircuit
  :d "Measures target qubit into target classical bit."
  (add-op c (g/make-msr q cl)))
