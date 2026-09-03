# ASL Hierarchical Memory & Observability Architecture (v1.0)

> **Unverified figures.** Every performance number on this page is a projection or a
> vendor claim, not a measurement this repository can reproduce. `DESIGN.md` §5 requires a
> published number to be traceable to a gate; these are not, and are kept only as an order
> of magnitude to design against. `ROADMAP.md` §2 lists the figures that do have a gate,
> and `bench/token_frames.py` is the shape a claim has to take to earn a place here.

## 1. The Core Philosophy
Autonomous agents generate software at superhuman speed. Humans cannot and should not read thousands of lines of raw code. Instead, humans govern through **Hierarchical Observability** and **Deterministic Memory Layers**.

---

## 2. The 3-Tier Memory Topology

```
┌────────────────────────────────────────────────────────┐
│  Tier 3: Global Organization Memory (Cloud / S3 / Mesh) │
│  Shared standards, global skills, security policies    │
└──────────────────────────┬─────────────────────────────┘
                           │ Sync & Pull
┌──────────────────────────▼─────────────────────────────┐
│  Tier 2: Project Git-Native Memory (.asl/mem/)        │
│  Version-controlled ADRs, specs, requirements, changelog│
└──────────────────────────┬─────────────────────────────┘
                           │ Instant Vector Recall
┌──────────────────────────▼─────────────────────────────┐
│  Tier 1: In-Memory WASI Vector Cache (64KB Isolate)    │
│  Zero-server cosine similarity search in <0.04ms       │
└────────────────────────────────────────────────────────┘
```

---

## 3. The 4 Cognitive Abstraction Layers

1. **Strategic Layer (Constitution & Intent)**:
   - High-level goals, safety boundaries, non-negotiable architectural invariants (`CONSTITUTION.md`).
2. **Tactical Layer (Component Topology & Wire Mesh)**:
   - Inter-module contracts, S-expression type schemas, agent bus topologies.
3. **Operational Layer (Git-Native Project Memory)**:
   - Architectural Decision Records (`.asl/mem/adr/`), test matrices, performance budgets.
4. **Physical Layer (Sub-Millisecond WASI Execution & Traces)**:
   - Memory isolates, I/O traces, flame graphs, and byte-level determinism.

---

## 4. Visual Inspection CLI: `asl inspect`
The `asl inspect` command launches a zero-dependency local browser observatory:
```bash
asl inspect           # Opens http://localhost:4174 visual cockpit
asl inspect --tui     # Terminal-based interactive topological TUI
asl inspect --audit   # Automated safety, bundle size, and health diagnostics
```
