# ASL Process Guard: Supervisor, Ephemeral Ring Buffer & Token Stream Reducer (RTK)

> **Vision**: An AgentScript-native process supervision, out-of-band buffering, and token stream reduction toolkit (`asl-proc-guard` / `@genseam/asl-sh` supervisor). Intercepts all command launches, buffers raw streams into an ephemeral in-memory ring buffer with OOM protection, detects silent stalls and interactive stdin prompts, generates token-compressed semantic summaries with inline adaptive returns, and enables out-of-band offset/grep/query navigation.

---

## 1. Architectural Foundations

### 1.1 Pure Functional ASL Core vs. Host Bridge
ASL Core v0.2 enforces totality, pure functional evaluation, and deterministic execution without native async/await or OS signal traps.
- **ASL Module (`.asl`)**: Owns the algebraic state machine, reduction algorithms, ANSI stripping, diagnostic parsing into AST records, chunking, and offset calculations:
  ```lisp
  (df step [(state SupervisorState) (event SupervisorEvent)] -> SupervisorState)
  ```
- **Host Bridge (TypeScript / Node.js / WASI)**: Owns subprocess spawning (`child_process.spawn`), PTY allocation, unbuffered environment variable injection (`PYTHONUNBUFFERED=1`), raw byte streams, and OS signal dispatching (`SIGINT`, `SIGKILL`).

### 1.2 Terminal Emulation & Carriage Return (`\r`) Handling
Terminal tools frequently redraw spinners or download bars using carriage returns (`\r`). Splitting naively on `\n` generates thousands of redundant lines. The ASL reducer simulates terminal line overwrites, collapsing `\r` updates down to the final state of each line before emitting.

### 1.3 Disambiguating Interactive Prompts vs. Silence Stalls
- **Interactive Prompt Detector (`AwaitingStdin`)**: Continuously monitors the stream tail without a trailing newline. Matches against interactive patterns (`? `, `[y/N]`, `password:`, `(yes/no)`), transitioning to `AwaitingStdin` and alerting the agent to pass input via `proc_send_input`.
- **Silence Watchdog (`QuietStall`)**: When output stops for $T_{\text{quiet}} \ge 10$s without matching a prompt, transitions to `QuietStall`, informing the agent that execution is continuing silently without killing the process.

### 1.4 Bounded Ring Buffer & OOM Protection
To prevent unbounded memory growth from commands spewing gigabytes:
- Hard ceiling per process buffer (10 MB / 10,000 lines).
- **Head/Tail Retention**: Preserves the first 500 lines (invocation and config headers) and the last 1,500 lines (crash stack trace and failure site), collapsing the middle into an eviction marker: `"... [42,000 lines evicted from in-memory ring buffer] ..."`.
- Ephemeral TTL eviction: Buffers automatically purge 15 minutes after process termination unless pinned.

### 1.5 Inline Adaptive Digest
Avoids the $N+1$ tool-call penalty:
- Fast short runs ($<2$s and $<40$ lines) return clean output immediately in the initial tool response.
- Heavy or long-running commands return a structured semantic summary card with diagnostics and navigation tool handles (`proc_slice`, `proc_grep`, `proc_query`).

### 1.6 Forced Routing with Justified Bypass
All commands in the agent harness route through the supervisor by default. `--bypass-reduction` is permitted only with a mandatory `bypass_reason` ($\ge 10$ characters) that is audited in execution logs.

---

## 2. Detailed Phase Specifications

### Phase 1: ASL Stream Reducer Core & Semantic Folding Engine
- **Goal**: Pure ASL modules for ANSI sequence stripping, `\r` carriage return / spinner collapsing, duplicate-line suppression, head/tail retention windowing, and semantic diagnostic extraction (Rust `rustc`, TypeScript `tsc`, Python tracebacks, test failures) into structured ASL records.
- **Paths**: `packages/asl-sh/src/reducer.asl`, `packages/asl-sh/src/ansi.asl`, `packages/asl-sh/src/diagnostics.asl`
- **Failing Gate / Acceptance Criterion**:
  `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-sh/src/reducer.asl`

