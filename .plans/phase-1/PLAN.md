# Phase 1: `asl-web-components-port` Plan

## Objective
Port key showcase UI components from React TSX into pure declarative ASL modules compiled via `vite-plugin-asl`.

## Work Items
1. `Hero.asl`: Top hero banner with headline, token reduction metrics, and primary CTA buttons.
2. `UnifiedPackageMatrix.asl`: Interactive package directory highlighting all official packages (Core, Harness, Visual, Quantum, Arduino).
3. `AslQualityDoctor.asl`: Interactive quality score and AST smell diagnostics visualizer.

## Acceptance Gate
`node asl/bin/asl gate asl/web/asl-src/components/Hero.asl asl/web/asl-src/components/UnifiedPackageMatrix.asl asl/web/asl-src/components/AslQualityDoctor.asl && npm --prefix asl/web run build`
