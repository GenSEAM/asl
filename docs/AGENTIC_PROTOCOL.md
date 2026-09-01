# AgP Wire Protocol — Agentic-Oriented Communication & Handshake Specification (v1.0)

## 1. Overview & Philosophy
When human beings talk to agents, natural language provides flexibility. But when **agents talk to agents (A2A)**, natural language is bloated, lossy, and wasteful.

The **AgP (Agentic Programming) Wire Protocol** defines an ultra-fast, token-compressed, typed S-expression framing layer that runs natively over:
- **MCP (Model Context Protocol)** JSON-RPC 2.0 stdio & SSE transports
- **Google A2A (Agent-to-Agent)** & Client-to-Agent streams
- **Unix Domain Sockets & WebSockets** for local multi-agent swarms

---

## 2. The 3-Step Handshake Sequence

```
Agent Alpha (Client)                           Agent Beta (Responder)
     |                                                  |
     |---- 1. Natural Language or Probe --------------->|
     |     "Please synthesize the search schema"        |
     |                                                  |
     |<--- 2. Agent Discovery Probe --------------------|
     |     (?agent/probe :proto "asl/1.0")              |
     |                                                  |
     |---- 3. Instant Protocol Switch ----------------->|
     |     (!agent/ack :proto "asl/1.0" :mode :nano)    |
     |                                                  |
     |==================================================|
     |      ULTRA-COMPRESSED AGP NANO S-EXPRESSION      |
     |           STREAM (-85% TOKEN OVERHEAD)           |
     |==================================================|
```

---

## 3. Wire Frame Grammar

All messages after handshake switch to typed ASL Nano frames:

```lisp
;; Query Frame
(? <target-agent> <action-verb> [:param-key <typed-value> ...])

;; Response / Assertion Frame
(! <source-agent> :ok <result-payload>)
(! <source-agent> :err <error-code> :msg <detail-str>)

;; Stream Packet
(~ <stream-id> :seq <i64> :chunk <payload>)
```

### Example:
```lisp
;; Task Delegation
(? agent-coder synthesize-fsm :states ["idle" "active" "error"] :timeout-ms 50)

;; Response Frame
(! agent-coder :ok (dfe State (:case idle []) (:case active [(t I64)]) (:case error [(e Str)])))
```
