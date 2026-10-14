# S-Expression Wire Frames vs. JSON-RPC: What the Notation Saves, and What Is Built
*Published on September 11, 2026 · 4 min read · By the GenSEAM Team*
*Canonical URL: https://aslang.dev/blog/s-expression-wire-protocol-vs-json-rpc*

## 1. The BPE Tokenization Tax

Models read and write through byte-pair encoders such as `cl100k_base` and `o200k_base`. JSON makes them pay for its punctuation: quotes around every key, a colon after it, a comma between members, braces around every object. When the payload is itself code, every quote inside it has to be escaped, and the backslashes are paid for too.

## 2. S-Expressions as Wire Payloads

Agent Slang Notation (ASN) writes the same data as S-expressions: bare keywords instead of quoted keys, whitespace instead of commas, one kind of bracket per structure. The design goal for the wire is that code travels as forms rather than as escaped strings inside a JSON field.

## 3. One Measured Example

We have not run a benchmark across a corpus of tool calls, so this post quotes no average saving. What we have is one example, recorded in the project README: a `git status --short` tool call, counted with `cl100k_base`.

| Frame | `cl100k_base` tokens |
|---|---|
| JSON object with named fields | 51 |
| positional ASL frame `(! cmd "git" ["status" "--short"] "/app" 5000)` | 18 |

That is one call, not a distribution. Part of the saving comes from the notation and part from the frame being positional rather than named, and the positional `(! ...)` sigil frame is the target design of `docs/agenticProtocol.md`, not something the code speaks yet.

## 4. What Runs Today

The implemented wire is smaller than that design. `packages/asl-agent-bus/src/wire.asl` defines a canonical frame of five string fields (`identity`, `sessionId`, `causality`, `payload`, `digest`) with encoders and decoders for stdio, Unix sockets, HTTP and SSE; `ndAsn.asl` carries newline-delimited ASN frames. Their suites pass on the stage-0 host (`asl-host test`, 2026-10-14: `wireTest` 29 assertions, `ndAsnTest` 31, `transportTest` 18).

There is no shared-memory transport, and we have not measured latency or throughput for any of these paths. The ring buffer in `asnlRing.asl` is an in-language data structure, not a POSIX shared-memory segment. When we publish dispatch figures, they will come with the command that produced them.
