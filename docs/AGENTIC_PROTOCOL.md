# AgP — The AgentScript Wire Protocol (v1.0)

**This document is the single normative specification for agent-to-agent communication in
AgentScript.** It has two layers and nothing else describes them:

| Layer | Defines | Reference implementation |
|---|---|---|
| **Part I — Frame layer (AgP)** | Sigils, frame grammar, value syntax, protocol version, the error taxonomy | `tools/a2a_wire.py` |
| **Part II — Session layer (SkyLoom)** | Dialect negotiation, frame types, handshake, heartbeat, rendezvous, handoff, yield | `packages/asl-skyloom/src/` |

Neighbouring documents and what they govern:

| Document | Governs |
|---|---|
| `AGENT_SPEC_CORE.md` | The AgentScript language: forms, types, evaluation |
| `docs/ASN_SPEC.md` | AgentScript Notation — how payload **data** is written |
| **this document** | The **wire** — how agents frame and exchange that data |
| `docs/SKYLOOM_SPEC.md` | Nothing. It is a pointer to Part II, kept for inbound links |

---

# Part I — Frame Layer (AgP)

## 1. Why a wire at all

Natural language between agents is bloated, lossy, and unverifiable. AgP frames an
agent-to-agent exchange as typed AgentScript s-expressions that run natively over:

- **MCP (Model Context Protocol)** JSON-RPC 2.0 stdio and SSE transports
- **Google A2A** and client-to-agent streams
- **Unix domain sockets and WebSockets** for local multi-agent swarms

## 2. Lexical rule: the sigil is a separate token

A frame's head is one of three sigils — `?`, `!`, `~` — and **a space always follows it**.

```agp
(? agent-coder synthesize-fsm :timeout-ms 50)
```

`(?agent-coder ...)` is **not** an AgP frame. Without the space, `?agent-coder` lexes as a
single identifier, so the form has a different head and the reference codec rejects it. Every
example in this document and every constant in `tools/a2a_wire.py` is written in the spaced
form; a spaceless frame is a defect wherever it appears.

## 3. Frame grammar

```text
;; Query — ask a peer to do something
(? <target-agent> <action-verb> [:param-key <value> ...])

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

## 5. Parameter keys are kebab-case

Every `:key` matches `[a-z][a-z0-9]*(-[a-z0-9]+)*`. The language's identifier rule forbids
snake_case, so the wire forbids it too, and the reference codec rejects it in both directions.

A quantity carries its unit in the key. The canonical spelling is **`:timeout-ms`**. The
spellings `:timeout`, `:t-out`, `:timeout_ms` and `:timeoutMs` are all wrong and all name the
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

The two handshake frames, exactly as `tools/a2a_wire.py` emits them:

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
(! agent-beta :err :dialect-unsupported :msg "this peer speaks asl/1.0" :retry false)
```

## 8. The error taxonomy

One table. The keyword is what a frame-layer `:err` carries; the integer is the same failure as
a session-layer `NACK` code (Part II §12); the enum case is `ErrorCode` in
`packages/asl-skyloom/src/core/skyloom.asl`.

| Keyword | Code | Meaning |
|---|---|---|
| `:peer-unreachable` | 1001 | Target agent id is not in the active registry |
| `:lonely-queued` | 1002 | No peer listening; frame buffered in the mailbox |
| `:dialect-unsupported` | 1003 | Peer cannot decode the requested dialect |
| `:decode-failed` | 1004 | Malformed frame syntax |
| `:type-mismatch` | 1005 | Body does not conform to the expected schema |
| `:timeout` | 1006 | No acknowledgement within the deadline |
| `:stalled` | 1007 | Peer accepted the task but heartbeats ceased |
| `:dead-letter` | 1008 | Frame exceeded its maximum retry attempts |
| `:scope-violation` | 1009 | Agent reached outside its permitted directory scope |
| `:handoff-rejected` | 1010 | Target agent declined the handoff contract |

The set is closed. An `:err` frame naming a keyword outside this table is a decode error, so a
new failure mode means a new row here, in `skyloom.asl` and in `types.ts` together.

## 9. Worked examples

