# AgP — The AgentScript Wire Protocol (v0.1.0)

**Status: target design.** This document specifies agent-to-agent communication in two layers.
As of 2026-09-24 no code implements either layer; the frames, dialects and error codes below are
the design that code is meant to meet. What the tree implements today is listed in the next
section.

| Layer | Defines | Implementation |
|---|---|---|
| **Part I — Frame layer (AgP)** | Sigils, frame grammar, value syntax, protocol version, the error taxonomy | none yet |
| **Part II — Session layer (SkyLoom)** | Dialect negotiation, frame types, handshake, heartbeat, rendezvous, handoff, yield | none yet |

Neighbouring documents and what they govern:

| Document | Governs |
|---|---|
| `asl/agentSpecCore.md` | The AgentScript language: forms, types, evaluation |
| `asl/docs/asnSpec.md` | AgentScript Notation — how payload **data** is written |
| **this document** | The **wire** — how agents frame and exchange that data |

## What exists today

The implemented wire is a different, smaller shape than AgP: a canonical frame of five string
fields carried over four transports.

| Path | What it holds | Check (asl-core, 2026-09-24) |
|---|---|---|
| `asl/grammar/wire.asn` | `CanonicalWireFrame` (`identity`, `sessionId`, `causality`, `payload`, `digest`), `WireError`, transports `:stdio :unixSocket :http :sse`, conformance vectors | — |
| `asl/packages/asl-agent-bus/src/wire.asl` | `CanonicalWireFrame` validate/encode/decode, per-transport `encodeStdioFrame` … `decodeSseFrame`, and a compressed `WireFrame` | `./bin/asl test asl/packages/asl-agent-bus/tests/wireTest.asl`: 43 assertions |
| `asl/packages/asl-agent-bus/src/transport.asl` | `TransportFrameType` (handshake, heartbeat, rpcReq, rpcRes, streamChunk, close), transport sessions, conversion to and from `CanonicalWireFrame` | `transportTest.asl`: 36 assertions |
| `asl/packages/asl-agent-bus/src/ndAsn.asl` | Newline-delimited ASN frames (`topic`, `seq`, `ts`, `payload`, `meta`) | `ndAsnTest.asl`: 31 assertions |
| `asl/packages/asl-agent-bus/src/presence.asl` | Swarm rooms (join, leave), path claims, task propose/accept/decline — the nearest thing to rendezvous and handoff | `presenceTest.asl`: 48 assertions |
| `asl/packages/asl-agent-bus/src/mesh.asl` | `TaskContract`, `delegateContract`, peer registry | `meshTest.asl`: 40 assertions |

These suites pass on asl-core, which is lenient. The stage-0 host (`asl/host/out/asl-host test`)
does not load them yet: `wire.asl` calls `show`, which the host does not bind
(`ERR_UNKNOWN_SYMBOL show`).

Not implemented: the sigil frames of Part I, the error codes 1001–1010 (they appear only in
`asl/packages/asl-agent-bus/skills/seambus/SKILL.md` and in blog data), the SkyLoom dialects and negotiator of
Part II, and any CLI for them. `asl loom` is an unknown command, and the `(:handoff)` op answers
`ERR_UNIMPLEMENTED`.

---

# Part I — Frame Layer (AgP)

## 1. Why a wire at all

Natural language between agents is bloated, lossy, and unverifiable. AgP frames an
agent-to-agent exchange as typed AgentScript s-expressions. Target transports:

- **AWP (Agent Wire Protocol)** JSON-RPC 2.0 stdio and SSE transports
- **Google A2A** and client-to-agent streams
- **Unix domain sockets and WebSockets** for local multi-agent swarms

Today's `CanonicalWireFrame` covers stdio, Unix sockets, HTTP and SSE (see above).

## 2. Lexical rule: the sigil is a separate token

A frame's head is one of three sigils — `?`, `!`, `~` — and **a space always follows it**.

```agp
(? agentCoder synthesizeFsm :timeoutMs 50)
```

`(?agentCoder ...)` is **not** an AgP frame. Without the space, `?agentCoder` lexes as a single
identifier, so the form has a different head and a conforming codec rejects it. Every example in
this document is written in the spaced form; a spaceless frame is a defect wherever it appears.

## 3. Frame grammar

```text
;; Query — ask a peer to do something
(? <target-agent> <action-verb> [:paramKey <value> ...])

;; Response — success
(! <source-agent> :ok <payload>)

;; Response — failure
(! <source-agent> :err <error-keyword> :msg "<detail>" [:retry <Bool>])

;; Stream — one chunk of a multi-part payload
(~ <stream-id> :seq <Int64> :chunk <payload>)

;; Stream — the frame that closes it
(~ <stream-id> :seq <Int64> :end true)
```

