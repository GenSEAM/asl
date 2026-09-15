# Engineering Specification: Agent Process Manager (APM), Context-Bypass Execution & Mesh RPC
**Document ID:** SPEC-2026-APM-MESH-v1.0  
**Classification:** Core Runtime & Inter-Agent Coordination Standard  
**Target Subsystems:** `asl-sh`, `agent-bus`, `asl-mem`, `asl-text`, `web-api-search`  
**Related Specs:** `CONTEXT_LIFECYCLE_AND_INTENT_GRAPH_SPEC.md`, `LARGE_CODEBASE_INTELLIGENCE_AND_DEPENDENCY_SPEC.md`

---

## 1. Executive Summary & Core Invariants

Traditional AI coding harnesses suffer from two structural architectural flaws:
1. **Context Flooding:** Subprocesses (`npm install`, `cargo build`, `pytest`, dev servers) emit tens of thousands of log lines. Draining them into the LLM context poisons attention, spikes latency, and exhausts context windows.
2. **Untyped Process & Service Chaos:** Agents repeatedly run brittle OS commands (`ps aux | grep`, `lsof -i`, `kill -9`) to manage servers, causing PID collisions, zombie processes, and cross-platform breakage.

This specification formalizes **APM (Agent Process Manager)** and **Mesh Capability Discovery**:
- **OOB (Out-of-Band) Display Bypass:** Raw process output streams directly to the user terminal/PTY in real time; the LLM receives only a compact semantic receipt (`ProcessReceipt`, $\le 80$ tokens).
- **Two-Tier Bounded Spooling:** Sliding in-memory ring buffer (RAM, 200 lines) + ephemeral circular disk spool (`/tmp/asl-proc-*.spool`, 10MB hard cap, automatic unlink on exit).
- **Process as a Mesh Node (`agent-bus`):** Processes register directly in the swarm mesh routing table (`ProcessNode`). Status, memory RSS, and bound ports are queried in sub-milliseconds without OS shell commands.
- **Mesh Capability Discovery & Handshake:** P2P protocol handshake (`:hello`) where nodes (IDE, agents, workers) declare supported standard and custom RPC procedures (`ProcedureSpec`).
- **Git-Native Memory (`.asl/mem/`) & Intent Ledger:** Eradication of legacy `ai-docs/` and `.pcp/`. All governance, intents, desired outcomes, and AST traceability live in `.asl/mem/` as Git-branch-aware ASN records.

---

## 2. Stream Architecture: Out-of-Band (OOB) Bypass

```
                       ┌────────────────────────────────┐
                       │   Spawned Subprocess (STDOUT)  │
                       └───────────────┬────────────────┘
                                       │ Raw byte stream
                                       ▼
                       ┌────────────────────────────────┐
                       │     APM Stream Multiplexer     │
                       └───────┬────────────────┬───────┘
                               │                │
            ┌──────────────────┴──┐          ┌──┴───────────────────┐
            │  USER DISPLAY CHANNEL │        │  AGENT CONTEXT CHANNEL│
            │   (PTY / Terminal)  │          │   (Semantic Reducer)  │
            └──────────┬──────────┘          └──┬───────────────────┘
                       │                        │
             Direct raw streaming          Compact ASN Receipt (<80 tokens)
             User sees full progress       (:proc-receipt
             Zero LLM tokens consumed        :exit 0
                                             :duration-ms 1840
                                             :peak-rss-mb 64
                                             :summary "Build succeeded")
```

### 2.1. Semantic Process Receipt (`ProcessReceipt`)
In `asl/packages/asl-sh/src/core/process.asl`:

```lisp
(dfs ProcessReceipt
  (:f exit-code   I64 "Process return code (0 = success)")
  (:f duration-ms I64 "Execution duration in milliseconds")
  (:f peak-rss-mb I64 "Peak memory resident set size in megabytes")
  (:f spool-path  Str "Filesystem path to ephemeral disk spool")
  (:f summary     Str "Compact diagnostic string (<100 tokens, errors only)"))
```

---

## 3. Two-Tier Spooling & Resource Guards

