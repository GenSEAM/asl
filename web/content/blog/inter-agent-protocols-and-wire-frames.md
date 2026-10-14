# Inter-Agent Protocol (AgP): Replacing Natural Language Chatter with Typed S-Expression Frames
*By GenSEAM | September 2026*

A common failure mode of multi-agent systems (AutoGPT, CrewAI, ChatDev, LangGraph swarms) is **Conversational Mesh Chaos**.

When autonomous agents communicate with one another in unstructured natural language, the system degenerates into a lossy "telephone game":

```text
Agent A: "Hi Agent B! Could you please refactor the database connector to handle connection timeouts gracefully? Make sure not to break existing retry semantics."
Agent B: "Certainly! I'd be happy to help with that. Here is a summary of the changes I made to improve timeout resilience..."
Agent C: "Thanks Agent B! Looking at your summary, it seems great. One quick question..."
```

Within a few hops:
1. Bandwidth goes to pleasantries and restated context instead of state.
2. Context windows fill with discursive chatter rather than executable state.
3. Subagents experience **Context Drift**: safety invariants, parameter constraints and directory boundaries are paraphrased until they are distorted or forgotten.
4. Parsing outputs requires brittle regular expressions or a second model acting as judge.

Agents do not need to be polite to each other. They need typed, deterministic, low-overhead wire protocols.

---

## 1. AgP: The AgentScript Wire Protocol (v0.1.0)

**AgP (Agentic Protocol)** replaces natural language chatter with typed, single-pass S-expression frames. Its specification lives in `asl/docs/agenticProtocol.md`, marked as a target design, and its target transports are JSON-RPC 2.0 stdio and SSE, Google A2A streams, and Unix domain sockets or WebSockets for local agent clusters.

Where it stands today: the frame layer and error taxonomy are specified, and the `seambus` skill in `asl/packages/asl-agent-bus/skills/seambus/` describes them to agents. No code implements the sigil grammar or the taxonomy below yet. What `asl/packages/asl-agent-bus/src` does implement is a smaller envelope, `CanonicalWireFrame` (five string fields with stdio, Unix socket, HTTP and SSE encoders), plus newline-delimited ASN frames, swarm presence and task contracts. Their suites pass on the strict stage-0 host (on 2026-10-14, `asl-host test` executed 29 assertions in `wireTest.asl`, 18 in `transportTest.asl`, 31 in `ndAsnTest.asl`, 24 in `presenceTest.asl` and 40 in `meshTest.asl`). The decoder that enforces AgP is the next piece.

### The Lexical Rule: Sigils as Causal Heads

An AgP frame begins with one of three single-character sigils:
* `?`: **Query.** Delegate a task or request data from a peer.
* `!`: **Response.** Return a result or an error status.
* `~`: **Stream.** Send an incremental chunk or end a stream.

**The Space Invariant:** a space always follows the sigil. `(? coder ...)` is a frame; `(?coder ...)` is a malformed token.

```agp
;; Query: ask peer coder to synthesize a state machine
(? coder synthesizeFsm :states ["idle" "active" "error"] :timeoutMs 50)

;; Response: success carrying a literal payload
(! coder :ok (fsm :states 3 :file "state.asl"))

;; Response: failure with a closed error taxonomy keyword
(! coder :err :scopeViolation :msg "path /etc/shadow is outside the jailed workspace" :retry false)

;; Stream: telemetry chunks followed by an explicit end frame
(~ telemetry42 :seq 1 :chunk (reading 22.4))
(~ telemetry42 :seq 2 :chunk (reading 22.8))
(~ telemetry42 :seq 3 :end true)
```

### Pure Value Syntax

AgP values are AgentScript literals, not JSON:
* Lists are whitespace-delimited (`["idle" "active"]`), with no commas.
* Keys are camelCase with the physical unit in the name (`:timeoutMs`), following the language dialect. The specification is camelCase throughout; the `seambus` skill still spells some keys and error keywords kebab-case (`:reply-to`, `:scope-violation`), and the two are being converged.
* Payloads are constructor forms such as `(fsm :states 3)`, read directly as S-expressions without a JSON decoding step.