`<target-agent>`, `<action-verb>`, `<source-agent>` and `<stream-id>` are bare identifiers.
`:ok` carries exactly one payload form. A stream frame carries exactly one of `:chunk` or
`:end`; a stream with no `:end` frame is an unterminated stream, not a finished one.

## 4. Value syntax

Frame values are **AgentScript literals**, never JSON. The difference is load-bearing: AgentScript
lists are whitespace-delimited and carry no commas, and a comma on the wire is a decode error.

| Kind | Written | AgentScript type |
|---|---|---|
| String | `"idle"` | `String` |
| Integer | `50`, `-3` | `Int64` |
| Float | `22.4` | `Float64` |
| Boolean | `true`, `false` | `Bool` |
| Keyword | `:nano` | enum case tag |
| List | `["idle" "active"]` | `(List T)` |
| Nested form | `(fsm :states 3)` | a constructor application |

String escapes are `\"`, `\\`, `\n`, `\t`, `\r`. Nothing else is an escape.

## 5. Parameter keys are camelCase

Every `:key` is a camelCase whole-word name, `[a-z][a-zA-Z0-9]*`, the dialect rule for keywords
in ASL and ASN. Neither engine enforces a naming convention today (snake_case names load on both),
so a conforming codec is where this rule is checked.

A quantity carries its unit in the key. The canonical spelling is **`:timeoutMs`**. The
spellings `:timeout`, `:tOut`, `:timeout_ms` and `:timeout-ms` are all wrong and all name the
same field; anywhere they survive is a bug to be fixed, not a variant to be supported.

## 6. Protocol version

The protocol version string is **`asl/1.0`**. There is exactly one, it is carried in `:proto`
during the handshake, and no other string denotes it.

Dialect tags — `asl/v1`, `asl/coord`, `compact/v1`, `polyglot/v1` (Part II §10) — are **not**
version strings. They name an encoding, and their `/v1` suffix is that encoding's own revision.
A peer speaking `asl/1.0` may speak any of the four dialects.

## 7. Handshake

Three steps: a peer is addressed in whatever it already understands, it probes, and both sides
switch to frames.

```
Agent Alpha (Client)                           Agent Beta (Responder)
     |                                                  |
     |---- 1. Natural language or probe --------------->|
     |     "Please synthesize the search schema"        |
     |                                                  |
     |<--- 2. Agent discovery probe --------------------|
     |     (? agent probe :proto "asl/1.0")             |
     |                                                  |
     |---- 3. Instant protocol switch ----------------->|
     |     (! agent :ok (proto :v "asl/1.0" ...))       |
     |                                                  |
     |==================================================|
     |         TYPED AgP S-EXPRESSION STREAM            |
     |==================================================|
```

The two handshake frames:

```agp
;; Probe. `agent` is the reserved identifier for a peer whose id you do not yet know.
(? agent probe :proto "asl/1.0")

;; Ack. A responder that knows its own id substitutes it for `agent`.
(! agent :ok (proto :v "asl/1.0" :mode :nano))
```

`:mode` selects the session-layer dialect family: `:nano` for the dense dialects
(`compact/v1`, `asl/coord`), `:verbose` for `asl/v1`, `:polyglot` for `polyglot/v1`.

A peer that does not speak `asl/1.0` answers with an error frame rather than silence:

```agp
(! agentBeta :err :dialectUnsupported :msg "this peer speaks asl/1.0" :retry false)
```

## 8. The error taxonomy

One table. The keyword is what a frame-layer `:err` carries; the integer is the same failure as
a session-layer `NACK` code (Part II §12).

| Keyword | Code | Meaning |
|---|---|---|
| `:peerUnreachable` | 1001 | Target agent id is not in the active registry |
| `:lonelyQueued` | 1002 | No peer listening; frame buffered in the mailbox |
| `:dialectUnsupported` | 1003 | Peer cannot decode the requested dialect |
| `:decodeFailed` | 1004 | Malformed frame syntax |
| `:typeMismatch` | 1005 | Body does not conform to the expected schema |
| `:timeout` | 1006 | No acknowledgement within the deadline |
| `:stalled` | 1007 | Peer accepted the task but heartbeats ceased |
| `:deadLetter` | 1008 | Frame exceeded its maximum retry attempts |
| `:scopeViolation` | 1009 | Agent reached outside its permitted directory scope |
| `:handoffRejected` | 1010 | Target agent declined the handoff contract |

The set is closed. An `:err` frame naming a keyword outside this table is a decode error, so a
new failure mode means a new row here and in the seambus skill's table together.

