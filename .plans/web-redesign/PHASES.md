# Iteration: asl-web-redesign-v1
Goal: Unified Cosmic Blueprint Design System, Vector Chameleon & Curled-'a' Logos, Key Capabilities Blueprint Cards, Honest UI & Data Consistency.

## Phases

### Phase 1: Design System & Vector Identity Assets (`web/src/index.css`, `web/src/components/ui/Logo.tsx`)
- Goal: Implement deep cosmic violet-slate palette, blueprint grid utilities, glowing gradients, and precision vector logos:
  - `ChameleonALogo`: Signature purple letter 'a' with spiral chameleon tail.
  - `ChameleonSchematic`: Refined vector mascot with cleaned-up crest (redundant vertical divider removed) and golden-ratio tail curl matching the 'a' mark.
  - SVG Favicon and Brand wordmark.
- Checkable Criterion: `cd web && npm run build`

### Phase 2: Hero Section & Blueprint Key Capabilities (`web/src/components/Hero.tsx`, `KeyCapabilities.tsx`)
- Goal: Implement the new Hero section with background schematic chameleon watermark, brand shield, [A] / [B] sub-cards, CLI install card, and the 3 blueprint-rich Key Capabilities cards (Observability, Terminal workflow, Ecosystem drafting tools).
- Checkable Criterion: `cd web && npm run build`

### Phase 3: Interactive Components & Honest UI Consistency (`web/src/components/Navbar.tsx`, `SearchModal.tsx`, `Footer.tsx`)
- Goal: Replace fake metrics (4.1k star count) with honest GitHub repository links, integrate floating pill navigation with `Cmd + K` search modal, and harmonize existing interactive visualizers (`SkyLoomVisualizer`, `AslQualityDoctor`, `SqlStudio`, `ModuleGraphVisualizer`) with the new visual system.
- Checkable Criterion: `cd web && npm run build`

### Phase 4: Production Build, Responsiveness & Deployment Gate
- Goal: Verify full production bundle generation, responsive layouts across mobile/desktop, accessibility contrast, and ensure zero regressions across the codebase.
- Checkable Criterion: `cd web && npm run build`

## Out of Scope
- Modifying backend transpilers or core S-expression language grammar (handled by core engine).
- Modifying `packages/asl-parser` (running concurrently in the self-hosted runtime session).
