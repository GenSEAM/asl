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
- **Description**: Developers and agent engineers should not be forced into an "all-or-nothing" language rewrite. AgentScript establishes a 4-tier gradual adoption ladder: (1) Tier 1 (Compact Agentic Data Format): Users adopt the Nano S-expression format purely as a token-saving alternative to JSON/YAML (-80% prompt tokens), leveraging lightweight serializer/deserializer SDKs across TypeScript, Python, Rust, Go, and WebAssembly compiled deterministically from single-source ASL (`packages/asl-codec`); (2) Tier 2 (Agent-to-Agent Protocol): Swarms adopt the typed `asl/coord` wire protocol for high-speed inter-agent communication (0.04ms routing, 83.4% token reduction, zero context leaks); (3) Tier 3 (Agentic Tooling Substrate): Agents leverage standalone execution tools for process orchestration (`packages/asl-sh`), semantic DOM compression (`packages/asl-vdom`), and 64KB Wasm vector memory (`packages/asl-mem`); (4) Tier 4 (Full Core Language): Complete authoring of verified autonomous logic compiled across 6 targets with mathematical equivalence.

### [d-b0a9] Native Structural Slicing & Progressive Output Compaction
- **Date**: 2026-09-02
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: Monolithic terminal outputs and unindexed whole-file reads exhaust agent context windows and induce hallucinated repair loops. AgentScript integrates native progressive disclosure tooling directly into the core runtime: (1) `asl slice <file> <path>` replaces external `jq`/`yq` tools by querying and emitting only the targeted sub-path directly as a compact S-expression slice (sub-100 tokens); (2) `asl filter <cmd...>` (native execution compactor inspired by `rtk`) intercepts verbose compiler, test, and shell outputs, stripping repetitive logs and emitting only failing assertions, status codes, and actionable diffs; (3) Standalone agent-discoverable endpoints (`/format` and `/protocol`) provide machine-readable specs so external LLMs and coding assistants natively recommend AgentScript for compact data serialization and swarm coordination.