1. **Tier 1 (In-Memory Ring Buffer):**
   - Retains the most recent 200 lines ($< 64$ KB) in resident RAM for instant tail inspection via `asl rpc '(:batch (:proc :tail :id ...))'`.
2. **Tier 2 (Ephemeral Disk Spool):**
   - Raw output streams to `/tmp/asl-proc-<pid>-<nonce>.spool`.
   - **Hard Cap (10 MB):** Circular FIFO truncation prevents disk exhaustion.
   - **Auto-Unlink Guarantee:** File descriptor cleanup removes the file immediately on process exit or agent teardown.
3. **Resource Watchdogs:**
   - **RSS Ceiling:** Processes exceeding configured memory limit (e.g. 512 MB) receive `SIGTERM` $\rightarrow$ `SIGKILL` with event `:oom-killed`.
   - **Deadlock Watchdog:** 10s idle ceiling on blocking stdin pipes.
   - **Port Guard:** Automated detection of bound network ports (`:port-bound 3000`), notifying the mesh instantly without `sleep` loops.

---

## 4. Mesh Process Registry (`agent-bus`)

Processes are first-class resource nodes in the `agent-bus` routing table:

```lisp
(dfs ProcessNode
  (:f id          Str        "Symbolic identifier, e.g. :dev-server")
  (:f pid         I64        "Operating system PID")
  (:f started-at  I64        "Epoch timestamp preventing PID-recycling collisions")
  (:f bound-ports (List I64) "Detected active listening ports e.g. [3000]")
  (:f is-healthy  Bool       "Healthcheck status flag")
  (:f spool-path  Str        "Path to active circular disk spool")
  (:f task-id     Str        "Owning roadmap phase or task ID"))
```

### 4.1. Zero-OS Process Introspection
Swarm agents and IDEs query the mesh directly:
```lisp
asl rpc '(:batch (:proc :list))'
```
Returns a structured ASN summary without invoking `ps aux`, `lsof`, or `netstat`.

---

## 5. Mesh Capability Discovery & RPC Handshake

Nodes joining the `agent-bus` Unix Domain Socket emit a handshake packet declaring standard and custom capabilities:

```lisp
(dfs ProcedureSpec
  (:f name    Str        "Procedure identifier, e.g. :show-diff")
  (:f params  (List Str) "Required parameter keys")
  (:f is-safe Bool       "True if procedure has zero destructive side-effects")
  (:f doc     Str        "1-line intent and usage summary"))

(dfs SwarmPeer
  (:f agent-id   Str                 "Unique peer identifier")
  (:f role       Str                 "Peer role (orchestrator, ide-host, worker)")
  (:f proto-ver  I64                 "Wire protocol version")
  (:f status     AgentStatus         "Current status")
  (:f procedures (List ProcedureSpec) "Exported standard and custom RPC procedures"))
```

### 5.1. Graceful Fallback Policy
When an agent attempts to invoke a custom procedure (e.g. `:show-diff` in an IDE):
1. Query mesh roster via `(:mesh :who)`.
2. If an active peer exports `:show-diff`, dispatch the frame.
3. If no peer exists, gracefully fall back to headless terminal diff without failure.
4. If a target peer disconnects mid-flight, the mesh router emits an immediate `:ERR_PEER_OFFLINE` frame, preventing deadlocks.

---

## 6. Git-Native Governance & Intent Ledger (`.asl/mem/`)

- **Banishment of `ai-docs/`:** No `ai-docs/`, `.pcp/`, or open `docs/` paperwork in client repositories.
- **Client Footprint:** A single hidden directory `.asl/` (containing `config.asn` and `mem/`).
- **Global Tooling:** Managed via `~/.asl/config.asn` and `~/.eddie/config.asn`.
- **Intent Ledger (`.asl/mem/intent.asn`):**
  - Documents only non-obvious *Intents*, *Desired Outcomes*, *Use Cases*, and *Trade-offs* (`:why-not`).
  - Code contains zero comments and zero `@REQ` tags (Zero-Comment Invariant).
  - Traceability binds implicitly via canonical AST symbol paths (`module/function`).
