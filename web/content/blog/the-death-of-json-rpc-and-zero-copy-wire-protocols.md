# Beyond JSON-RPC: Why ASL Frames Agent Messages as S-Expressions
*Published on September 10, 2026 · 6 min read · By the GenSEAM Team*
*Canonical URL: https://aslang.dev/blog/the-death-of-json-rpc-and-zero-copy-wire-protocols*

## 1. The Bottleneck

Most agent stacks today follow industry defaults: tools are described with JSON Schema, and every call travels as a JSON-RPC 2.0 message. That works, but it charges a model in two places on every call.

Here is a tool call that asks for one function out of one file:

```json
{"jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": {"name": "read", "arguments": {"file": "src/server.asl", "symbol": "handleRequest"}}}
```

And here is the same request as the `asl` toolbelt takes it today:

```asl
(:read :file "src/server.asl" :symbol "handleRequest")
```

Counted with `cl100k_base` (js-tiktoken 1.0.15, 2026-10-14), the JSON-RPC message is 51 tokens and the form is 15; under `o200k_base` they are 52 and 16. One example, not a benchmark: the gap is the envelope (`jsonrpc`, `id`, `method`, `params`, `arguments`) plus the quotes and colons around every key.

## 2. The Structural Flaw

JSON was designed to pass small associative arrays into JavaScript runtimes. Used as the wire between a model and its tools, it imposes two costs.

### The quotation tax
Every JSON property key needs two quotes and a colon (`"symbol":`), and the envelope repeats on every call. The README's example, one `git status` command, is 51 `cl100k_base` tokens as a JSON object and 18 as a positional S-expression frame.

### The escaping problem
Code is rich in quotes and backslashes. Put code inside a JSON string and every `"` becomes `\"`; put that message inside another string, as happens when a tool call is logged, forwarded or wrapped by a second agent, and the escapes double (`\\\"`). A model generating left to right has to track that depth, and one wrong backslash makes the whole message unparseable.

ASL strings escape the same way, so an ASN string is not immune. What S-expressions change is that a payload which is itself code or data does not have to be a string at all: ASL source and ASN data share one syntax, so a frame can carry a form as a form, nested in parentheses, with no escaping and nothing to re-parse.

## 3. What Exists Today

The implemented wire is small and deliberately plain:

- `grammar/wire.asn` declares a `CanonicalWireFrame` of five fields (`identity`, `sessionId`, `causality`, `payload`, `digest`), its errors, and four transports: stdio, Unix socket, HTTP and SSE.
- `packages/asl-agent-bus/src/wire.asl` validates, encodes and decodes that frame per transport; `transport.asl` adds frame types (handshake, heartbeat, request, response, stream chunk, close); `ndAsn.asl` carries newline-delimited ASN frames.
- These suites pass on the stage-0 host: `wireTest.asl` (29 assertions), `transportTest.asl` (18), `ndAsnTest.asl` (31), `presenceTest.asl` (24) and `meshTest.asl` (40), run on 2026-10-14.

Today the frame's `payload` field is a string, so the "form as a form" property above is not yet used on this wire.

## 4. What Is Still Design

The AgentScript wire protocol (AgP, `docs/agenticProtocol.md`) is a target design, and its own status line says so. It specifies sigil frames with a space after the sigil:

```text
(? agentCoder synthesizeFsm :states ["idle" "active" "error"] :timeoutMs 50)
(! agentCoder :ok (fsm :states 3))
(~ s1 :seq 0 :chunk "...")
```

and a session layer for dialect negotiation, handshake and handoff. None of it is implemented yet.

An earlier version of this post described a shared-memory ring buffer built on `mmap` and `shm_open`, and a benchmark table of payload sizes, latencies, failure rates and throughput. No such transport exists in the repository, and no measurement backs those figures, so both are withdrawn. The bus's `asnlRing.asl` is an in-memory ring of ASN frames held as an ordinary list, not a shared-memory queue. A comparison against JSON-RPC will be published with its method, scope and date, or not at all.

## 5. Try It

```bash
# One batch of agent-plane forms: search, then a bounded read
asl '(:query :text "handleRequest") (:read :file "src/server.asl" :symbol "handleRequest")'

# The wire codec suites on the stage-0 host (from the directory above the asl checkout)
asl/host/out/asl-host test asl/packages/asl-agent-bus/tests/wireTest.asl
```

## 6. Resources

- The language and toolchain: [github.com/GenSEAM/asl](https://github.com/GenSEAM/asl)
- The data notation: `docs/asnSpec.md` in that repository
- The wire design: `docs/agenticProtocol.md` in that repository
