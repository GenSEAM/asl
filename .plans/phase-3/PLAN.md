# Phase 3: Pure ASL Physics Reactor Core (`asl-physics-reactor-core`)

## Goal
Implement a single-source physics reactor engine in `packages/asl-vdom/src/physics_reactor.asl` written in pure AgentScript. It defines the N-body Coulomb repulsion, Hooke spring force, and velocity damping equations, serving as the single source of truth for both Wasm SIMD and JS web showcase targets.

## Work Items
1. **Physics Equations in Pure ASL**:
   - `packages/asl-vdom/src/physics_reactor.asl`:
     - Structures: `Particle` (`:f x F64`, `:f y F64`, `:f vx F64`, `:f vy F64`), `Spring` (`:f from-idx I64`, `:f to-idx I64`, `:f length F64`, `:f stiffness F64`).
     - Functions:
       - `coulomb-repulsion-force [(dx F64) (dy F64) (repulsion F64)] -> Pair`: calculates inverse-square repulsive force with softening factor to avoid division by zero.
       - `hooke-spring-force [(dx F64) (dy F64) (rest-len F64) (stiffness F64)] -> Pair`: calculates linear restorative spring force along edge.
       - `euler-step [(p Particle) (fx F64) (fy F64) (dt F64) (damping F64)] -> Particle`: updates velocity with damping and updates position.
2. **Unit Test Suite**:
   - `packages/asl-vdom/tests/physics_test.asl`:
     - Test that two overlapping particles experience repulsive force away from each other.
     - Test that a stretched spring pulls connected nodes inward.
     - Test that velocity damping reduces kinetic energy over successive steps.

## Acceptance Gate
```bash
node bin/asl test packages/asl-vdom/tests/physics_test.asl
```
Must pass cleanly with exit code 0.
