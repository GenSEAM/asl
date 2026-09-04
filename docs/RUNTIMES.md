# ASL Universal Runtime & Ecosystem Compatibility Matrix

### Cross-Platform WebAssembly, JavaScript Engines, and Python Accelerators

> **Unverified figures.** Every performance number on this page is a projection or a
> vendor claim, not a measurement this repository can reproduce. `DESIGN.md` §5 requires a
> published number to be traceable to a gate; these are not, and are kept only as an order
> of magnitude to design against. `ROADMAP.md` §2 lists the figures that do have a gate,
> and `bench/token_frames.py` is the shape a claim has to take to earn a place here.

> **"Write once in ASL. Execute seamlessly across Browser, Node, Bun, Deno, Edge Workers, and WebAssembly (wasm32-wasip1)."**

---

## 1. WebAssembly Runtimes & Mobile Strategy

Running native code on mobile devices (especially iOS) is strictly constrained by App Store policies:
* **The iOS Challenge:** Apple forbids dynamic JIT compilation (`mprotect` / executable memory allocations) for non-Apple web engines. Native JIT compilers get rejected from the App Store.
* **The ASL Solution:** ASL compiles to standard `wasm32-wasip1` binaries that run through lightweight, certified **WebAssembly interpreters**.

### WebAssembly Engine Tier List:

| Engine | Tier | Primary Use Case | iOS App Store Compliant? | Memory Footprint |
| :--- | :--- | :--- | :--- | :--- |
| **Wasm3** | **Mobile #1 (Interpreter)** | iOS, Android, Embedded C, Microcontrollers | **100% Compliant (Pure C Interpreter, No JIT)** | **< 64 KB** |
| **Browser Native (V8 / JSC / Gecko)** | **Web #1 (Client-Side)** | React, Vue, Svelte, Angular, Canvas, Web Workers | **100% Native** | **0 KB (Built into OS)** |
| **Wasmtime (Bytecode Alliance)** | **Server #1 (WASI Host)** | Cloud edge workers, Fastly Compute, Docker Wasm | Server / Edge only | ~12 MB |
| **Wasmer** | **Universal Plugin VM** | Desktop extensions, Figma/Notion-like plugin hosts | Desktop / Server | ~15 MB |

---

## 2. JavaScript & TypeScript Runtime Matrix

ASL emits pure, zero-dependency ES Modules (`.ts` / `.mjs`) with standard type definitions that work out of the box with all modern bundlers and runtimes:

```
                          ┌────────────────────────┐
                          │   ASL Core (.asl)      │
                          └───────────┬────────────┘
                                      │
        ┌─────────────────────────────┼─────────────────────────────┐
        ▼                             ▼                             ▼
   Node.js (v18+)                   Bun (v1.1+)                  Deno (v2.0+)
  (npm / pnpm / yarn)             (Ultra-fast ESM)            (Native TS / Web APIs)
```

* **Bundler Compatibility:**
  * **Vite & Rollup:** Direct tree-shaking via ES6 named exports (`import { renderBadge } from './generated/ui'`).
  * **esbuild & Webpack 5:** Full dead-code elimination (DCE) — unused schemas and functions are stripped automatically.

---

## 3. Python Reference Runtime

ASL provides a reference lowering into standard PEP 484 type-annotated Python for differential verification and host interop:

| Python Runtime | Compatibility | How ASL Integrates | Execution Role |
| :--- | :--- | :--- | :--- |
| **CPython (3.10 – 3.13)** | **100% Native** | Emits clean PEP 484 type-annotated standard Python | Reference verification baseline |
| **PyPy (JIT)** | **100% Compatible** | Fast JIT compilation of reference AST execution | High-speed alternative Python runner |

---

## 4. The Unified Pipeline: WebAssembly, TypeScript, and Edge

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           THE ASL GLUE ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. Frontend (React / Svelte):   Consumes Wasm binary in-memory (<0.04ms)   │
│ 2. Mobile App (iOS / Android):  Runs Wasm3/WASI interpreter (App Store safe)│
│ 3. Edge / Cloud Services:       Executes wasm32-wasip1 on Cloudflare / Deno │
│ 4. Node / Bun Host Runtimes:    Direct zero-dependency TypeScript modules   │
│                                                                             │
│ ──> ZERO Protobuf/gRPC serialization drift across your entire tech stack    │
└─────────────────────────────────────────────────────────────────────────────┘
```