## 9. Worked examples

```agp
;; Task delegation
(? agentCoder synthesizeFsm :states ["idle" "active" "error"] :timeoutMs 50)

;; Success
(! agentCoder :ok (fsm :states 3 :file "state.asl"))

;; Failure
(! agentCoder :err :scopeViolation :msg "path '/etc/shadow' is outside the jailed workspace" :retry false)

;; Streamed result, then its terminator
(~ stream7 :seq 1 :chunk (reading 22.4))
(~ stream7 :seq 2 :chunk (reading 22.8))
(~ stream7 :seq 3 :end true)
```

No test decodes these examples yet; a frame-layer codec, when it exists, should read them out of
this file.

Wire frames are fenced ` ```agp `, never ` ```lisp `. A frame is the protocol's language, not
Core AgentScript or ASN: the ASN reader (`asl/packages/asl-transpile/src/core/asn.asl`) rejects a
sigil head such as `(! :a 1)` as `parse`.

---

# Part II — Session Layer (SkyLoom)

SkyLoom is the session layer designed above AgP: peer registry, dialect negotiation, delivery
guarantees, context-isolated handoff. No code implements it: the names this part uses
(`LoomFrame`, `FrameType`, `encodeFrame`, `AsymmetricNegotiator`) occur nowhere in the tree.

## 10. Dialects

Four, all carrying the same `LoomFrame`.

| Tag | Shape | Used for |
|---|---|---|
| `asl/v1` | `loom:frame` head, every field keyed | Verbose self-describing frames; diagnostics and introspection |
| `asl/coord` | `loom:handoff`, `loom:yield`, `loom:coord` heads | Coordination: handoff, yield, spawn. Typed keyed fields, no encoded body |
| `compact/v1` | `SK1\|v\|id\|from\|to\|type\|channel\|ts\|replyTo\|body` | Default wire dialect for high-frequency loops |
| `polyglot/v1` | Markdown envelope with a JSON block | Peers that have never heard of SkyLoom |

`asl/coord` and `compact/v1` are the **compact** dialects. The encoder defaults to `asl/coord`
for `HANDOFF` and `YIELD` frames and to `compact/v1` for everything else; `asl/v1` is only
produced when asked for by name.

## 11. Frame types

Eleven. This is the whole `FrameType` union.

| Type | Meaning |
|---|---|
| `HANDSHAKE` | Peer hello, capability exchange, supported dialects |
| `DATA` | Application-level message |
| `HANDOFF` | Context-isolated task delegation |
| `YIELD` | Handoff completion: status, gate verdict, artifacts |
| `SPAWN` | Agent process execution inside a scoped directory |
| `ACK` | Positive acknowledgement of receipt or processing |
| `NACK` | Negative acknowledgement, carrying a code from §8 |
| `PING` / `PONG` | Liveness and latency. **Not** `HEARTBEAT_PING` / `HEARTBEAT_PONG` |
| `RENDEZVOUS` | Lonely-agent presence announcement and mailbox check |
| `LEAVE` | Graceful connection termination |

`DATA`, `HANDOFF`, `SPAWN` and `HANDSHAKE` require an acknowledgement (`requiresAck`).
Everything except `DATA`, `HANDOFF` and `YIELD` is a control frame (`isControlFrame`).

## 12. Frame structure

A `LoomFrame` is a header, a type, an optional channel and a body. Types below are AgentScript
types.

| Field | Wire key | Type | Required |
|---|---|---|---|
| version | `:v` | `Int64` | yes |
| id | `:id` | `String` | yes |
| from | `:from` | `String` | yes |
| to | `:to` | `String` | yes |
| dialect | `:dialect` | `(Option Dialect)` | no |
| timestamp | `:ts` | `Int64` | yes |
| replyTo | `:replyTo` | `(Option String)` | no |
| type | `:type` | `FrameType` | yes |
| channel | `:channel` | `(Option String)` | no |
| body | `:body` | payload, see §13 | yes |

`id` is `String`, not a UUID type: the codec never parses or validates it, and ids look like
`msg-9f201`. An optional `signature` field is reserved. There is no footer and no checksum field.

## 13. What a frame body is

In `asl/v1`, `compact/v1` and `polyglot/v1` the design places a JSON body inside the envelope,
so an `asl/v1` frame is an s-expression envelope wrapping a JSON payload, not an s-expression
all the way down.

**The target is ASN.** The body becomes an AgentScript Notation value (`asl/docs/asnSpec.md`)
carrying the same nominal types the checker verifies, and the JSON layer goes away.

`asl/coord` already has that shape: its `loom:handoff` and `loom:yield` frames carry their fields
as typed keyed s-expression attributes, with no JSON anywhere.

