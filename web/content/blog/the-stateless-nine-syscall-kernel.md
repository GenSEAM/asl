# A Small Host Boundary: What an ASL Program May Ask of Its Host
*Published on September 12, 2026 · 4 min read · By the GenSEAM Team*
*Canonical URL: https://aslang.dev/blog/the-stateless-nine-syscall-kernel*

## 1. Sandboxing Through a Small Surface

A conventional process can make hundreds of system calls, and a sandbox has to decide which ones to deny. ASL starts from the other end: a program reaches its host only through a short, declared list, and a target that lacks an entry rejects the program when it is compiled, not when it runs.

## 2. The Declared Adapter

`tools/platform/platformAdapter.asn` declares the host boundary that cross-platform compilation is meant to target: nine operating-system operations (`fsRead`, `fsWrite`, `fsStat`, `fsWatch`, `procSpawn`, `procWait`, `procSignal`, `netSocket`, `timeMonotonic`) and two memory primitives (`memAllocPage`, `memFreePage`), with targets for macOS, Linux, Windows and WASI. It is a declaration: a test checks that the file exists and names these entries, and the native backends do not yet route every call through it. It also includes a socket operation, so it is not a no-network boundary.

## 3. The Boundary That Is Enforced: wasm32

The smallest boundary that exists in code is the WebAssembly target of `asl-target-llvm`. A program compiled for `wasm32-unknown-unknown` brings its own allocator and garbage collector, and its runtime imports four functions from the host: `asl.write`, `asl.exit`, `asl.nowNs` and `asl.trap`. Memory grows with the module's own `memory.grow`.

The site you are reading is such a program. Listing the imports of `web/dist/site.wasm` (built 2026-10-14) with Node's `WebAssembly.Module.imports` returns exactly those four.

Of the builtins a program can call, only `print` reaches the host on that target. A program that calls the clock builtins (`nowNs`, `monotonicNs`, `sleepMs`), opens a file, starts a process, reads the environment or opens a socket is refused at compile time with `ERR_CAPABILITY_ABSENT`, naming the builtin and the target. There is nothing to deny at run time because nothing else was linked in.

## 4. Effects in the Source

The same idea runs through the language. A function that calls an effectful builtin must say so, as `fn ! name` or a name ending in `!`; otherwise `asl-host check` rejects it with `ERR_EFFECT_UNMARKED` before anything runs. A reader, human or model, can see from a signature whether a call can touch the outside world.

## 5. Deterministic Replay: A Goal

A narrow host interface is what makes record-and-replay practical: if every interaction with the outside world crosses a few named functions, those crossings are the whole trace. `packages/asl-replay` records event streams and reports where a replay's state digests diverge, and its suite passes on the host. Recording every host call of a running program and replaying it identically across machines is the goal, not something we have shown yet.
