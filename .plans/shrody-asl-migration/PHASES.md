# Shrody to AgentScript (ASL) Migration Plan (`asl-shrody-migration-v1`)

> **Source Reference Repository:** [`/Users/purplelephant/projects/shrody`](file:///Users/purplelephant/projects/shrody)  
> **Source Git Reference:** `main` @ `68414612635eee46705206760bdfb6fa619f6c68`  
> **Target Repository:** [`/Users/purplelephant/projects/asex`](file:///Users/purplelephant/projects/asex) (AgentScript Ecosystem)  
> **Package Location:** `packages/asl-shrody/`  
> **Goal:** Migrate Shrody's voice and coding agent capabilities into modular, testable, sandboxed AgentScript (ASL) packages running on the Wasm/FFI runtime. Eliminate architectural debt: OOM memory crashes, multi-second process launch lag, permission prompt spam, and brittle heuristic routing.

---

## 1. Architectural Debt & Bug Elimination (What to Rethink & NOT Transfer)

Before porting any code, we deliberately design out the flaws of the Node.js implementation:

| Area | Current Bug / Flaw in Shrody (`/Users/purplelephant/projects/shrody`) | Clean Redesign in AgentScript (`asex`) |
| :--- | :--- | :--- |
| **1. Memory & Process Sprawl (OOM)** | `src/sessions.js` spawns full external CLI agent processes (Claude Code / OpenCode on Node/V8) consuming 500MB–1.5GB RAM each. Session pooling retains them for 10 min (`DEFAULT_TTL_MS`). Multiple tasks cause system OOM crashes. | **Pure ASL Micro-Harness (`shrody/harness.asl`)**: Lightweight ReAct loop running in an isolated ASL/Wasm isolate with a strict 16MB RAM ceiling (`--memory 16`). Instant disposal after task completion. Zero subprocess bloat. |
| **2. Permission Prompt Spam** | Andy / agent constantly prompts the user for permission to write into `/tmp` or edit files in the workspace directory it was explicitly commanded to inspect or repair. | **Capability-Based Policy (`shrody/policy.asl`)**: Declarative WASI-style capability manifests. Workspace root and sandbox `/tmp` are pre-authorized by default. Zero interactive prompt spam for authorized paths; strict refusal for host escapes. |
| **3. Brittle Triage & Intent Splitting** | `src/frontline.js` and `src/wiring.js` use sprawling regular expressions and ad-hoc string checks. As observed, multi-aspect requests (e.g. "check weather in X and find info on Y") were falsely split into isolated tasks losing context. | **Typed Intent Grammar (`shrody/triage.asl`)**: Formal S-expression AST matcher with deterministic predicates. Encodes `@pcp:d-374e` natively to collapse multi-aspect questions into single execution frames. |
| **4. Heavy IPC & Context Bloat** | Streaming hundreds of KB of JSON schemas and terminal logs over stdio pipes saturates the Node.js event loop and blows LLM token budgets. | **ASN Compact Notation**: Tools and task context represented as tabular matrices (`([:id :name :role] [...])`) and constant pools, reducing token and payload size by 65–80%. |
| **5. Hardware Coupling** | Audio drivers (CoreAudio/SoX), Piper TTS child processes, and Ink React TUI are tangled with agent orchestration logic. | **Clean Host FFI Separation**: Host provides low-level capabilities via `(host-call "audio/speak" [...])`. Cognitive agent logic remains 100% pure, portable, and testable without hardware mocks. |

---

## 2. Target Package Structure in `asex`

```
packages/asl-shrody/
├── package.json
├── README.md
├── src/
│   ├── ffi.asl          # Low-level Host Capability & FFI bridge contract
│   ├── policy.asl       # Capability-based path sandboxing & permission rules
│   ├── triage.asl       # Intent parser, multi-query collapse, question routing
│   ├── dag.asl          # Task/subtask dependency graph & scheduler
│   ├── harness.asl      # Native ReAct micro-agent runner (replaces Claude Code for errands)
│   └── format.asl       # ASN matrix encoder for context and tool catalog
├── bridges/
│   └── host_bridge.js   # Thin Node.js/Wasm FFI adapter (Audio, Piper TTS, FS, Process)
└── test/
    ├── policy.test.js   # Sandbox and permission boundary tests
    ├── triage.test.js   # Ported Shrody frontline & benchcases test suite
    ├── dag.test.js      # Task dependency & parallel execution tests
    └── harness.test.js  # End-to-end errand execution & memory ceiling tests
```

---

## 3. Ordered & Testable Phases

### Phase 1: FFI Contract & Thin Host Bridge
- **Objective**: Define the bidirectional Host-Guest communication protocol between AgentScript and the host environment.
- **ASL Module**: `packages/asl-shrody/src/ffi.asl`
- **Host Bridge**: `packages/asl-shrody/bridges/host_bridge.js`
- **Contract**:
  - `(df host-call [(capability Str) (action Str) (payload Str)] -> (Result Str Str))`
  - Capabilities: `fs`, `exec`, `audio`, `llm`.
- **Verification Gate**:
  - `node --test packages/asl-shrody/test/ffi.test.js`
  - Verifies round-trip dispatch, error propagation, and memory leak absence over 10,000 calls.

### Phase 2: Capability-Based Policy & Zero-Spam Permissions
- **Objective**: Implement path containment and permission logic in ASL. Pre-authorize workspace root and `/tmp` without interactive prompting; block path traversal (`../`) and unauthorized system roots.
- **ASL Module**: `packages/asl-shrody/src/policy.asl`
- **Verification Gate**:
  - Port permissions test matrix from Shrody.
  - Test: writing to `$WORKSPACE/file.txt` -> `ALLOW_SILENT`.
  - Test: writing to `/tmp/scratch.log` -> `ALLOW_SILENT`.
  - Test: writing to `/etc/passwd` -> `DENY_STRICT`.
  - Gate command: `node --test packages/asl-shrody/test/policy.test.js`.

### Phase 3: Formal Intent Triage & Multi-Query AST Parser
- **Objective**: Port Shrody's routing rules (`@pcp:d-fe29`, `@pcp:d-1a1a`, `@pcp:d-374e`) into typed ASL pattern matching.
- **ASL Module**: `packages/asl-shrody/src/triage.asl`
- **Verification Gate**:
  - Port all 232 test cases from Shrody's `test/frontline.test.js` and `src/benchcases.js` (including setup actions, multi-aspect question collapse, and admin routing).
  - Gate command: `node --test packages/asl-shrody/test/triage.test.js` (100% pass, 0 regressions).

### Phase 4: Task DAG & Subtask Coordination Engine
- **Objective**: Implement deterministic task/subtask topology in ASL. Build dependency resolution, detect circular waits, and separate parallel executable tasks from sequential blockers.
- **ASL Module**: `packages/asl-shrody/src/dag.asl`
- **Verification Gate**:
  - Gate command: `node --test packages/asl-shrody/test/dag.test.js`.
  - Verifies DAG linearization, deadlock prevention, and task state transitions (`PENDING` -> `RUNNING` -> `DONE` / `FAILED`).

### Phase 5: Native ReAct Micro-Harness (Memory & Latency Cure)
- **Objective**: Implement a self-contained ReAct loop in ASL that executes errands, file reads, web lookups, and code inspections without spawning external heavyweight agent processes.
- **ASL Module**: `packages/asl-shrody/src/harness.asl`
- **Verification Gate**:
  - Benchmark memory and latency against Shrody's `sessions.js`:
    - Memory: ASL isolate <= 24MB RAM (vs Shrody Node child process >= 600MB).
    - Startup latency: <= 10ms (vs Shrody CLI spawn >= 2000ms).
  - Gate command: `node --test packages/asl-shrody/test/harness.test.js`.

### Phase 6: End-to-End Comparative Benchmark against Shrody
- **Objective**: Run identical task suites through both Shrody (Node.js) and `packages/asl-shrody` (ASL/Wasm).
- **Deliverables**: Comparative scoreboard artifact (`BENCHMARK_REPORT.md`):
  - Token consumption (ASN vs JSON).
  - Peak RSS memory under 5 concurrent tasks.
  - Total end-to-end task turnaround time.
- **Verification Gate**:
  - 0 OOM crashes.
  - Zero permission prompts for workspace and `/tmp` edits.
  - >= 60% token reduction.