How much this saves depends on the frame, and we have no corpus measurement. The one recorded example is in the [README](https://github.com/GenSEAM/asl#why): a `git status` tool call is 51 `cl100k_base` tokens as a JSON object and 18 as a positional sigil frame. That is one example, not a benchmark.

---

## 2. Closed Error Taxonomy: No Freeform Failures

In conversational systems, when an agent fails, it writes paragraphs of apology ("I apologize, but I could not find the file you mentioned..."). Downstream agents must parse this prose to guess why the task failed.

AgP specifies a **closed error taxonomy**. An `:err` frame carries one of ten error keywords, shared with the session layer's NACK codes:

| Error Keyword | NACK Code | Meaning |
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

The table is the specification's spelling. Because the set is closed, failure handling is a lookup rather than a reading exercise: an agent receiving `:scopeViolation` knows the request was rejected by the jail, without guessing. A conforming decoder will reject an `:err` frame naming any keyword outside the table.

---

## 3. The Session Layer: Handshake and Handoff

Above the frame layer sits the session layer: peer registry, dialect negotiation, delivery and context-isolated delegation. The specification calls it SkyLoom; the `seambus` skill describes the same design under the name SeamBus. None of it is implemented yet.

```text
Coordinator (Alpha)                              Worker (Beta)
        |                                              |
        |-- 1. Discovery Probe ----------------------->|
        |   (? agent probe :proto "asl/1.0")           |
        |                                              |
        |<- 2. Protocol Ack ---------------------------|
        |   (! agent :ok (proto :v "asl/1.0"           |
        |                       :mode :nano))          |
        |                                              |
        |-- 3. Context-Isolated Handoff -------------->|
        |   task, working directory, owned files,      |
        |   frozen files, gate, token budget           |
        |                                              |
        |<- 4. Yield ----------------------------------|
        |   status, gate verdict, artifacts            |
```

### Context-Isolated Delegation

When a coordinator delegates work to a subagent, passing the coordinator's entire conversational history pollutes the worker's context. The design specifies **hermetic task handoffs** instead (`HANDOFF` and `YIELD` in the specification, `pass` and `ret` in the skill):
1. **Scope Jailing:** The handoff names the working directory and the files the assignee owns. Reaching outside the directory or writing a frozen path is `:scopeViolation`.
2. **Minimal Contract Input:** The subagent receives the task, the files it owns, a verification gate and a token budget, not the coordinator's history.
3. **Deterministic Return:** On completion, the subagent answers with a structured frame carrying status, the gate verdict and artifact paths.

No command or op sends these frames yet. The nearest working pieces are `proposeTask`, `acceptTask` and `declineTask` in `asl-agent-bus/src/presence.asl`, `delegateContract` in `asl-agent-bus/src/mesh.asl`, and the toolbelt's own agent loop: the `(:agent ...)` op takes `:owns` and `:gates`, edits only inside its root narrowed by `:owns`, runs the gates, and reports status, findings and gate results in its receipt.

---

## 4. Context Drift: What We Expect, and What We Have Not Yet Measured

The argument for typed frames is that a handoff which is an immutable, schema-checked S-expression cannot be paraphrased: hop 100 receives the same constraint values as hop 1, where a chat protocol re-describes them at every hop.

We have not yet run a multi-hop drift benchmark comparing natural language chat, JSON-RPC and AgP, so we make no quantitative claim here. The experiment we intend to run is a chain of agents that each receive an invariant configuration, apply a local transformation and forward the state, scored on whether the invariant survives to the last hop.

---

## 5. Architectural Summary

Autonomous agent swarms do not scale on top of human conversational metaphors.

Sigil-headed S-expression frames, a closed error taxonomy, and context-isolated handoffs are the substrate we are building for multi-agent software engineering: typed state instead of chatter, and failures that are keywords instead of prose.
