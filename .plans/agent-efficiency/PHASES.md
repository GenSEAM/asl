# Roadmap & Implementation Plan: Agent-Native Efficiency Suite (`asl-agent-efficiency-v1`)

**Goal**: Equip autonomous AI agents with an end-to-end efficiency toolkit covering semantic HTML/DOM compaction (-78% tokens), intent-first element inspection & manipulation, hierarchical in-memory knowledge retrieval, and zero-bloat context synthesis (@pcp:d-676f).

## Status: PLANNED (Scheduled for execution following Self-Hosting & Admin Toolkit completion)

---

### Phase 1: Agent-Native HTML & DOM Compaction (`packages/asl-vdom`, `packages/asl-browser-plugin`)
- [ ] Implement fast streaming HTML/DOM-to-S-Expression converter in `packages/asl-vdom` and `packages/asl-browser-plugin`.
- [ ] Aggressively prune non-semantic noise: remove raw SVG paths, inline styles, script blocks, redundant wrapper `<div>`s, and CSS class soup.
- [ ] Preserve high-value agent semantics: ARIA roles, accessible names, active form values, component boundaries, and viewport visibility.
- [ ] Automated verification gate: verify $\ge 75\%$ prompt token reduction across real-world web applications (GitHub, Linear, Dashboard templates).

### Phase 2: Intent-First Element Control & Diagnostics Toolkit
- [ ] Design resilient semantic element locator: query elements by functional intent (`:role "button" :label "Deploy"`) rather than fragile CSS selectors or dynamic hash IDs.
- [ ] Typed agent action vectors: `(? ui/click :target elem)`, `(? ui/fill :target elem :text "val")`, `(? ui/submit :target form)`.
- [ ] Real-time UI diagnostics & anomaly detection: track excessive re-render loops, hydration mismatches, layout shifts (CLS), and unhandled console errors.
- [ ] Emits structured S-expression diagnostic frames: `(! ui/anomaly :type :excessive-rerender :component "TaskGrid" :count 18)`.

### Phase 3: Hierarchical Knowledge & Memory Matrix (`packages/asl-mem`, `packages/asl-search`)
- [ ] Integrate zero-server 64KB Wasm vector store (`packages/asl-mem`) for instant in-memory similarity search (target: $<0.05$ ms latency).
- [ ] Hierarchical RAG Context Compressor: transform multi-file codebase scans into compact context digests with exact file line ranges and symbol summaries.
- [ ] Project entity caching: index AST schemas, exported functions, and module dependency graphs into local cache for instant agent retrieval without reading raw files.

### Phase 4: CLI Commands & Universal Agent Mesh Tooling
- [ ] CLI Integration in `agentscript`:
  - `asl dom compress <file.html|url>`: outputs compressed S-expression DOM tree.
  - `asl dom query <selector|intent>`: finds elements matching semantic intent.
  - `asl mem index <path>`: builds local Wasm vector index of project files.
  - `asl mem query "<search query>"`: returns compressed semantic context digest.
- [ ] Model Context Protocol (MCP) tool bindings: expose tools natively to Antigravity, Cursor, Claude Code, and Cline.
- [ ] Comprehensive test suite and automated CI gates across all platforms.
