---
name: agent-bus
description: Inter-Agent Swarm Bus (SeamBus / Simba) for high-performance agent communication, typed S-expression packet routing, SSE streaming, and Unix domain socket IPC. Use when sending messages between subagents, querying swarm mesh topology, or streaming agent execution telemetry.
---

# Agent Bus (SeamBus / Simba) Skill

`agent-bus` is the native inter-agent communication layer in AgentScript. It enables warm subagents to communicate over local SSE streams, Unix domain sockets, and shared memory ring buffers with sub-millisecond dispatch.

## Core Capabilities
- **Direct Dispatch**: `(bus/format-sse-event "agent:step" payload)`
- **Swarm Mesh Routing**: `(mesh/route-packet routing-table from to data)`
- **Liveness Monitoring**: `(mesh/is-node-alive node)`

## CLI Commands
```bash
# Start local agent bus daemon on port 8765
asl bus serve --port 8765

# Send message to active agent
asl bus send agent-coder "Run task X"
```
