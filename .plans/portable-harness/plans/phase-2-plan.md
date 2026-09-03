# Phase 2 Plan: Pluggable Adapter Contracts & Isomorphic Host Effect Loop

## Goal
Implement the abstract ASL adapter contracts and the asynchronous TypeScript effect-dispatcher loop that executes effects across both Browser (in-memory WASI, Web Workers, Fetch) and Local Node/Native CLI environments.

## Work Items

### Item 1: Abstract ASL Adapter & Effect Specifications
- **File**: `packages/asl-harness/src/adapters.asl`
- **Specification**:
  - `dfe HostTarget`: `(:c browser [])`, `(:c node [])`, `(:c native [])`
  - `dfs AdapterCapability`: `name: Str`, `target: HostTarget`, `async-supported: Bool`
  - `dfe HostError`: `(:c timeout [ms: I64])`, `(:c network-error [msg: Str])`, `(:c denied [reason: Str])`, `(:c fatal [detail: Str])`
- **Gate**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-harness/src/adapters.asl`

### Item 2: Isomorphic TypeScript AgentHost Interface & Dispatcher
- **File**: `packages/asl-harness/bridges/host.ts`
- **Specification**:
  - Define `interface AgentHost`:
    - `dispatchEffect(effect: AgentEffect): Promise<AgentEvent>`
    - `step(event: AgentEvent): Promise<{ state: AgentState, effects: AgentEffect[] }>`
    - `runLoop(initialTask: string, onStep?: (s: AgentState) => void): Promise<AgentExecutionResult>`
  - Zero host leakage: handles errors gracefully and converts host exceptions into `AgentEvent.effect-done` error payloads.
- **Gate**: `npx tsc --noEmit packages/asl-harness/bridges/host.ts`

### Item 3: Browser Host Implementation
- **File**: `packages/asl-harness/bridges/browser_host.ts`
- **Specification**:
  - Uses `backend/ts/rt.ts` and in-memory WASI preview1 shim.
  - Implements Web Worker message channels for off-main-thread execution.
  - Implements browser fetch with configurable CORS proxy support and extension fallback.
  - Implements browser storage backed by IndexedDB / OPFS.
- **Gate**: `npx tsc --noEmit packages/asl-harness/bridges/browser_host.ts`

### Item 4: Node/Local Host Implementation
- **File**: `packages/asl-harness/bridges/node_host.ts`
- **Specification**:
  - Implements direct Node `fetch`, child process spawning (`asl-sh`), POSIX filesystem I/O, and SQLite store (`asl-sql`).
- **Gate**: `npx tsc --noEmit packages/asl-harness/bridges/node_host.ts`

### Item 5: Dual-Host Bridge Verification Test
- **File**: `packages/asl-harness/bridges/tests/test_host_bridge.ts`
- **Specification**:
  - Instantiates both `BrowserHost` (mocked DOM/worker) and `NodeHost`.
  - Runs a synthetic 3-step FSM loop: `idle` -> `planning` -> `acting` -> `completed`.
  - Asserts identical transition sequence and event emission across both hosts.
- **Gate**: `npx tsx packages/asl-harness/bridges/tests/test_host_bridge.ts`