## 14. Wire formats

### 14.1 `asl/v1` — verbose self-describing

The `:body` here is a JSON object; the block is a wire dump, not AgentScript source.

```text
(loom:frame :v 1 :id "msg-9f201" :from "orchestratorMain" :to "coderSub42" :dialect "asl/v1" :ts 1788350000000 :type "DATA" :channel "tasks" :body {"action":"compile","target":"wasm","timeoutMs":5000})
```

### 14.2 `asl/coord` — coordination and handoff

Fully typed, no JSON. These are AgentScript s-expressions.

```agp
(loom:handoff :v 1 :id "handoff-7721" :from "agentOrchestrator" :to "agentCoder1"
  :ts 1788350000000 :task "implementRateLimiter" :cwd "packages/asl-rate"
  :owns ["src/limiter.asl" "tests/limiterTest.asl"] :frozen ["src/core.asl"]
  :gate "asl/host/out/asl-host test tests/limiterTest.asl" :budget 4000)

(loom:yield :v 1 :id "yield-7722" :replyTo "handoff-7721" :from "agentCoder1"
  :to "agentOrchestrator" :ts 1788350004000 :status "ok"
  :verdict "PASS (0 diagnostics, 12 tests green)" :artifacts ["src/limiter.asl"])
```

### 14.3 `compact/v1` — positional token stream

Ten pipe-delimited fields; `\|` and `\\` are the escapes.

```text
SK1|1|msg-9f201|orchestratorMain|coderSub42|DATA|tasks|1788350000000||{"action":"compile","target":"wasm","timeoutMs":5000}
```

### 14.4 `polyglot/v1` — for peers that do not speak SkyLoom

The envelope teaches the receiver how to answer.

````text
<!-- SKYLOOM_HEADER: {"v":1,"id":"msg-9f201","from":"orchestratorMain","to":"coderSub42","dialect":"polyglot/v1","type":"DATA","channel":"tasks"} -->
[SkyLoom Inter-Agent Protocol Frame]
From Agent: orchestratorMain
To Agent: coderSub42
Message Type: DATA | Channel: tasks

```json
{
  "action": "compile",
  "target": "wasm",
  "timeoutMs": 5000
}
```
<!-- SKYLOOM_FOOTER -->
````

## 15. Negotiation

The negotiator picks the dialect from both peers' declared capabilities:

1. Both peers ASL-native → `asl/v1`.
2. Both list `compact/v1` → `compact/v1`.
3. Otherwise → `polyglot/v1`, and the sender prepends an instruction primer when the receiver
   is not ASL-native.

A peer asked for a dialect it cannot decode answers `:dialectUnsupported` (1003).

## 16. Heartbeat, rendezvous and the mailbox

- **Heartbeat.** `PING` expects `PONG`. A peer that accepted work and then stopped answering is
  `:stalled` (1007), distinct from `:timeout` (1006), which is silence before acceptance.
- **Rendezvous.** A peer that comes online announces itself with `RENDEZVOUS`; the mesh drains
  any mailbox queued for it.
- **Lonely peers.** A frame sent to an absent peer is buffered, not dropped, and the sender is
  told `:lonelyQueued` (1002) with a TTL. Retrying in a tight loop is wrong: delivery happens
  on the peer's `RENDEZVOUS`. A frame that outlives its retries becomes `:deadLetter` (1008).

## 17. Handoff and yield

Handoff exists so that delegating work does not mean copying context. The delegator sends a
`HANDOFF` frame naming a task, a working directory, the files the assignee owns, the files it
must not touch, a verification gate, and a token budget. The assignee answers with `YIELD`.

Reaching outside `:cwd` or writing a `:frozen` path is `:scopeViolation` (1009). Declining the
contract outright is `:handoffRejected` (1010).

No command sends these frames yet: `asl loom` is an unknown command and the `(:handoff)` op
answers `ERR_UNIMPLEMENTED`. The implemented neighbours are `proposeTask`, `acceptTask` and
`declineTask` in `asl/packages/asl-agent-bus/src/presence.asl` and `delegateContract` in `asl/packages/asl-agent-bus/src/mesh.asl`.

## 18. Conformance

Neither layer has a conformance suite. The suites that cover the wire the tree does implement
run on asl-core:

```bash
./bin/asl test asl/packages/asl-agent-bus/tests/wireTest.asl        # CanonicalWireFrame, transports
./bin/asl test asl/packages/asl-agent-bus/tests/transportTest.asl   # transport sessions and frame types
./bin/asl test asl/packages/asl-agent-bus/tests/ndAsnTest.asl       # newline-delimited ASN frames
```
