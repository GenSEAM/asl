# @genseam/asl-pack

**Universal Cross-Platform Packager, WebAssembly Runtime Matrix & Standalone Distribution Toolchain for AgentScript.**

---

## 1. Overview & Mission

`@genseam/asl-pack` packages AgentScript applications and compiler toolchains into self-contained, standalone single-binary executables without requiring pre-installed Node.js, Python, or runtime dependencies on the target host.

It establishes a deterministic **WebAssembly Runtime Decision Matrix** providing platform-optimal compilation and execution policies across desktop, mobile, server, and embedded targets.

---

## 2. WebAssembly Runtime Decision Matrix

| Target Environment | Recommended Runtime Engine | Execution Mode | SIMD-128 | Cold Start | Binary Footprint | Apple App Store Compliant |
|---|---|---|---|---|---|---|
| **CLI / Developer Tools** | `Wasmtime (Cranelift)` | `JIT` | Yes | ~1.5 ms | ~12 MB | No |
| **Server / Cloud MicroVM** | `Wasmtime (Cranelift)` | `JIT` | Yes | ~1.5 ms | ~12 MB | No |
| **iOS Native Applications** | `LLVM / Cranelift AOT` | `AOT` | Yes | ~0.001 ms | ~1.5 MB | **Yes (Strict No-JIT)** |
| **iOS Low-Memory Sandbox** | `Wasm3` | `Interpreted` | No | ~0.05 ms | **~150 KB** | **Yes (Strict No-JIT)** |
| **Android Mobile Apps** | `WAMR (Intel Micro Runtime)` | `AOT` | Yes | ~0.2 ms | < 1.0 MB | Yes |
| **Web Browser / Extensions** | `Browser Native Engine` | `JIT` | Yes | ~0.01 ms | 0.0 MB | Yes |
| **Embedded / IoT (<1MB RAM)**| `Wasm3` / `WAMR` | `Interpreted` | No | ~0.05 ms | ~150 KB | Yes |

---

## 3. Platform Target Triples

- **Apple macOS (Apple Silicon)**: `aarch64-apple-darwin` (mach-o, `.dylib`)
- **Apple macOS (Intel)**: `x86_64-apple-darwin` (mach-o, `.dylib`)
- **Linux (x64)**: `x86_64-unknown-linux-gnu` (elf, `.so`)
- **Linux (ARM64)**: `aarch64-unknown-linux-gnu` (elf, `.so`)
- **Microsoft Windows**: `x86_64-pc-windows-msvc` (pe/coff, `.exe`, `.dll`)

---

## 4. Verification

```bash
node --test tests/runtime.test.js
```
