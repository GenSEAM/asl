---
name: skyloom
description: Universal Inter-Agent Communication Protocol & Resilient Swarm Mesh. Use when coordinating multiple AI agents, exchanging structured tasks, communicating across agent boundaries (aware vs unaware models), or routing messages via SkyLoom CLI, Wasm SDK, or MCP server.
---

# SkyLoom Agent Protocol Skill

SkyLoom is the high-performance, typed inter-agent communication protocol for **AgentScript (ASL)**.
It eliminates hallucinated schemas, prevents silent message loss, and bridges advanced ASL-native agents with vanilla LLM agents.

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
- Format: Native ASL S-expressions `(loom:frame :v 1 :id ... :type "DATA" :body (...))`
- Zero schema drift, validated directly against the ASL type checker.
- Direct 1:1 or topic broadcast.

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
- Status returns: `{"status": "QUEUED", "errorCode": 1002}`.
- You do NOT need to retry in a tight loop. When the counterparty joins, SkyLoom automatically drains the mailbox and delivers your message.
- You will receive a `peer_joined` / `lonely:resolved` event.

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
```lisp
(loom:handoff :v 1 :id "handoff-001" :from "orchestrator" :to "agent-coder"
  :task "build_feature" :cwd "packages/rate" :owns ["src/main.asl"] :gate "asl check")
```
When complete, the worker yields back:
```lisp
(loom:yield :v 1 :id "yield-001" :reply-to "handoff-001" :status "ok"
  :verdict "PASS (0 errors)" :artifacts ["src/main.asl"])
```
The Zero-Leak Mesh Firewall prevents the worker from receiving unrelated project chatter.
