# Phase 6 Plan: Multi-Modal Tool Runtime Mesh

## Goal
Implement safe sandboxed tool invocation bridging ASL Nano contracts to host capabilities: Browser DOM actions (`asl-browser-plugin`), sandboxed shell execution (`asl-sh` / WASI runner), and agent mesh messaging (`asl-agent-bus` / `asl-skyloom`).

## Work Items

### Item 1: Multi-Modal Tool Specifications in ASL
- **File**: `packages/asl-harness/src/tools.asl`
- **Specification**:
  - `dfe ToolTarget`: `(:c browser-dom [])`, `(:c sandboxed-sh [])`, `(:c mesh-bus [])`, `(:c custom [name: Str])`
  - `dfs ToolSpec`: `name: Str`, `target: ToolTarget`, `description: Str`, `input-schema: Str`, `timeout-ms: I64`, `requires-confirmation: Bool`
  - `dfs ToolInvocation`: `call-id: Str`, `tool-name: Str`, `args-json: Str`
  - `dfs ToolResult`: `call-id: Str`, `success: Bool`, `output: Str`, `duration-ms: I64`
- **Gate**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-harness/src/tools.asl`

### Item 2: Tool Dispatcher & Security Sandbox Mesh
- **File**: `packages/asl-harness/bridges/tool_mesh.ts`
- **Specification**:
  - Browser DOM adapter: connects to `asl-browser-plugin` for DOM tree snapshotting, click, type, and evaluate.
  - Sandboxed Shell adapter: connects to `asl-sh` and Wasm runner with path jailing (zero host leaks) and execution timeout.
  - Mesh Bus adapter: connects to `asl-agent-bus` for inter-agent IPC via Unix socket / SSE / BroadcastChannel.
- **Gate**: `npx tsc --noEmit packages/asl-harness/bridges/tool_mesh.ts`

### Item 3: Tool Mesh Test Suite
- **File**: `packages/asl-harness/tests/test_tool_mesh.ts`
- **Specification**:
  - Tests dispatching mock DOM action, sandboxed shell command, and mesh bus packet.
  - Asserts path jailing prevents access outside designated workspace.
- **Gate**: `npx tsx packages/asl-harness/tests/test_tool_mesh.ts`
