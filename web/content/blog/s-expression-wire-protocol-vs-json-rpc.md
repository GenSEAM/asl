# Many Calls in One Frame: ASN Wire Batches vs. Chatty JSON-RPC
*Published on September 11, 2026 · 4 min read · By the GenSEAM Team*
*Canonical URL: https://aslang.dev/blog/s-expression-wire-protocol-vs-json-rpc*

When an agent works through the `asl` toolbelt or across the agent bus, requests and receipts are written in Agent Slang Notation (ASN)—the same S-expression grammar as the code itself. Because every operation is a self-contained form, an agent packs a query, a symbol read, a staged edit and a checker run into one call, and receives one `(:batch ...)` frame with an ordered receipt for each step. Code and structured receipts travel as native forms rather than double-escaped strings inside JSON-RPC envelopes.

## 1. Why JSON-RPC Adds Friction to Agent Loops

JSON-RPC was designed for single request/response pairs with named-field objects. Under byte-pair encoders (`cl100k_base`, `o200k_base`), every call pays for repeated key quotes, colons, commas and braces—and when the payload is source code, every quote and newline inside it has to be backslash-escaped. Worse, running four dependent repository operations one tool call at a time costs four model round trips.

## 2. S-Expressions as Batchable Wire Payloads

ASN writes wire frames as S-expressions: bare keywords (`:read`, `:edit`, `:check`), whitespace separation, and balanced parentheses. A batch is simply a list of forms sent in one turn and answered in one receipt.

## 3. One Measured Example

We have not run a benchmark across a corpus of tool calls, so this post quotes no average saving. What we have is one example, recorded in the project README: a `git status --short` tool call, counted with `cl100k_base`.

| Frame | `cl100k_base` tokens |
|---|---|
| JSON object with named fields | 51 |
| positional ASL frame `(! cmd "git" ["status" "--short"] "/app" 5000)` | 18 |

That is one call, not a distribution. Part of the saving comes from the notation and part from the frame being positional rather than named, and the positional `(! ...)` sigil frame is the target design of `docs/agenticProtocol.md`, not something the code speaks yet.

## 4. What Runs Today

The implemented wire is smaller than that design. `packages/asl-agent-bus/src/wire.asl` defines a canonical frame of five string fields (`identity`, `sessionId`, `causality`, `payload`, `digest`) with encoders and decoders for stdio, Unix sockets, HTTP and SSE; `ndAsn.asl` carries newline-delimited ASN frames. Their suites pass (`asl test`, 2026-10-14: `wireTest` 29 assertions, `ndAsnTest` 31, `transportTest` 18).

There is no shared-memory transport, and we have not measured latency or throughput for any of these paths. The ring buffer in `asnlRing.asl` is an in-language data structure, not a POSIX shared-memory segment. When we publish dispatch figures, they will come with the command that produced them.
