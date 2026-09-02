# Phases — asl-quality-tools-v1

Enforce Nano-Format Default, Anti-Pattern / Smell Linter, AST Structural Clone Detection, and Zero-Blocker Auto-Fixers (`asl lint`, `asl fix`, `asl fmt`) with all core domain logic implemented natively in AgentScript (`.asl`).

## Ordered Phases

1. **Phase 1: Nano-Format Default Wire Enforcement & Dual-Mode Bidirectional Transcoder**
   - Core ASL: `packages/asl-skyloom/src/core/skyloom.asl`
   - Acceptance: `.venv/bin/python checker/gate.py && node packages/asl-skyloom/dist/tests/nano_enforcement_test.js` exits 0.
2. **Phase 2: Native ASL Linter & Smell Detector Engine (`packages/asl-lint/src/core/lint.asl`)**
   - Core ASL: `packages/asl-lint/src/core/lint.asl` checked by `asl check`
   - Acceptance: `.venv/bin/python -m pytest tools/tests/test_linter.py -q` exits 0.
3. **Phase 3: Native ASL Structural Clone & Duplicate Code Detector (`packages/asl-lint/src/core/clone.asl`)**
   - Core ASL: `packages/asl-lint/src/core/clone.asl` checked by `asl check`
   - Acceptance: `.venv/bin/python -m pytest tools/tests/test_clone_detector.py -q` exits 0.
4. **Phase 4: Native ASL Autonomous Auto-Fixer & Formatter (`packages/asl-lint/src/core/heal.asl`)**
   - Core ASL: `packages/asl-lint/src/core/heal.asl` checked by `asl check`
   - Acceptance: `.venv/bin/python -m pytest tools/tests/test_auto_fix.py -q` exits 0.
5. **Phase 5: Pre-Commit Quality Gate Integration & Web Doctor Dashboard**
   - Acceptance: `.venv/bin/python agentscript lint packages/asl-skyloom/src/core/skyloom.asl && /usr/local/bin/node web/node_modules/vite/bin/vite.js build web` exits 0.

## Out of Scope

- **Dynamic Wasm Binary Monkey-Patching**: Linting and fixing operate strictly at the AST and source level before compilation.
- **LLM Model Fine-Tuning**: Tooling operates via deterministic tree-sitter & AST transformations without model weight updates.
