---
name: skyloom
description: Universal Inter-Agent Communication Protocol & Resilient Swarm Mesh. Use when coordinating multiple AI agents, exchanging structured tasks, communicating across agent boundaries (aware vs unaware models), or routing messages via SkyLoom CLI, Wasm SDK, or MCP server.
---

# SkyLoom Agent Protocol Skill

SkyLoom is the session layer of the AgentScript wire protocol: peer registry, dialect negotiation,
delivery guarantees, and context-isolated handoff. It eliminates hallucinated schemas, prevents
silent message loss, and bridges ASL-native agents with vanilla LLM agents.

**The normative specification is `docs/AGENTIC_PROTOCOL.md`** — Part I for the frame layer
(sigils, value syntax, error taxonomy), Part II for everything this skill uses. When this skill
and that document disagree, the document wins.

## 1. Quick Start

### Connecting to the Mesh
Agents connect to the local SkyLoom mesh using either MCP tools or the CLI:

#### Via MCP Server
Call the `skyloom_connect` tool:
```json
{
  "agentId": "agent-planner",
  "channels": ["plans", "tasks/code"],
  "isAslNative": true
}
```

#### Via CLI
```bash
asl loom join --id agent-planner --channels "plans,tasks/code"
```

---

## 2. Asymmetric Scenarios: Aware vs. Unaware Peers

### Scenario A: Both Agents Know SkyLoom (Native Mode)
- Four dialects carry the same frame: `asl/v1` (verbose, self-describing), `asl/coord`
  (coordination and handoff, fully typed), `compact/v1` (positional `SK1|...`, the default),
  `polyglot/v1` (markdown and JSON, for unaware peers).
- `asl/v1` shape: `(loom:frame :v 1 :id "msg-01" :from "a" :to "b" :dialect "asl/v1" :ts 1788350000000 :type "DATA" :body {"action":"compile"})`.
  The envelope is an s-expression; the **body is JSON today** and becomes ASN when
  `docs/ASN_SPEC.md` lands. `asl/coord` is the one dialect that is already typed end to end.
- Frame types: `HANDSHAKE DATA HANDOFF YIELD SPAWN ACK NACK PING PONG RENDEZVOUS LEAVE`.
  Liveness is `PING`/`PONG`, not `HEARTBEAT_PING`/`HEARTBEAT_PONG`.
- Keys are kebab-case with the unit in the name: `:timeout-ms`, never `:timeout`, `:t-out`
  or `:timeout_ms`.

### Scenario B: Talking to an Unaware Counterparty (Polyglot Mode)
When sending a task to an agent that does NOT have the SkyLoom skill:
1. Call `skyloom_bootstrap_peer` to obtain the prompt primer:
   ```json
   { "senderId": "agent-orchestrator", "targetPeerId": "vanilla-claude" }
   ```
2. Wrap your message in the Polyglot envelope:
   ```markdown
   <!-- SKYLOOM_HEADER: {"v":1,"id":"msg-01","from":"orchestrator","to":"vanilla-claude","type":"DATA"} -->
   [SkyLoom Autonomous Protocol Primer]
   Please execute the requested task and reply with a structured JSON code block:
   ```json
   { "action": "audit_code", "files": ["src/index.ts"] }
   ```
   <!-- SKYLOOM_FOOTER -->
   ```
3. When the peer replies with conversational text + JSON, the SkyLoom router automatically unwraps it back into a nominal typed `LoomFrame`.

---

## 3. Lonely Agent & Offline Peer Handling

If you send a message to a peer that is not yet online or has crashed:
- SkyLoom buffers the message in the **Mailbox Queue** (with TTL).
- Status returns: `{"status": "QUEUED", "errorCode": 1002}` (`:lonely-queued`).
- You do NOT need to retry in a tight loop. When the counterparty joins, SkyLoom automatically drains the mailbox and delivers your message.
- You will receive a `peer_joined` / `lonely:resolved` event.

### Error codes

One closed taxonomy, shared by frame-layer `:err` keywords and session-layer `NACK` codes.

| Keyword | Code | Keyword | Code |
|---|---|---|---|
| `:peer-unreachable` | 1001 | `:timeout` | 1006 |
| `:lonely-queued` | 1002 | `:stalled` | 1007 |
| `:dialect-unsupported` | 1003 | `:dead-letter` | 1008 |
| `:decode-failed` | 1004 | `:scope-violation` | 1009 |
| `:type-mismatch` | 1005 | `:handoff-rejected` | 1010 |

---

## 4. MCP Tool Reference

| Tool | Purpose |
|---|---|
| `skyloom_connect` | Register this agent in the swarm mesh |
| `skyloom_send` | Send direct or channel broadcast messages |
| `skyloom_poll` | Drain inbox and fetch pending messages |
| `skyloom_peers` | Discover active agents and their capabilities |
| `skyloom_mailbox_status` | Check buffered offline messages |
| `skyloom_bootstrap_peer` | Generate instruction primer for vanilla LLMs |
| `skyloom_handoff` | Delegate task with directory scoping, owned files, and verification gate |
| `skyloom_yield` | Return task execution status and artifacts back to delegator |

---

## 5. Context-Isolated Handoff & Directory Scoping

To avoid $O(N^2)$ token explosions and context rot, do NOT broadcast full chat histories between agents. Instead, use context-isolated handoffs:

```bash
asl loom handoff --to agent-coder --task build_feature --cwd packages/rate --owns "src/main.asl" --gate "asl check"
```

The assignee receives a minimal S-expression:
```agp
(loom:handoff :v 1 :id "handoff-001" :from "orchestrator" :to "agent-coder"
  :ts 1788350000000 :task "build_feature" :cwd "packages/rate"
  :owns ["src/main.asl"] :gate "asl check" :budget 4000)
```
When complete, the worker yields back:
```agp
(loom:yield :v 1 :id "yield-001" :reply-to "handoff-001" :from "agent-coder"
  :to "orchestrator" :ts 1788350004000 :status "ok"
  :verdict "PASS (0 errors)" :artifacts ["src/main.asl"])
```
Reaching outside `:cwd` or writing a `:frozen` path is `:scope-violation` (1009); declining the
contract is `:handoff-rejected` (1010).
The Zero-Leak Mesh Firewall prevents the worker from receiving unrelated project chatter.
