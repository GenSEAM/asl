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

**AgP (Agentic Protocol)** replaces natural language chatter with typed, single-pass S-expression frames. Its specification lives in `asl/docs/agenticProtocol.md`, and it is designed to run over standard transports: JSON-RPC 2.0 stdio and SSE, Google A2A streams, and Unix domain sockets or WebSockets for local agent clusters.

Where it stands today: the frame layer and error taxonomy are specified, and the `seambus` skill in `asl/packages/asl-agent-bus/skills/seambus/` teaches agents to use them. The code in `asl/packages/asl-agent-bus/src` implements a related envelope (`CanonicalWireFrame`, with stdio, Unix socket, HTTP and SSE encoders), not yet the sigil grammar or the taxonomy below. We are building the decoder that enforces them.

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
(! coder :err :scopeViolation :msg "path '/etc/shadow' is outside the jailed workspace" :retry false)

;; Stream: telemetry chunks followed by an explicit end frame
(~ telemetry42 :seq 1 :chunk (reading 22.4))
(~ telemetry42 :seq 2 :chunk (reading 22.8))
(~ telemetry42 :seq 3 :end true)
```

### Pure Value Syntax

AgP values are AgentScript literals, not JSON:
* Lists are whitespace-delimited (`["idle" "active"]`), with no commas.
* Keys are camelCase with the physical unit in the name (`:timeoutMs`), following the language dialect. The protocol document and skill still spell them kebab-case (`:timeout-ms`); they are being converged.
* Payloads are constructor forms such as `(fsm :states 3)`, read directly as S-expressions without a JSON decoding step.

How much this saves depends on the frame. For the query above, the AgP frame is 25 tokens and an equivalent JSON-RPC 2.0 request carrying the same method, target, states and timeout is 41 tokens on o200k_base and 39 on cl100k_base (tiktoken 0.12.0, measured 2026-09-24): about 40 percent fewer for this one frame, not a corpus figure.

---

## 2. Closed Error Taxonomy: No Freeform Failures

In conversational systems, when an agent fails, it writes paragraphs of apology ("I apologize, but I could not find the file you mentioned..."). Downstream agents must parse this prose to guess why the task failed.

AgP specifies a **closed error taxonomy**. An `:err` frame carries one of ten error keywords, shared with the session layer's NACK codes:

| Error Keyword | NACK Code | Meaning |
|---|---|---|
| `:peer-unreachable` | 1001 | Target agent ID is not registered in the active swarm |
| `:lonely-queued` | 1002 | Target peer is offline; frame buffered in a mailbox |
| `:dialect-unsupported`| 1003 | Peer cannot decode the requested dialect |
| `:decode-failed` | 1004 | Malformed frame syntax or invalid token sequence |
| `:type-mismatch` | 1005 | Payload violates the receiving agent's schema contract |
| `:timeout` | 1006 | Execution exceeded the specified deadline |
| `:stalled` | 1007 | Peer accepted the task but emitted no heartbeats |
| `:dead-letter` | 1008 | Frame exceeded the maximum delivery retries |
| `:scope-violation` | 1009 | Agent reached for paths outside its directory jail |
| `:handoff-rejected` | 1010 | Target agent declined the delegated task contract |

The table is the specification's spelling. Because the set is closed, failure handling is a lookup rather than a reading exercise: an agent receiving `:scope-violation` knows the request was rejected by the jail, without guessing.

---

## 3. SeamBus: The Session & Coordination Mesh

Above the frame layer sits **SeamBus**, the session layer described by the `seambus` skill: peer registry, dialect negotiation, delivery and context-isolated delegation.

```
Coordinator (Alpha)                              Worker (Beta)
        │                                              │
        │── 1. Handshake Probe ───────────────────────>│
        │   (? agent probe :proto "asl")               │
        │                                              │
        │<─ 2. Capability Ack ─────────────────────────│
        │   (! agent :ok (proto :name "asl"            │
        │                       :format :compact))     │
        │                                              │
        │── 3. Context-Isolated Delegation ───────────>│
        │   (pass :id "h-99"                           │
        │         :in "pkg/auth"                       │
        │         :do "auditJwt")                      │
        │                                              │
        │<─ 4. Typed Return ───────────────────────────│
        │   (ret :id "h-99"                            │
        │        :ok "patch.diff"                      │
        │        :gate "pass")                         │
```

### Context-Isolated Delegation (`pass`) & Return (`ret`)

When a coordinator delegates work to a subagent, passing the coordinator's entire conversational history pollutes the worker's context.

SeamBus specifies **hermetic task handoffs**:
1. **Scope Jailing:** The `pass` frame names the directory root (`:in "pkg/auth"`) the subagent may read and modify. Access outside this path is a `:scope-violation`.
2. **Minimal Contract Input:** The subagent receives only the task definition, the interfaces of the modules it needs, and the verification criteria.
3. **Deterministic Return (`ret`):** On completion, the subagent returns a structured frame carrying status (`:ok` or `:err`), gate verdicts and artifact references.

The same idea already runs in the workspace's own agent loop: the `(:agent ...)` op takes an `:owns` list, edits only inside it and runs the named `:gates`, and its receipt reports status, findings and gate results.

---

## 4. Context Drift: What We Expect, and What We Have Not Yet Measured

The argument for typed frames is that a handoff which is an immutable, schema-checked S-expression cannot be paraphrased: hop 100 receives the same constraint values as hop 1, where a chat protocol re-describes them at every hop.

We have not yet run a multi-hop drift benchmark comparing natural language chat, JSON-RPC and AgP, so we make no quantitative claim here. The experiment we intend to run is a chain of agents that each receive an invariant configuration, apply a local transformation and forward the state, scored on whether the invariant survives to the last hop.

---

## 5. Architectural Summary

Autonomous agent swarms do not scale on top of human conversational metaphors.

Sigil-headed S-expression frames, a closed error taxonomy, and context-isolated delegations (`pass` / `ret`) are the substrate we are building for multi-agent software engineering: typed state instead of chatter, and failures that are keywords instead of prose.
