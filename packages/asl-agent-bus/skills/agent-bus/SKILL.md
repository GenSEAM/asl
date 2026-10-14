---
name: agent-bus
description: Map of asl/packages/asl-agent-bus, the pure AgentScript library of agent-bus values (message envelopes, SSE event text, priority queues, routing tables, swarm presence, task contracts, canonical wire frames and newline-delimited ASN). Use when reading, changing or testing those modules. The package performs no I/O, so it cannot by itself send a message between running agents, and there is no bus daemon or CLI.
---

# Agent Bus (`asl/packages/asl-agent-bus`)

Package `aslAgentBus` (entry `src/bus.asl`). Every module is a set of pure functions over
records and enums: they build, validate, encode and filter values. None opens a socket, starts
a server or touches shared memory, and functions such as `dispatchBusEvent` only return a
receipt record. Transport names (Unix socket, SSE, stdio, HTTP) describe text encodings, not
live connections.

## What does not exist

- No `asl bus` or `asl sb` command (each answers `ERR_UNKNOWN_COMMAND`), and no bus op in
  `(:tools)`. `asl mesh` is a different tool (`asl/tools/mesh/cmd.asl`), not this package.
- No daemon, port or listener. The session-layer protocol (dialects, handoff frames, error
  codes 1001-1010) is a design; see the `seambus` skill and `asl/docs/agenticProtocol.md`.

## Modules most often needed

Names are the exported camelCase names; call them through the module's import alias.

| Module | Use it for |
|---|---|
| `bus.asl` | `makeBusEnvelope`, `formatSseEvent eventName data` (SSE event text), `formatLifecycleSse`, `dispatchBusEvent`, `queryBusEvents`, priority queue `makePriorityBusQueue` / `pushPriorityEvent` / `popPriorityEvent` |
| `mesh.asl` | `createRoutingTable`, `registerMeshNode`, `routePacket rt from to payload`, `isNodeAlive node`, `makeTaskContract`, `delegateContract`, peer registry and buffer leases |
| `presence.asl` | Swarm rooms (`createSwarmRoom`, `joinSwarmRoom`, `leaveSwarmRoom`), `claimPath`, task negotiation (`proposeTask`, `acceptTask`, `declineTask`) |
| `wire.asl` | `CanonicalWireFrame` (`identity` `sessionId` `causality` `payload` `digest`), `validateWireFrame`, encode and decode for stdio, Unix socket, HTTP and SSE text; schema in `asl/grammar/wire.asn` |
| `transport.asl` | `TransportFrameType`, `makeTransportEnvelope`, `initTransportSession` |
| `ndAsn.asl` | Newline-delimited ASN frames: `ndAsnFrame`, `ndAsnSerialize`, `ndAsnDeserialize` |
| `asnlRing.asl` | Bounded ring of `NDASNFrame` values (`makeRingBuffer`, `ringPush`, `ringPop`, `ringDrain`), an immutable value |
| `mvccBus.asl` | Causal message log (`mvccBusCreate`, `mvccBusPublish`, `mvccBusFindHeads`, `mvccBusMergeIntents`) |

Others: `ambient`, `bridge`, `browserBridge`, `cluster`, `gateway`, `networkBridge`,
`procTelemetry`, `toolPlane`, `types`, `transportPatch`; `manifest.asn` lists them and
`doc.asn` holds each symbol's doc row.

## Testing

Suites live in `asl/packages/asl-agent-bus/tests`. Run one from the workspace root; exit 0 and
the executed assertion count are the evidence:

```bash
asl/host/out/asl-host check asl/packages/asl-agent-bus/src/bus.asl
asl/host/out/asl-host test asl/packages/asl-agent-bus/tests/busTest.asl
```

On 2026-10-14 every suite there passed on `asl-host test` except `asnlRingTest.asl`, which
stops with `ERR_ASSERT` because it shells out to `./bin/asl check`, which a checkout without
`bin/asl` does not have.
