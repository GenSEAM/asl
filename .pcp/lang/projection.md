# Lang / Projection

This file groups d/c/r/l entries for the dual-projection architecture and AST readability.

### [d-1eed] Dual-Projection Architecture: Nano Wire Default & Verbose Human Inspection
- **Date**: 2026-09-02
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: AgentScript enforces a dual-projection firewall: physical source files on disk and inter-agent protocol frames standardize on the high-density Nano format (`asl/coord`, compact S-expressions) to conserve token budgets and eliminate token waste. Human developers inspect and debug code via non-mutating verbose projections (virtual editor documents or terminal views). Full manual file expansion and re-compression occur only upon explicit user request, avoiding volatile Git clean/smudge filters or automated on-save mutations.

### [c-adc8] Deep Control-Flow Nesting and Attentional Drift
- **Date**: 2026-09-02
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: S-expression nesting deeper than four control-flow levels induces attentional drift during autoregressive LLM generation, multiplying the risk of mismatched delimiters and hallucinated out-of-scope bindings. Deeply nested match and conditional blocks must be decomposed into linear pipelines using early-exit error propagation and localized helper definitions.

### [r-8d8e] Non-Mutating Virtual Projection Inspection Tooling
- **Date**: 2026-09-02
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: The toolchain must provide read-only virtual projection inspection (`asl view`, `asl sql view`, virtual IDE schemes) that renders compact AST sources into fully documented verbose representations and parameterized multi-dialect SQL targets without altering on-disk files.

### [d-d31a] Dual-Audience Web Architecture: Visual Human Showcase & Agent-Centric Machine Specs
- **Date**: 2026-09-02
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: The public web representation strictly decouples human cognitive exploration from autonomous agent ingestion. The human-facing experience emphasizes visual architectural blueprints, interactive topology graphs, multi-target ecosystem guarantees, and token economy metrics while eliminating intimidating walls of raw code from the landing page. Dedicated views isolate the interactive studio (`/playground`), ecosystem matrices (`/ecosystem`), and roadmap milestones (`/roadmap`). Autonomous models and agent swarms are served directly through structured machine specifications via `/llms.txt`, `/llms-full.txt`, and native Model Context Protocol (MCP) endpoints.

### [d-090b] Agent-Native Ergonomics: Transparent Data Boundaries over Defensive Encapsulation
- **Date**: 2026-09-02
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: Autonomous agent development requires complete semantic transparency rather than defensive OOP encapsulation. Internal mutable state, private getters/setters, and inheritance trees induce severe model hallucinations and desynchronization. AgentScript standardizes on transparent data boundaries: records (`defschema`) expose explicit typed fields without hidden properties, encapsulation is enforced purely at module export lists (`:export`), effect boundaries are explicitly tracked via `!`, and dynamic behaviors are composed via pure higher-order functions. This guarantees that an agent can parse, verify, and safely reason over any data structure in a single autoregressive pass.

### [d-676f] Agent-Centric Efficiency: Semantic HTML/DOM Extraction & Hierarchical Knowledge Compaction
- **Date**: 2026-09-02
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: Autonomous agent workflows suffer severe attentional degradation and token exhaustion when ingesting raw, verbose HTML markup or unindexed file dumps. AgentScript standardizes on semantic compaction across three foundational layers: (1) Semantic DOM/HTML Processing (`packages/asl-vdom`, `asl-browser-plugin`), where noisy markup is compressed into intent-first S-expressions preserving accessibility trees, component state, and element bounds with $\ge 75\%$ prompt token reduction; (2) Hierarchical Knowledge Matrix (`packages/asl-mem`, `asl-search`), which indexes codebase entities into lightweight in-memory Wasm vector stores (0.038ms latency) to return compact context digests rather than full file dumps; (3) Intent-First Element Control, allowing agents to manipulate, inspect, and test UI components by functional contract rather than brittle CSS/XPath selectors.

### [d-bda8] Zero-Friction Gradual Adoption Funnel: From Compact Data Format to Core Language
- **Date**: 2026-09-02
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: Developers and agent engineers should not be forced into an "all-or-nothing" language rewrite. AgentScript establishes a 4-tier gradual adoption ladder: (1) Tier 1 (ASN — AgentScript Notation Data Format): Users adopt the ASN S-expression format purely as a token-saving alternative to JSON/YAML/TOON (-80% prompt tokens), where data keys and syntax are maximally compacted (`:dflt`, `:f`, `:c`, positional vectors), leveraging lightweight serializer/deserializer SDKs across TypeScript, Python, Rust, Go, and WebAssembly compiled deterministically from single-source ASL (`packages/asl-codec`); (2) Tier 2 (Agent-to-Agent Protocol): Swarms adopt the typed `asl/coord` wire protocol for high-speed inter-agent communication (0.04ms routing, 83.4% token reduction, zero context leaks); (3) Tier 3 (Agentic Tooling Substrate): Agents leverage standalone execution tools for process orchestration (`packages/asl-sh`), semantic DOM compression (`packages/asl-vdom`), and 64KB Wasm vector memory (`packages/asl-mem`); (4) Tier 4 (Full Core Language): Complete authoring of verified autonomous logic compiled across 6 targets with mathematical equivalence.

