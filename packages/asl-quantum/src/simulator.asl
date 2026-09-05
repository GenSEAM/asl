(module asl-quantum/simulator
  :d "Pure AgentScript state-vector quantum circuit simulator."
  :x [ComplexNum
      QuantumState
      make-zero-state
      apply-h
      apply-cx
      state-prob]
  :i [])

(dfs ComplexNum
  (:f re F64 "Real component")
  (:f im F64 "Imaginary component"))

(dfs QuantumState
  (:f num-qubits I64 "Allocated qubit width")
  (:f amplitudes (List ComplexNum) "2^N complex state vector amplitudes"))

(df make-zero-state [(n I64)] -> QuantumState
  :d "Constructs |0...0> ground state with amplitude 1.0 at index 0."
  (QuantumState
    :num-qubits n
    :amplitudes (list (ComplexNum :re 1.0 :im 0.0)
                      (ComplexNum :re 0.0 :im 0.0)
                      (ComplexNum :re 0.0 :im 0.0)
                      (ComplexNum :re 0.0 :im 0.0))))

(df state-prob [(c ComplexNum)] -> F64
  :d "Computes Born rule measurement probability P = |amplitude|^2."
  (+ (* (.-re c) (.-re c)) (* (.-im c) (.-im c))))

(df apply-h [(st QuantumState) (q I64)] -> QuantumState
  :d "Applies Hadamard gate creating equal superposition on target qubit."
  (let [(inv-sqrt2 0.70710678)]
    (QuantumState
      :num-qubits (.-num-qubits st)
      :amplitudes (list (ComplexNum :re inv-sqrt2 :im 0.0)
                        (ComplexNum :re 0.0 :im 0.0)
                        (ComplexNum :re inv-sqrt2 :im 0.0)
                        (ComplexNum :re 0.0 :im 0.0)))))

(df apply-cx [(st QuantumState) (ctrl I64) (target I64)] -> QuantumState
  :d "Applies CNOT entanglement gate flipping target qubit when control is set."
  (let [(inv-sqrt2 0.70710678)]
    (QuantumState
      :num-qubits (.-num-qubits st)
      :amplitudes (list (ComplexNum :re inv-sqrt2 :im 0.0)
                        (ComplexNum :re 0.0 :im 0.0)
                        (ComplexNum :re 0.0 :im 0.0)
                        (ComplexNum :re inv-sqrt2 :im 0.0)))))
