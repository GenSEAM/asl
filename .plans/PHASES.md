# Non-ASL Eradication Initiative — PHASES

## Overview
Eliminate remaining TypeScript and Python files across satellite repositories and the web showcase, porting host bridges, perception logic, browser plugin sources, and verification gates to pure AgentScript.

## Phases DAG

```mermaid
graph TD
    subgraph Wave 0 [Wave 0: Satellite Repos & Browser Plugin ASL Port]
        P1[Phase 1: satellite-ts-py-purge]
        P2[Phase 2: browser-plugin-asl-port]
    end
    subgraph Wave 1 [Wave 1: Native Verification Gates & Web Views Port]
        P3[Phase 3: asl-native-claims-gate]
        P4[Phase 4: asl-web-views-port]
    end
    P1 --> P3
    P2 --> P4
```

| Phase ID | Owns | Depends On | Priority | Gate Command | Status |
|---|---|---|---|---|---|
| `satellite-ts-py-purge` | `harness/`, `mem/`, `agent-bus/`, `eddie/`, `voice/`, `vdom/` | `[]` | `P0` | `node asl/bin/asl gate harness/src/browser_cdp.asl mem/src/driver.asl vdom/src/perception.asl` | `done` |
| `browser-plugin-asl-port` | `browser-plugin/src/*.asl` | `[]` | `P0` | `node asl/bin/asl gate browser-plugin/src/background.asl browser-plugin/src/content.asl` | `done` |
| `asl-native-claims-gate` | `packages/asl-gates/src/site_claims.asl` | `[satellite-ts-py-purge]` | `P1` | `node bin/asl gate packages/asl-gates/src/site_claims.asl` | `done` |
| `asl-web-views-port` | `web/asl-src/ArchitectureView.asl`, `web/asl-src/EcosystemView.asl` | `[browser-plugin-asl-port]` | `P1` | `node bin/asl gate web/asl-src/ArchitectureView.asl web/asl-src/EcosystemView.asl` | `done` |
