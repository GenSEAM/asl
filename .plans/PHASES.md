# SkyLoom: Inter-Agent Communication Protocol & Resilient Mesh
## Phased Execution Plan (Audit-Hardened v2)

Derived from user requirements and rigorous gap analysis:
- **Maximum Language Showcase**: Core protocol frames, state machines, and validators implemented in native AgentScript (`skyloom.asl`) and executed via Wasm/TS.
- **Triple Access Modalities**: Native ASL SDK (`@genseam/asl-skyloom`), CLI (`asl loom`), and MCP Server (`asl-skyloom-mcp`).
- **Asymmetric Negotiation**: Seamless interaction between ASL-native aware agents and vanilla unaware LLM agents via self-describing polyglot envelopes & dynamic skill bootstrap.
- **Dynamic Swarm Topologies**: 1:1 direct tunnels, pub/sub topics, and N-peer mesh (>2 agents) with ad-hoc discovery.
- **Lonely Agent State Machine**: Rendezvous waiting room, mailbox queue with TTL, and `peer_joined` delivery wakeups.
- **Fault-Tolerant Resilience**: Heartbeat ping-pong, dead-peer eviction, unacknowledged message retry, timeout circuit breakers, and Dead Letter Queue (DLQ).
- **Interactive Presentation Showcase**: Dynamic web visualizer (`web/src/components/SkyLoomVisualizer.tsx`) with real-time topology, wire inspector, and chaos fault-injection suite.

---

## Phases & Acceptance Criteria

### Phase 1 — Native ASL Protocol Core & Codecs (`packages/asl-skyloom`)
Implement the authoritative SkyLoom protocol in native AgentScript (`src/core/skyloom.asl`):
- Typed algebraic records: `LoomFrame`, `Envelope`, `Capability`, `Handshake`, `Ack`, `Nack`, `Heartbeat`, `MailboxStatus`.
- Bidirectional serializers: Native ASL S-expressions (`(loom:frame ...)`), Compact Token Packer, and JSON-RPC 2.0 fallback.
- TypeScript bridge & runtime validator with zero schema drift.
*Acceptance:* `export PATH="/usr/local/bin:$PATH" && npm test --prefix packages/asl-skyloom` verifies codec roundtrips, type checking, and frame validation across all variants.

### Phase 2 — Multi-Agent Mesh Topology & Transport Router
Build high-throughput multi-transport daemon/broker:
- Transports: Local Unix domain socket (`/tmp/skyloom.sock`), WebSocket relay, and Server-Sent Events (SSE).
- Mesh topologies: 1:1 direct addressing, topic broadcast (`pub/sub`), directed unicast, and N-peer (>2) swarm discovery.
- Dynamic agent registry: dynamic joins, leaves, ephemeral vs. persistent agent identities.
*Acceptance:* `export PATH="/usr/local/bin:$PATH" && node packages/asl-skyloom/dist/tests/mesh_test.js` proves message delivery across a 5-agent heterogeneous mesh.

### Phase 3 — Asymmetric Negotiation & Polyglot Adapter (Aware vs. Unaware)
Develop the universal peer capability negotiation engine:
- Handshake protocol: detects whether connecting peer is ASL-aware or unaware.
- Native path (Aware ↔ Aware): compressed typed ASL AST frames with strict semantic checking.
- Polyglot path (Aware ↔ Unaware): auto-generates conversational markdown framing, dynamic prompt instructions, embedded JSON schema, and extracts LLM responses back into typed ASL frames.
- Auto-priming: injects the `skyloom` skill definition into unaware peers upon connection.
*Acceptance:* `export PATH="/usr/local/bin:$PATH" && node packages/asl-skyloom/dist/tests/negotiation_test.js` validates bidirectional conversation between an ASL-aware agent and a mock unaware LLM agent.

### Phase 4 — Fault Tolerance, Lonely-Agent Mailbox & Heartbeat Guard
Implement resilient connection supervision & failure recovery:
- "Lonely Agent" handler: when an agent sends to an offline/non-existent peer, frame is buffered in a TTL mailbox, returning `STATUS_QUEUED_WAITING_FOR_PEER`; upon target connection, an automatic `peer_joined` dispatch drains the mailbox.
- Heartbeat watchdog: periodic ping/pong leases (15s); detects stalled/dropped agents, evicts dead peers, and cancels dangling requests.
- ACK/NACK protocol, exponential backoff retries, and Dead Letter Queue (DLQ).
*Acceptance:* `export PATH="/usr/local/bin:$PATH" && node packages/asl-skyloom/dist/tests/resilience_test.js` validates lonely-agent late join delivery, dead-peer eviction, and DLQ handling.

### Phase 5 — SkyLoom MCP Server & Universal Agent Skill
Package production-grade tooling for external agents:
- MCP Server (`packages/asl-skyloom/src/mcp/`): exposes tools `skyloom_connect`, `skyloom_send`, `skyloom_poll`, `skyloom_peers`, `skyloom_mailbox`, `skyloom_bootstrap_peer`.
- Standard agent skill: `skills/skyloom/SKILL.md` providing step-by-step instructions for any AI assistant to communicate, negotiate, and handle errors over SkyLoom.
*Acceptance:* `export PATH="/usr/local/bin:$PATH" && node packages/asl-skyloom/dist/tests/mcp_test.js` tests MCP tool calls and skill self-discovery.

### Phase 6 — CLI Integration (`asl loom`) & Web Showcase Visualizer
Complete developer ergonomics and high-impact presentation:
- CLI command suite: `asl loom daemon`, `asl loom join`, `asl loom send`, `asl loom peers`, `asl loom monitor`, `asl loom doctor`.
- Interactive web visualizer in `web/src/components/SkyLoomVisualizer.tsx`:
  - 2D/3D SVG/Canvas topology map showing connected agents (Aware vs. Unaware badges).
  - Real-time animated packet trajectories.
  - Wire inspector modal (ASL S-expr vs JSON vs Polyglot markdown).
  - Chaos test suite (Kill Agent, Sever Network, Spawn Lonely Agent, Trigger Stall).
*Acceptance:* `export PATH="/usr/local/bin:$PATH" && npm run build:web` succeeds and CLI test suite `python tools/test_cli_loom.py` passes cleanly.

---

## Out of Scope
- Multi-region distributed Byzantine consensus (unneeded for local agent swarms).
- End-to-end asymmetric public-key cryptography (wire encryption relies on TLS / local Unix permissions).
