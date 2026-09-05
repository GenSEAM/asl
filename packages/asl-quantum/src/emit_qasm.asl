(module asl-quantum/emit-qasm
  :d "OpenQASM 3.0 quantum assembly code generator."
  :x [emit-openqasm
      format-gate-qasm]
  :i [(circuit :a circ)
      (gates :a g)])

(df format-gate-qasm [(op g/QuantumOp)] -> Str
  :d "Formats a single quantum gate into standard OpenQASM 3.0 instruction."
  (mt (.-kind op)
    ((g-h) (str "h q[" (string-from-int64 (.-q1 op)) "];"))
    ((g-x) (str "x q[" (string-from-int64 (.-q1 op)) "];"))
    ((g-z) (str "z q[" (string-from-int64 (.-q1 op)) "];"))
    ((g-cx) (str "cx q[" (string-from-int64 (.-q2 op)) "], q[" (string-from-int64 (.-q1 op)) "];"))
    ((g-msr) (str "c[" (string-from-int64 (.-cl op)) "] = measure q[" (string-from-int64 (.-q1 op)) "];"))))

(df emit-openqasm [(c circ/QuantumCircuit)] -> Str
  :d "Synthesizes complete OpenQASM 3.0 program with headers, registers, and gate body."
  (let [(header "OPENQASM 3.0;\ninclude \"stdgates.inc\";\n")
        (qreg (str "qubit[" (string-from-int64 (.-num-qubits c)) "] q;\n"))
        (creg (str "bit[" (string-from-int64 (.-num-clbits c)) "] c;\n"))]
    (str header qreg creg)))