```agp
;; Task delegation
(? agent-coder synthesize-fsm :states ["idle" "active" "error"] :timeout-ms 50)

;; Success
(! agent-coder :ok (fsm :states 3 :file "state.asl"))

;; Failure
(! agent-coder :err :scope-violation :msg "path '/etc/shadow' is outside the jailed workspace" :retry false)

;; Streamed result, then its terminator
(~ stream-7 :seq 1 :chunk (reading 22.4))
(~ stream-7 :seq 2 :chunk (reading 22.8))
(~ stream-7 :seq 3 :end true)
```

Every frame printed in this section is decoded by `tools/tests/test_a2a_wire.py`, which reads
them out of this file, and the session-layer examples in §14 are decoded by
`packages/asl-skyloom/tests/spec_examples_test.ts` the same way. An example the reference
implementation cannot read fails the test suite.

Wire frames are fenced ` ```agp `, never ` ```lisp `. A frame is the protocol's language, not
Core AgentScript, so `tools/doc_examples.py` — which parses every ` ```lisp ` and
` ```agentscript ` block in the repository as Core — must not be handed one.

---

# Part II — Session Layer (SkyLoom)

SkyLoom is the session layer above AgP: peer registry, dialect negotiation, delivery guarantees,
context-isolated handoff. `packages/asl-skyloom/src/types.ts` and
`packages/asl-skyloom/src/core/skyloom.asl` are the implementations this part describes; where
they and this prose disagree, they are right and this is a bug.

## 10. Dialects

Four, all carrying the same `LoomFrame`.

| Tag | Shape | Used for |
|---|---|---|
| `asl/v1` | `loom:frame` head, every field keyed | Verbose self-describing frames; diagnostics and introspection |
| `asl/coord` | `loom:handoff`, `loom:yield`, `loom:coord` heads | Coordination: handoff, yield, spawn. Typed keyed fields, no encoded body |
| `compact/v1` | `SK1\|v\|id\|from\|to\|type\|channel\|ts\|reply-to\|body` | Default wire dialect for high-frequency loops |
| `polyglot/v1` | Markdown envelope with a JSON block | Peers that have never heard of SkyLoom |

`asl/coord` and `compact/v1` are the **nano** dialects (`isNanoFormat`). `encodeFrame` defaults
to `asl/coord` for `HANDOFF` and `YIELD` frames and to `compact/v1` for everything else;
`asl/v1` is only produced when asked for by name.

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

`DATA`, `HANDOFF`, `SPAWN` and `HANDSHAKE` require an acknowledgement (`requires-ack`).
Everything except `DATA`, `HANDOFF` and `YIELD` is a control frame (`is-control-frame`).

## 12. Frame structure

A `LoomFrame` is a header, a type, an optional channel and a body. Types below are AgentScript
types — the earlier `U16` / `UUID` / `U32` spellings named types the language does not have.

| Field | Wire key | Type | Required |
|---|---|---|---|
| version | `:v` | `Int64` | yes |
| id | `:id` | `String` | yes |
| from | `:from` | `String` | yes |
| to | `:to` | `String` | yes |
| dialect | `:dialect` | `(Option Dialect)` | no |
| timestamp | `:ts` | `Int64` | yes |
| reply-to | `:reply-to` | `(Option String)` | no |
| type | `:type` | `FrameType` | yes |
| channel | `:channel` | `(Option String)` | no |
| body | `:body` | payload, see §13 | yes |

`id` is `String`, not a UUID type: the codec never parses or validates it, and the CLI issues ids
like `msg-9f201`. `LoomFrame` also declares an optional `signature`, which no codec currently
writes or reads; it is reserved, not implemented. There is no footer and no checksum field.

## 13. What a frame body actually is

**Today the body is JSON.** `encodeAslSExpr`, `encodeCompact` and `encodePolyglot` all call
`JSON.stringify` on `frame.body` and place the result inside the envelope, and the matching
decoders call `JSON.parse`. So an `asl/v1` frame is an s-expression envelope wrapping a JSON
payload, not an s-expression all the way down.

**The intent is ASN.** Once `docs/ASN_SPEC.md` lands, the body becomes an AgentScript Notation
value carrying the same nominal types the checker verifies, and the JSON layer goes away. Until
that change ships in the codec, prose describing SkyLoom bodies as "typed ASL frames" is
describing the envelope, not the payload.

`asl/coord` is the exception and the preview: its `loom:handoff` and `loom:yield` frames carry
their fields as typed keyed s-expression attributes, with no JSON anywhere.

