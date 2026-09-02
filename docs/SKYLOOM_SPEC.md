# SkyLoom: Inter-Agent Communication Protocol Specification (v1.0)

## 1. Abstract & Motivation

Current multi-agent frameworks rely on untyped, high-entropy natural language chats or loose JSON blobs. This causes three pervasive failure modes:
1. **Schema Drift & Hallucination**: JSON keys get misspelled, nullability is unchecked, and prompt injection can alter structural contracts.
2. **Token Inefficiency**: Verbose JSON headers, escaped quotes, and conversational filler waste 40–70% of context tokens.
3. **Fragile Asymmetry**: When an advanced agent attempts to communicate with a vanilla model, the conversation either collapses or degrades into unstructured English chit-chat.

**SkyLoom** is an agent-to-agent protocol built on **AgentScript (ASL)** principles:
- **Zero-Drift Nominal Types**: All wire frames correspond directly to verified ASL structs (`dfs`) and enums (`dfe`).
- **Triple-Dialect Codec**:
  - `ASL_NATIVE`: Compact S-expressions `(loom:frame ...)` validated by the ASL type checker.
  - `COMPACT_TOKEN`: Ultra-high density positional representation for high-frequency subagent loops.
  - `POLYGLOT_JSON`: Self-describing JSON with conversational markdown framing for unprimed/unaware LLM peers.
- **Asymmetric Capability Negotiation**: Aware agents detect and automatically elevate or gracefully adapt to unaware peers.
- **Mesh & Swarm Native**: Dynamic discovery, topic routing, heartbeat supervision, and lonely-agent mailbox queues.

---

## 2. Frame Architecture

Every transmission on the SkyLoom wire is a **LoomFrame**:

```
+-------------------------------------------------------------------+
|                        LoomHeader                                 |
|  version: U16 | id: UUID | from: AgentId | to: AgentId            |
|  dialect: DialectTag | timestamp: I64 | reply_to: Option<UUID>     |
+-------------------------------------------------------------------+
|                        LoomPayload                                |
|  type: FrameType (Handshake | Data | Ack | Nack | Ping | Pong)    |
|  channel: Str | body: AnyTyped                                    |
+-------------------------------------------------------------------+
|                        LoomFooter (Optional)                      |
|  signature: Option<Str> | checksum: U32                           |
+-------------------------------------------------------------------+
```

### 2.1 Dialect Tags
- `asl/v1`: Native ASL S-expression AST format.
- `compact/v1`: Positional compressed token stream.
- `polyglot/v1`: JSON-RPC / Markdown hybrid with self-describing instructions.

### 2.2 Frame Types
- `HANDSHAKE`: Peer hello, capability exchange, supported dialects.
- `DATA`: Application-level message (Task, Query, Result, Stream Chunk).
- `ACK`: Positive acknowledgement of receipt/processing.
- `NACK`: Negative acknowledgement with standardized error code.
- `HEARTBEAT_PING` / `HEARTBEAT_PONG`: Liveness and latency monitoring.
- `RENDEZVOUS`: Lonely-agent presence announcement and mailbox check.
- `LEAVE`: Graceful connection termination.

---

## 3. Wire Formats

### 3.1 ASL Native Dialect (`asl/v1`)
```lisp
(loom:frame
  :v 1
  :id "msg-9f201"
  :from "orchestrator-main"
  :to "coder-sub-42"
  :type "DATA"
  :channel "tasks"
  :body (loom:task :action "compile" :target "wasm" :timeout_ms 5000))
```

### 3.2 Polyglot Dialect (`polyglot/v1`)
For unaware LLMs, the frame includes a natural language preamble that teaches the receiving agent how to parse and answer:
```markdown
<!-- SKYLOOM_HEADER: {"v":1,"id":"msg-9f201","from":"orchestrator-main","to":"coder-sub-42","type":"DATA","channel":"tasks"} -->
[SkyLoom Inter-Agent Protocol Frame]
You have received a structured task from agent `orchestrator-main`.
Please execute the requested action and reply with a SkyLoom JSON response.

```json
{
  "action": "compile",
  "target": "wasm",
  "timeout_ms": 5000
}
```
<!-- SKYLOOM_FOOTER: {"dialect":"polyglot/v1"} -->
```

---

## 4. Error Taxonomy

| Code | Name | Description |
|---|---|---|
| 1001 | `ERR_PEER_UNREACHABLE` | Target agent ID is not in active registry |
| 1002 | `ERR_LONELY_QUEUED` | No peer listening; frame buffered in mailbox |
| 1003 | `ERR_DIALECT_UNSUPPORTED` | Peer cannot decode requested dialect |
| 1004 | `ERR_DECODE_FAILED` | Malformed frame syntax or invalid checksum |
| 1005 | `ERR_TYPE_MISMATCH` | Body does not conform to expected ASL schema |
| 1006 | `ERR_TIMEOUT` | No ACK received within deadline |
| 1007 | `ERR_STALLED` | Peer accepted task but heartbeats ceased |
| 1008 | `ERR_DEAD_LETTER` | Frame exceeded max retry attempts |