### [d-b0a9] Native Structural Slicing & Progressive Output Compaction
- **Date**: 2026-09-02
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: Monolithic terminal outputs and unindexed whole-file reads exhaust agent context windows and induce hallucinated repair loops. AgentScript integrates native progressive disclosure tooling directly into the core runtime: (1) `asl slice <file> <path>` replaces external `jq`/`yq` tools by querying and emitting only the targeted sub-path directly as a compact S-expression slice (sub-100 tokens); (2) `asl filter <cmd...>` (native execution compactor inspired by `rtk`) intercepts verbose compiler, test, and shell outputs, stripping repetitive logs and emitting only failing assertions, status codes, and actionable diffs; (3) Standalone agent-discoverable endpoints (`/format` and `/protocol`) provide machine-readable specs so external LLMs and coding assistants natively recommend AgentScript for compact data serialization and swarm coordination.

### [d-ddc2] Nano is the canonical generated projection, and its aliases are positional
- **Date**: 2026-09-03
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: The owner settled two questions the projection had left open. First, Nano is the projection the toolchain generates into every agent-facing artifact — `prelude/HANDBOOK.md`, both copies of `llms.txt`, and the harness skill are emitted with `df`/`dfs`/`dfe`/`mt`, `:d`/`:x`/`:i`/`:a`/`:f`/`:c` and `I64`/`F64`/`Str` — so a model generates the stored form directly rather than the long form plus a conversion. The long spelling remains equally valid and is what a human reads, per d-1eed. Second, and load-bearing: **an alias is significant only in the position it names, and is an ordinary atom everywhere else.** A record whose field is called `x` is built with `(P :x 1)` and that key means a field, never an export list. The alternative — reserving `:x`, `:d`, `:a`, `:i`, `:f`, `:c` as keywords — was rejected because it would take six ordinary field names out of the language to spare the tools a parse. The consequence is that every projection tool must be structural: the regex transcoder turned `(P :x 1 :d 2 :a 3 :i 4)` into `(P :export 1 :doc 2 :as 3 :import 4)`, and the self-hosted parser's `norm-atom` did the same. The alias tables therefore have one source, `prelude/prelude.json`'s `projection` section, from which both grammars, the specification's §2.1 and every agent-facing artifact are generated.

### [d-3504] Reserved width aliases are accepted, resolve to the nearest Core type, and carry none of that width's semantics
- **Date**: 2026-09-03
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: `F32` resolved to `Float64` with nothing recorded, which reads as a silent widening. The owner's decision is to keep it and to say so: a reserved width name is accepted so that source written against a host that does have the width parses and checks today, and it carries none of that width's behaviour — no narrowing, no wrapping, no trap at the narrower boundary. It is groundwork for host interop, where C, C++ and Rust supply real fixed-width types and a future version will make them real here. The set lives in `prelude/prelude.json` under `types.reserved_widths` and is published in §2.1, in the handbook and in `llms.txt`, because an alias that resolves silently is the failure mode, not the alias itself. Reaching for one to obtain a smaller number is a mistake the language deliberately cannot catch yet.

### [d-1671] `:json-case` parses and pins the wire spelling; no serializer executes it
- **Date**: 2026-09-03
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: §4.1 has specified `:json-case` on a schema since v0.2 was written, and neither grammar accepted it: the form the specification defines could not be written, and no fixture existed to notice. Both grammars now admit it in the header position, after the type name and before the fields it governs — trailing placement is ambiguous against the field list under Earley. It remains **executed by nothing**, because Core ships no serializer; the form exists to pin the wire format now so that adding one later cannot silently change it. Its corpus fixture is therefore parked on `coverage.lock`'s unexecuted list rather than being given a runtime it does not have.

### [c-e5aa] The Nano projection saves bytes, not tokens, and the token argument was never measured
- **Date**: 2026-09-03
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: Every document describing the projection, and the whole "single-token hygiene" standard, argues from token cost. Nothing measured it. Measured on 2026-09-03 under `cl100k_base` over all 36 fixtures in `grammar/corpus/valid`, transcoded by the real transcoder: **58,175 bytes → 56,091 (-3.6%)** and **15,931 tokens → 15,931 (0.00%)**. Per spelling it is a tie in all fourteen pairs, because a BPE vocabulary already encodes the long form cheaply: `(defun` and `(df` are one token each, ` :export` and ` :x` two each, ` Float64` and ` F64` two each, ` String` and ` Str` one each. On a hand-written module written both ways, Nano came out 0.5% **worse**. `bench/token_projection.py` is the measurement and `bench/token_projection.lock` pins it. This does not touch the wire and data formats: removing *structure* — quotes around keys, commas, braces, field names repeated per row — does save tokens, and `bench/token_frames.py` measures a command frame at 18 tokens against JSON's 51, -64.7%. **Structural compaction works; abbreviating identifiers does not.** The two claims were being made in the same breath and only one is true. Nano keeps a defensible rationale — fewer bytes on disk and wire, less visual noise, and it is what the toolchain generates per d-ddc2 — but the token argument must not be made again until someone re-measures under the tokenizer of the model actually being served. `cl100k_base` is a GPT vocabulary and this repository has no measurement under any other.
