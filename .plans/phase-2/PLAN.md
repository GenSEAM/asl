# Phase 2: Quantum State-Vector Simulator & Telemetry (`asl-quantum-telemetry-engine`)

## Goal
Implement a pure ASL state-vector simulation engine in `@genseam/asl-quantum` supporting up to 4 qubits (16 complex amplitudes), calculating exact state probabilities for Bell states, GHZ states, and quantum gate sequences without any external Python/C libraries.

## Work Items
1. **Complex Amplitudes & State Vector**:
   - `packages/asl-quantum/src/simulator.asl`: define `ComplexNum` (`:f re F64`, `:f im F64`), `StateVector` (`:f amplitudes (List ComplexNum)`, `:f num-qubits I64`).
   - Pure ASL unitary transformations:
     - Apply single-qubit Hadamard: $(|0\rangle + |1\rangle)/\sqrt{2}$ ($1/\sqrt{2} \approx 0.70710678$).
     - Apply two-qubit CNOT (controlled-X bit flip).
2. **Measurement Probabilities & Sampling**:
   - Calculate probability $P(x) = |\alpha_x|^2 = \text{re}^2 + \text{im}^2$.
   - For Bell state: verify $P(00) \approx 0.5$ and $P(11) \approx 0.5$, while $P(01) = 0$ and $P(10) = 0$.
3. **Integration in `quantum.asl`**:
   - Export `simulate-circuit [(c circ/QuantumCircuit)] -> StateVector`.
   - Export `state-probability [(sv StateVector) (basis-state I64)] -> F64`.
4. **Unit Test Suite**:
   - `packages/asl-quantum/tests/simulator_test.asl`: test Bell state simulation and amplitude probabilities.

## Acceptance Gate
```bash
node bin/asl test packages/asl-quantum/tests/simulator_test.asl
```
Must pass with 0 errors.
