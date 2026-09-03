# ASL Process Guard: Ordered Phases & Acceptance Criteria

Goal: Deliver an AgentScript-native process supervision, out-of-band ring buffering, and token stream reduction toolkit (`asl-proc-guard` / `@genseam/asl-sh` supervisor).

## Ordered Phases

### Phase 1: ASL Stream Reducer Core & Semantic Folding Engine
- **Objective**: Implement pure ASL modules for ANSI sequence stripping, `\r` carriage return / spinner collapsing, duplicate-line suppression, head/tail retention windowing, and semantic diagnostic extraction (Rust `rustc`, TypeScript `tsc`, Python tracebacks, test failures) into structured ASL records.
- **Paths**: `packages/asl-sh/src/reducer.asl`, `packages/asl-sh/src/ansi.asl`, `packages/asl-sh/src/diagnostics.asl`
- **Acceptance Criterion**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-sh/src/reducer.asl`

### Phase 2: In-Memory Ring Buffer & Offset Navigator Schema in ASL
- **Objective**: Implement pure ASL data models and algorithms for bounded chunked stream spools, 10MB/10k line ceiling enforcement, middle-eviction markers, separate stdout/stderr channels, windowed offset pagination (`slice`), and line/byte indexation.
- **Paths**: `packages/asl-sh/src/spool.asl`, `packages/asl-sh/src/navigator.asl`
- **Acceptance Criterion**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-sh/src/spool.asl`

### Phase 3: Watchdog & Process Supervisor State Machine in ASL
- **Objective**: Implement the lifecycle state machine in ASL integrating with `asl-fsm` patterns (`Starting`, `Streaming`, `QuietStall`, `AwaitingStdin`, `Exited`, `Killed`), with event transitions, prompt-pattern matcher, silence timers, and stdin injection commands.
- **Paths**: `packages/asl-sh/src/supervisor.asl`, `packages/asl-sh/src/events.asl`
- **Acceptance Criterion**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-sh/src/supervisor.asl`

### Phase 4: Host Bridge & Subprocess Execution Driver (Node.js & WASI)
- **Objective**: Build the host runtime bridge executing subprocesses via PTY/pipes with unbuffered stream flags, feeding raw chunks to the bounded in-memory ring buffer, tracking silence timeouts, and signaling state transitions to the ASL supervisor.
- **Paths**: `packages/asl-sh/bridge/host_process.ts`, `packages/asl-sh/bridge/ring_buffer.ts`, `packages/asl-sh/bridge/stream_watcher.ts`
- **Acceptance Criterion**: `npx tsx packages/asl-sh/tests/test_host_supervisor.ts`

### Phase 5: Stream Querying, Grep & Structured Filter Engine (jq/yq Semantics)
- **Objective**: Implement in-buffer regex/glob search (`grep_stream`) returning matches with context windows without flushing the whole buffer to context, plus structured path queries (jq/yq style) over JSON/YAML outputs using `asl-codec`.
- **Paths**: `packages/asl-sh/src/query.asl`, `packages/asl-sh/bridge/query_engine.ts`, `packages/asl-sh/tests/test_query.ts`
- **Acceptance Criterion**: `npx tsx packages/asl-sh/tests/test_query.ts`

### Phase 6: Agent Harness Plugin & Policy Enforcement (Forced Routing & Justified Bypass)
- **Objective**: Integrate supervisor into the agent harness as a command execution plugin. Enforce default reduction, implement Inline Adaptive Digest (immediate return for quick small outputs), expose inspection tools (`proc_status`, `proc_read_slice`, `proc_search`, `proc_send_input`), and validate required `bypass_reason` ($\ge 10$ chars).
- **Paths**: `packages/asl-harness/src/plugins/proc_guard.asl`, `packages/asl-harness/bridges/proc_guard_plugin.ts`
- **Acceptance Criterion**: `npx tsx packages/asl-harness/tests/test_proc_guard_plugin.ts`

### Phase 7: End-to-End Benchmarks, Stress Tests & Token Reduction Verification
- **Objective**: Verification suite testing: OOM protection against infinite byte streams (`yes` / `cat /dev/urandom`), interactive prompt response (`[y/N]` unblocking via `proc_send_input`), silence watchdog alerting, and token savings benchmarking on real builds (`cargo build`, `npm install`, `pytest`).
- **Paths**: `packages/asl-sh/tests/bench_token_reduction.ts`, `packages/asl-sh/tests/test_interactive_session.ts`, `packages/asl-sh/tests/test_stress_buffer.ts`
- **Acceptance Criterion**: `npm run --prefix packages/asl-sh bench:reduction && npx tsx packages/asl-sh/tests/test_stress_buffer.ts`

---

## Out of Scope & Rationale

- **Grammar Modifications to ASL Core**: The v0.2 core specification is frozen and normative. All reducer, state machine, and data structures use existing ASL types (`List`, `Map`, `Option`, `Result`, `dfs`, `dfe`).
- **Heavy External Background Daemons**: The supervisor runs as an in-process host bridge (TypeScript/Wasm), avoiding external background system daemons, Redis, or systemd services.
- **Permanent Log Storage**: The ring buffer is ephemeral with in-memory TTL (spool cache), not a permanent logging database. Long-term storage belongs to user logfiles.
