# Iteration: asl-ecosystem-audit-v1
Goal: Full Ecosystem Audit: Packages, API contracts, Dual-Projection, Protocols, Self-Hosting ASL Parser feasibility & Hardening.

## Phases

### Phase 1: Packages & API Contract Consistency Audit
- Goal: Audit all 24 packages and manifests (`asl.json`), export signatures, import topologies, and docstring coverage.
- Checkable Criterion: `.venv/bin/python tools/module_graph.py --summary && .venv/bin/python agentscript lint packages/`

### Phase 2: Dual-Projection & Syntax Conformance Audit
- Goal: Verify lossless bidirectional transcoding (Ultra-Nano <-> Verbose), evaluate feasibility of Self-Hosting Native ASL Parser replacing Lark/Tree-sitter.
- Checkable Criterion: `.venv/bin/python tools/tests/test_ultra_nano.py && .venv/bin/python grammar/validate.py`

### Phase 3: Protocols, Mesh & Security Isolation Audit
- Goal: Audit SkyLoom frames, Agent-Bus sockets, SQL cross-dialect polyfills, and sandboxed jailing boundaries.
- Checkable Criterion: `.venv/bin/python -m pytest tools/tests/test_sandbox.py tools/tests/test_sql.py tools/tests/test_graph.py -q`

### Phase 4: Verification, Hardening & Ecosystem Report
- Goal: Address all identified gaps, run full 7-gate CI pre-commit pipeline, update documentation and emit audit report.
- Checkable Criterion: `node /Users/purplelephant/.gemini/config/skills/pcp/scripts/pcp.js actualize && npm run build:web`

## Out of Scope
- Breaking existing AST nodes in corpus fixtures (compatibility must remain green).
- Adding heavy external C/Node dependencies.