### Phase 2: In-Memory Ring Buffer & Offset Navigator Schema in ASL
- **Goal**: Pure ASL data models and algorithms for bounded chunked stream spools, 10MB/10k line ceiling enforcement, middle-eviction markers, separate stdout/stderr channels, windowed offset pagination (`slice`), and line/byte indexation.
- **Paths**: `packages/asl-sh/src/spool.asl`, `packages/asl-sh/src/navigator.asl`
- **Failing Gate / Acceptance Criterion**:
  `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-sh/src/spool.asl`

### Phase 3: Watchdog & Process Supervisor State Machine in ASL
- **Goal**: Lifecycle state machine in ASL integrating with `asl-fsm` patterns (`Starting`, `Streaming`, `QuietStall`, `AwaitingStdin`, `Exited`, `Killed`), with event transitions, prompt-pattern matcher, silence timers, and stdin injection commands.
- **Paths**: `packages/asl-sh/src/supervisor.asl`, `packages/asl-sh/src/events.asl`
- **Failing Gate / Acceptance Criterion**:
  `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-sh/src/supervisor.asl`

### Phase 4: Host Bridge & Subprocess Execution Driver (Node.js & WASI)
- **Goal**: Host runtime bridge executing subprocesses via PTY/pipes with unbuffered stream flags, feeding raw chunks to the bounded in-memory ring buffer, tracking silence timeouts, and signaling state transitions to the ASL supervisor.
- **Paths**: `packages/asl-sh/bridge/host_process.ts`, `packages/asl-sh/bridge/ring_buffer.ts`, `packages/asl-sh/bridge/stream_watcher.ts`
- **Failing Gate / Acceptance Criterion**:
  `npx tsx packages/asl-sh/tests/test_host_supervisor.ts`

### Phase 5: Stream Querying, Grep & Structured Filter Engine (jq/yq Semantics)
- **Goal**: In-buffer regex/glob search (`grep_stream`) returning matches with context windows without flushing the whole buffer to context, plus structured path queries (jq/yq style) over JSON/YAML outputs using `asl-codec`.
- **Paths**: `packages/asl-sh/src/query.asl`, `packages/asl-sh/bridge/query_engine.ts`, `packages/asl-sh/tests/test_query.ts`
- **Failing Gate / Acceptance Criterion**:
  `npx tsx packages/asl-sh/tests/test_query.ts`

### Phase 6: Agent Harness Plugin & Policy Enforcement (Forced Routing & Justified Bypass)
- **Goal**: Integrate supervisor into the agent harness as a command execution plugin. Enforce default reduction, implement Inline Adaptive Digest (immediate return for quick small outputs), expose inspection tools (`proc_status`, `proc_read_slice`, `proc_search`, `proc_send_input`), and validate required `bypass_reason` ($\ge 10$ chars).
- **Paths**: `packages/asl-harness/src/plugins/proc_guard.asl`, `packages/asl-harness/bridges/proc_guard_plugin.ts`
- **Failing Gate / Acceptance Criterion**:
  `npx tsx packages/asl-harness/tests/test_proc_guard_plugin.ts`

### Phase 7: End-to-End Benchmarks, Stress Tests & Token Reduction Verification
- **Goal**: Verification suite testing: OOM protection against infinite byte streams (`yes` / `cat /dev/urandom`), interactive prompt response (`[y/N]` unblocking via `proc_send_input`), silence watchdog alerting, and token savings benchmarking on real builds (`cargo build`, `npm install`, `pytest`).
- **Paths**: `packages/asl-sh/tests/bench_token_reduction.ts`, `packages/asl-sh/tests/test_interactive_session.ts`, `packages/asl-sh/tests/test_stress_buffer.ts`
- **Failing Gate / Acceptance Criterion**:
  `npm run --prefix packages/asl-sh bench:reduction && npx tsx packages/asl-sh/tests/test_stress_buffer.ts`
