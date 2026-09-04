# ASL Syntax & Branding Cleanup: Phases & Acceptance Criteria

Goal: Eliminate "Nano" terminology from all public surfaces, READMEs, and documentation across the repository and packages. Establish that AgentScript (ASL) is compact by default; the long projection is "ASL Verbose" (purely for human debugging/inspection via `asl view`). Remove TOON from the main README Face-Off, show a strict 1-to-1 comparison between JSON and native ASL (positional zero-key form), and document where the keyed form is required.

## Architectural Invariants
1. **ASL is Compact by Default**: The standard syntax of AgentScript is the concise S-expression notation. It is not called "Nano"; it is simply ASL.
2. **ASL Verbose is Solely for Debugging**: The expanded form is ASL Verbose, accessed via `asl view` and `asl transcode --to verbose` for inspection.
3. **1:1 Face-Off without Intermediaries**: Main README compares Verbose JSON directly to AgentScript (ASL) positional zero-key form. TOON is removed.
4. **No Python Modifications**: Python files and benchmarks are untouched.

---

## Ordered Phases

### Phase 1: Main README Face-Off & Quickstart Refactor (`README.md`)
- **Objective**: 
  - Remove TOON from the Face-Off comparison.
  - Present strict 1:1 comparison: Verbose JSON vs AgentScript (ASL).
  - Feature positional zero-key form `(! cmd "git" ["status" "--short"] "/app" 5000)` (18 tokens, -64.7%).
  - Add an explanatory callout demonstrating where positional notation is insufficient and keyed form is used (sparse optional fields, default overrides).
  - Update quickstart and tools sections to reference ASL Verbose (`asl view`, `asl transcode --to verbose`).
  - Eliminate all occurrences of "Nano" from `README.md`.
- **Paths**: `README.md`
- **Acceptance Criterion**: `! grep -i "nano" README.md && ! grep -i "toon" README.md && .venv/bin/python tools/doc_examples.py --quiet`

### Phase 2: Packages and Skills READMEs Audit (`packages/*/README.md`, `skills/README.md`)
- **Objective**:
  - Remove "Nano" references across `packages/*/README.md` and `skills/README.md`.
  - Update `skills/README.md` to reference standard ASL syntax.
  - Update `packages/asl-context/README.md` and any other package READMEs.
- **Paths**: `skills/README.md`, `packages/asl-context/README.md`
- **Acceptance Criterion**: `git grep -i -E "nano syntax|nano format|agentscript nano|pure asl nano" packages/ skills/ || true` returns 0 matches.

### Phase 3: Documentation & Web Alignment (`docs/`, `web/`)
- **Objective**:
  - Update `docs/NANO_SYNTAX.md` header and content to frame standard ASL vs ASL Verbose.
  - Update `docs/CONTEXT_ECONOMY_GUIDELINES.md` table and prose.
  - Update `docs/blog/05-token-economy-and-nano-projection.md` to frame ASL vs ASL Verbose.
  - Update `web/` metadata and components (`ModuleGraphVisualizer.tsx`, `RoadmapView.tsx`, `index.html`) to replace "Nano" with "ASL" or "ASL Verbose".
- **Paths**: `docs/NANO_SYNTAX.md`, `docs/CONTEXT_ECONOMY_GUIDELINES.md`, `docs/blog/05-token-economy-and-nano-projection.md`, `web/src/views/RoadmapView.tsx`, `web/src/components/ModuleGraphVisualizer.tsx`, `web/index.html`
- **Acceptance Criterion**: `.venv/bin/python tools/doc_examples.py --quiet && npm --prefix web run build`

### Phase 4: Full Verification & Repository Gate
- **Objective**: Run full validation suite ensuring all docs, examples, locks, and builds pass cleanly.
- **Paths**: All modified files.
- **Acceptance Criterion**: `.venv/bin/python bench/token_frames.py --check && .venv/bin/python tools/doc_examples.py --quiet && npm --prefix web run build`
