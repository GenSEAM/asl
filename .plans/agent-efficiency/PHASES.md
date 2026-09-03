# Roadmap & Implementation Plan: Agent-Native Efficiency Suite (`asl-agent-efficiency-v1`)

**Goal**: Equip autonomous AI agents with an end-to-end efficiency toolkit covering semantic HTML/DOM compaction (-78% tokens), dual perception (AXTree + Structural Downsampling), incremental state diffing, hierarchical in-memory knowledge retrieval, zero-token pre-compacted execution, and output token generation economy (@pcp:d-676f, @pcp:d-29ef).

## Status: PLANNED (Prerequisite foundation for `asl-browser-agent-v1`)

---

### Phase 1: Dual Perception HTML/DOM Compaction (`packages/asl-vdom`)
- [ ] **Tier 1: Accessibility Tree (AXTree) Extractor**: Extracts browser accessibility nodes (roles, accessible names, interactive states, descriptions), reducing standard pages to a few hundred tokens.
- [ ] **Tier 2: Structural DOM Downsampler (D2Snap)**: For canvas, complex panels, or non-semantic HTML: parses the DOM tree, collapses repeated sibling items, strips CSS class soup, inline styles, scripts, and decorative wrapper `<div>`s into compact S-expression trees.
- [ ] **Incremental DOM Diffing**: Transmits mutations (`(! dom/diff :route r :added [...] :removed [...] :mutated [...])`) rather than full page trees on each agent cycle.
- [ ] **Benchmark Gate**: Verify $\ge 75\%$ prompt token reduction compared to raw `outerHTML` across modern web apps (GitHub, Linear, Dashboard templates).

### Phase 2: Intent-First Element Control & Diagnostics Toolkit
- [ ] **Semantic Element Locator**: Query elements by functional intent (`:role "button" :label "Deploy"`, form control purpose, or `:test-id`) rather than fragile CSS/XPath selectors.
- [ ] **Typed Action Vectors**: Safe, non-evaluating action frames:
  - `(? ui/click :target elem)`
  - `(? ui/fill :target elem :text "val")`
  - `(? ui/submit :target form)`
  - `(? ui/select :target elem :value val)`
- [ ] **Real-time Diagnostics & Anomaly Detection**: Track excessive re-render loops, hydration mismatches, layout shifts (CLS), and console exceptions.
- [ ] Emits structured S-expression anomaly frames: `(! ui/anomaly :type :excessive-rerender :component "TaskGrid" :count 18)`.

### Phase 3: Hierarchical Knowledge & WASI Workspace Mounting (`packages/asl-mem`, `packages/asl-search`)
- [ ] **Zero-Server 64KB Wasm Vector Store (`packages/asl-mem`)**: Ultra-fast cosine similarity search engine running in a single Wasm page (latency: $<0.05$ ms for 5,000 vectors).
- [ ] **WASI Directory Mounting (`asl run --mount <dir> <tool.wasm>`)**: Mounts project or subdirectories into the isolated Wasm sandbox. Wasm tools scan, search, and parse ASTs in-memory (<15ms) without raw socket leaks or host exposure.
- [ ] **Zero-Token Pre-Compacted Execution**: Instead of models writing multi-step inspection scripts over 10 turns, mounted Wasm tools emit pre-compacted sub-100-token S-expression digests directly to the agent.
- [ ] **Project Entity & Call-Graph Cache**: Caches module exports, schemas, and AST topology for instant sub-symbol retrieval without disk thrashing.

### Phase 4: Output Token Economy & Universal CLI Interfaces
- [ ] **Output Generation Token Economy Benchmark**:
  - Benchmark model output generation tokens: compare generating 5-line ASL Nano pipelines vs
    50-line Python/TS/Bash scripts. **Measure the program, not the spelling.** The projection's own
    short spellings save 3.6% of bytes and 0.00% of tokens (`bench/token_projection.py`, PCP
    `c-e5aa`), so any saving here has to come from the pipeline being shorter than the script, and
    the benchmark must be built so the two causes cannot be confused.
  - Assert $\ge 70\%$ output token reduction and $5\times$ faster decode turnaround latency.
- [ ] **CLI Integration in `agentscript`**:
  - `asl dom compress <file.html|url>`: outputs compressed S-expression DOM tree.
  - `asl dom diff <old.html> <new.html>`: outputs structured DOM mutation diff.
  - `asl dom query <selector|intent>`: finds elements matching semantic intent.
  - `asl mem index <path>`: builds local Wasm vector index of project files.
  - `asl mem query "<search query>"`: returns compressed semantic context digest.
- [ ] **Model Context Protocol (MCP) Bindings**: Expose tools natively to Antigravity, Cursor, Claude Code, and Cline.
- [ ] **Verification**: Automated test suite covering parser edge cases, memory footprint, and cross-platform compilation.
