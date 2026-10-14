---
name: seambus
description: Design reference for the AgentScript agent-to-agent session layer (SkyLoom in the specification, SeamBus being this skill's alias for it) and a map of the wire code that exists today. Use when designing or reviewing inter-agent frames, handoff and yield contracts or the error codes 1001-1010, or when changing the wire, transport, ndAsn, presence or mesh modules of asl/packages/asl-agent-bus. It sends nothing, and there is no bus daemon or CLI.
---

# SeamBus (the SkyLoom session layer)

**Status: design, not code.** The normative specification is `asl/docs/agenticProtocol.md`:
Part I is the frame layer (AgP: sigils, value syntax, error taxonomy), Part II the session layer
(SkyLoom: dialects, frame types, handoff, mailbox). That document states that no code implements
either layer. SeamBus is this skill's name for the same design; where the two disagree, the
document wins.

## 1. What does not exist

Do not tell a user that a message was sent, queued or delivered through any of these:

- No CLI. `asl bus`, `asl sb` and `asl loom` are not commands; each answers `ERR_UNKNOWN_COMMAND`.
- No op. `(:handoff)` answers `ERR_UNIMPLEMENTED`, and `(:tools)` lists no bus or mesh op.
- No daemon, socket listener, mailbox, Wasm SDK or dialect negotiator. The names the
  specification uses (`LoomFrame`, `FrameType`, `encodeFrame`, `AsymmetricNegotiator`) occur
  nowhere in code.

## 2. What exists today

`asl/packages/asl-agent-bus/src` holds pure functions that build, validate and encode values;
none of them opens a socket or performs other I/O. The implemented wire is a smaller shape than
AgP: `CanonicalWireFrame`, five string fields, declared in `asl/grammar/wire.asn`.

| Module | What it holds | Suite on `asl-host test` (2026-10-14) |
|---|---|---|
| `wire.asl` | `CanonicalWireFrame` (`identity` `sessionId` `causality` `payload` `digest`), `validateWireFrame`, `encodeCanonicalFrame`/`decodeCanonicalFrame`, per-transport `encodeStdioFrame` ... `decodeSseFrame` (stdio, Unix socket, HTTP, SSE text) | `wireTest.asl`, 29 assertions |
| `transport.asl` | `TransportFrameType` (`frameHandshake` `frameHeartbeat` `frameRpcReq` `frameRpcRes` `frameStreamChunk` `frameClose`), `makeTransportEnvelope`, `initTransportSession` | `transportTest.asl`, 18 |
| `ndAsn.asl` | Newline-delimited ASN frames: `ndAsnFrame` (`topic` `seq` `ts` `payload` `meta`), `ndAsnSerialize`, `ndAsnDeserialize` | `ndAsnTest.asl`, 31 |
| `presence.asl` | `createSwarmRoom`, `joinSwarmRoom`, `leaveSwarmRoom`, `claimPath`, `proposeTask`, `acceptTask`, `declineTask`: the nearest thing to rendezvous and handoff | `presenceTest.asl`, 24 |
| `mesh.asl` | `TaskContract`, `makeTaskContract`, `delegateContract`, `PeerRegistry`, `routePacket` | `meshTest.asl`, 40 |

Run a suite from the workspace root; exit 0 and the executed assertion count are the evidence:

```bash
asl/host/out/asl-host test asl/packages/asl-agent-bus/tests/wireTest.asl
```

`asl-host` is built by `sh asl/host/build.sh`.

## 3. The design (target)

Everything below is what code is meant to meet. Nothing decodes or encodes it yet.

### Dialects

Four dialects carry the same frame: `asl/v1` (a `loom:frame` head with every field keyed),
`asl/coord` (`loom:handoff`, `loom:yield` and `loom:coord` heads, typed end to end),
`compact/v1` (positional `SK1|v|id|from|to|type|channel|ts|replyTo|body`, the default for
high-frequency loops) and `polyglot/v1` (a markdown envelope with a JSON block, for peers that
have never heard of the protocol). In `asl/v1`, `compact/v1` and `polyglot/v1` the body is JSON
inside the envelope; the target is an ASN body. Dialect tags are not version strings: the
protocol version is `asl/1.0`, carried in `:proto` during the handshake.

### Frame types

`HANDSHAKE DATA HANDOFF YIELD SPAWN ACK NACK PING PONG RENDEZVOUS LEAVE`. Liveness is
`PING`/`PONG`, not `HEARTBEAT_PING`/`HEARTBEAT_PONG`.

### Keys

Every key is camelCase, and a quantity carries its unit in the key: `:timeoutMs`, `:replyTo`.
The spellings `:timeout`, `:tOut`, `:timeout_ms` and `:timeout-ms` are wrong. Nothing enforces
this today; a conforming codec is where it will be checked.

### Handoff and yield

Delegate a task without copying context: the delegator names the task, a working directory, the
files the assignee owns, the files it must not touch, a verification gate and a token budget;
the assignee answers with a yield. From `asl/docs/agenticProtocol.md` §14.2:

```agp
(loom:handoff :v 1 :id "handoff-7721" :from "agentOrchestrator" :to "agentCoder1"
  :ts 1788350000000 :task "implementRateLimiter" :cwd "packages/asl-rate"
  :owns ["src/limiter.asl" "tests/limiterTest.asl"] :frozen ["src/core.asl"]
  :gate "asl/host/out/asl-host test tests/limiterTest.asl" :budget 4000)

(loom:yield :v 1 :id "yield-7722" :replyTo "handoff-7721" :from "agentCoder1"
  :to "agentOrchestrator" :ts 1788350004000 :status "ok"
  :verdict "PASS (0 diagnostics, 12 tests green)" :artifacts ["src/limiter.asl"])
```

Reaching outside `:cwd` or writing a `:frozen` path is `:scopeViolation` (1009); declining the
contract is `:handoffRejected` (1010). Until a codec exists, the implemented neighbours are
`proposeTask`/`acceptTask`/`declineTask` in `presence.asl` and `delegateContract` in `mesh.asl`.

### Absent peers and the mailbox

In the design, a frame sent to an absent peer is buffered with a TTL rather than dropped, and the
sender is told `:lonelyQueued` (1002). Retrying in a tight loop is wrong: delivery happens when
the peer announces itself with `RENDEZVOUS`. A frame that outlives its retries is `:deadLetter`
(1008). A peer that accepted work and then stopped answering `PING` is `:stalled` (1007),
distinct from `:timeout` (1006), which is silence before acceptance.

### Error taxonomy

One closed set, shared by frame-layer `:err` keywords and session-layer `NACK` codes. A new
failure mode means a new row here and in `asl/docs/agenticProtocol.md` §8 together.

| Keyword | Code | Keyword | Code |
|---|---|---|---|
| `:peerUnreachable` | 1001 | `:timeout` | 1006 |
| `:lonelyQueued` | 1002 | `:stalled` | 1007 |
| `:dialectUnsupported` | 1003 | `:deadLetter` | 1008 |
| `:decodeFailed` | 1004 | `:scopeViolation` | 1009 |
| `:typeMismatch` | 1005 | `:handoffRejected` | 1010 |
