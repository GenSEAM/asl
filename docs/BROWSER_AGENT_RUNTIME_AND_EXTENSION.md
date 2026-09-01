# In-Browser Agent Runtime, Hot-Reload Sandbox & Companion Extension (ASL v1.0)

## 1. Architecture Overview

The ASL in-browser ecosystem unites three operational planes:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       ASL Browser Extension Companion                       │
│  - Live DOM & visual context capture (Accessibility Tree, bounding boxes)   │
│  - Click, type, automate in-situ QA workflows                               │
│  - IPC bridge to local `asl daemon` and in-browser WASI worker              │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
            ┌──────────────────────────┴──────────────────────────┐
            ▼                                                     ▼
┌──────────────────────────────────────┐  ┌──────────────────────────────────┐
│   In-Browser Sandbox (Web Worker)    │  │  Local Dev Daemon (asl serve)    │
│  - Pure TS/WASI Runner in memory     │  │  - Native disk access            │
│  - In-memory HMR & hot-reload loops  │  │  - Git repo synchronization      │
│  - OPFS / File System Access API     │  │  - SSE / WebSocket wire bus      │
│  - In-browser isomorphic-git         │  │  - Multi-agent compiler daemon   │
└──────────────────────────────────────┘  └──────────────────────────────────┘
```

---

## 2. In-Browser Hot-Reloading Sandbox (`@genseam/in-browser-dev`)

### WebAssembly Web Worker Pipeline
1. **Code Modification**: User or Agent emits `.agentscript` S-expression.
2. **Instant In-Memory Transpilation & Checking**: Run typechecker in `<0.015ms`.
3. **WASI Web Worker Isolate**:
   - Compiles to `wasm32-wasip1` in memory.
   - Memory buffers stream `stdout`, `stderr`, and DOM mutation events without page reload.
4. **Hot State Preservation**: State snapshots preserved across code swaps.

---

## 3. Hybrid Storage & Git Strategy

| Mode | Target | Mechanism |
|---|---|---|
| **Zero-Install (Browser Standalone)** | Browser Sandbox | File System Access API (`showDirectoryPicker`) + OPFS + In-browser Wasm Git (`isomorphic-git`) |
| **Local Workspace (Developer Machine)** | Real File System | `asl serve` daemon over `ws://127.0.0.1:8765` + direct Git CLI bindings |
| **Extension Bridge (In-Situ Web Assistant)** | Active Web Page | Chrome Extension Manifest v3 + Content Script DOM observer + Native Messaging Host |

---

## 4. ASL Browser Companion Extension Specification

* **Visual & Structural Context Extraction**:
  - Extracts compressed semantic trees (`data-agent-*`, ARIA roles, clean Markdown DOM) with `-85%` token reduction.
* **Autonomous In-Situ Actions**:
  - Real-time DOM interaction (click, scroll, type, assert visually).
* **Direct Agent Socket Integration**:
  - Connects to `@genseam/agent-bus` on `localhost:8765/events` for real-time human-agent pair programming.
