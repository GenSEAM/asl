# Gap Analysis: Non-ASL Eradication Initiative

**Verdict**: `APPROVE`
**Lenses**: Completeness, Invariants, Anti-Overengineering

---

## 1. Completeness & Edge Cases
- **CDP Protocol Port in Harness**:
  - `harness/src/browser_cdp.asl` must model WebSocket JSON-RPC requests to Chrome DevTools Protocol using standard S-expression records without requiring python websockets.
- **Browser Plugin Manifest Compilation**:
  - `browser-plugin/src/manifest.asn` must compile directly to `dist/manifest.json` on build, while source files remain 100% pure `.asl`.
- **Claims Verification**:
  - `packages/asl-gates/src/site_claims.asl` verifies percentage and latency regex matches against `published_claims.asn`.

---

## 2. Invariants & Wave Execution
- **Wave 0**:
  - Stream A: `satellite-ts-py-purge` (`harness`, `mem`, `agent-bus`, `eddie`, `voice`, `vdom`)
  - Stream B: `browser-plugin-asl-port` (`browser-plugin`)
- **Wave 1**:
  - Stream A: `asl-native-claims-gate` (`asl/packages/asl-gates`)
  - Stream B: `asl-web-views-port` (`asl/web/asl-src`)