## 14. Wire formats

### 14.1 `asl/v1` — verbose self-describing

The `:body` here is a JSON object; the block is a wire dump, not AgentScript source.

```text
(loom:frame :v 1 :id "msg-9f201" :from "orchestrator-main" :to "coder-sub-42" :dialect "asl/v1" :ts 1788350000000 :type "DATA" :channel "tasks" :body {"action":"compile","target":"wasm","timeout-ms":5000})
```

### 14.2 `asl/coord` — coordination and handoff

Fully typed, no JSON. These are AgentScript s-expressions.

```agp
(loom:handoff :v 1 :id "handoff-7721" :from "agent-orchestrator" :to "agent-coder-1"
  :ts 1788350000000 :task "implement_rate_limiter" :cwd "packages/asl-rate"
  :owns ["src/limiter.asl" "tests/limiter_test.asl"] :frozen ["src/core.asl"]
  :gate "asl check src/limiter.asl" :budget 4000)

(loom:yield :v 1 :id "yield-7722" :reply-to "handoff-7721" :from "agent-coder-1"
  :to "agent-orchestrator" :ts 1788350004000 :status "ok"
  :verdict "PASS (0 diagnostics, 12 tests green)" :artifacts ["src/limiter.asl"])
```

### 14.3 `compact/v1` — positional token stream

Ten pipe-delimited fields; `\|` and `\\` are the escapes.

```text
SK1|1|msg-9f201|orchestrator-main|coder-sub-42|DATA|tasks|1788350000000||{"action":"compile","target":"wasm","timeout-ms":5000}
```

### 14.4 `polyglot/v1` — for peers that do not speak SkyLoom

The envelope teaches the receiver how to answer.

````text
<!-- SKYLOOM_HEADER: {"v":1,"id":"msg-9f201","from":"orchestrator-main","to":"coder-sub-42","dialect":"polyglot/v1","type":"DATA","channel":"tasks"} -->
[SkyLoom Inter-Agent Protocol Frame]
From Agent: orchestrator-main
To Agent: coder-sub-42
Message Type: DATA | Channel: tasks

```json
{
  "action": "compile",
  "target": "wasm",
  "timeout-ms": 5000
}
```
<!-- SKYLOOM_FOOTER -->
````

## 15. Negotiation

`AsymmetricNegotiator.negotiate` picks the dialect from both peers' declared capabilities:

1. Both peers ASL-native → `asl/v1`.
2. Both list `compact/v1` → `compact/v1`.
3. Otherwise → `polyglot/v1`, and the sender prepends an instruction primer when the receiver
   is not ASL-native.

A peer asked for a dialect it cannot decode answers `:dialect-unsupported` (1003).

## 16. Heartbeat, rendezvous and the mailbox

- **Heartbeat.** `PING` expects `PONG`. A peer that accepted work and then stopped answering is
  `:stalled` (1007), distinct from `:timeout` (1006), which is silence before acceptance.
- **Rendezvous.** A peer that comes online announces itself with `RENDEZVOUS`; the mesh drains
  any mailbox queued for it.
- **Lonely peers.** A frame sent to an absent peer is buffered, not dropped, and the sender is
  told `:lonely-queued` (1002) with a TTL. Retrying in a tight loop is wrong: delivery happens
  on the peer's `RENDEZVOUS`. A frame that outlives its retries becomes `:dead-letter` (1008).

## 17. Handoff and yield

Handoff exists so that delegating work does not mean copying context. The delegator sends a
`HANDOFF` frame naming a task, a working directory, the files the assignee owns, the files it
must not touch, a verification gate, and a token budget. The assignee answers with `YIELD`.

Reaching outside `:cwd` or writing a `:frozen` path is `:scope-violation` (1009). Declining the
contract outright is `:handoff-rejected` (1010).

```bash
asl loom handoff --to agent-coder --task build_feature --cwd packages/rate \
  --owns "src/main.asl" --gate "asl check" --budget 4000
asl loom yield --to agent-orchestrator --reply-to handoff-7721 --status ok \
  --verdict "PASS (0 errors)" --artifacts "src/main.asl"
```

## 18. Conformance

```bash
.venv/bin/python -m pytest tools/tests/test_a2a_wire.py -q          # Part I
cd packages/asl-skyloom && npm test                                  # Part II
```
