# Iteration: Native AgentScript Process & Shell Automation (`asl-sh-admin-toolkit-v1`)

**Goal**: Replace brittle Bash/sh scripts and Python subprocess boilerplate for autonomous agents with a secure, typed, pipeline-capable native AgentScript execution toolkit (`packages/asl-sh`) and CLI (`asl sh`).

## Phase Overview

### Phase 1: Core Process & Pipeline Scaffold (Completed)
- [x] Package manifest (`packages/asl-sh/asl.json`, `packages/asl-sh/package.json`).
- [x] Safe command vector builder (`packages/asl-sh/src/core/process.asl`).
- [x] Multi-stage process pipeline streaming (`packages/asl-sh/src/core/pipe.asl`).
- [x] Structured administrative logging & error formatting (`packages/asl-sh/src/core/log.asl`).
- [x] Native test suite (`packages/asl-sh/tests/sh_test.asl`).
- [x] Architectural decision `@pcp:d-446d` recorded and compiled.
- [x] Python subprocess runner engine (`tools/sh_runner.py` & `tools/tests/test_sh_runner.py`).
- [x] Native CLI integration (`asl sh <cmd> [args...]`, `asl sh --json`).

### Phase 2: Stream Redirection & Channel Multiplexing
- [ ] File stream redirection: stdout/stderr teeing to log files (`file-append`, `file-write`).
- [ ] Non-blocking process polling and timeout supervision.
- [ ] Environment variable inheritance and sandbox isolation.

### Phase 3: Agent Script Orchestration & Tasks
- [ ] Agent Task Runner (`asl task <task-name>` reading `asl.json` scripts section).
- [ ] Standardized exit code translation and diagnostic error synthesis.
- [ ] Integration with MCP tool `asl_exec_command`.
