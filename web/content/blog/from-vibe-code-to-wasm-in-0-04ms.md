# Killing Docker Spin-Up Latency: Why Agent Test Sandboxes Belong in Memory
*By GenSEAM | September 2026*

Autonomous software engineering ("vibe-coding") relies on rapid feedback loops: an agent synthesizes an implementation, executes a test suite, inspects failures, and refines the code.

In practice, this loop hits an infrastructure wall.

Testing agent-generated code requires an isolated sandbox. Today that usually means starting a container or provisioning a remote microVM. When an agent iterates through many repair cycles, the start-up cost of the sandbox, not the test itself, sets the pace of the loop.

The alternative, running agent-generated code directly in a host subprocess, is a security hole. Unconstrained agents can traverse directories, leak API keys, exhaust file descriptors, or open network connections.

AgentScript (ASL) is aiming at a third option: **in-memory WebAssembly sandboxing**, where a test run costs about as much as the computation it performs. This post describes that direction, what exists today, and what we have measured.

---

## 1. The Sandboxing Latency Hierarchy

Why are containers and microVMs too slow for an agent's inner loop?

* **Docker and OCI containers:** Starting a container means talking to a daemon, setting up cgroups and namespaces (`net`, `pid`, `ipc`, `mnt`), and mounting layered filesystems. Warm pools help, but cold start still dominates a short test.
* **MicroVMs (Firecracker):** Lighter than full VMs, but they still initialize virtual CPUs and devices and boot a guest kernel.
* **Process jails (seccomp-BPF):** No hypervisor, but fork-exec costs and syscall filters that are hard to get right.

When an LLM generates a 20-line pure function, paying for a virtual machine to run a few microseconds of computation is the wrong trade.

---

## 2. The Target: In-Memory WebAssembly Sandboxing

The design we are building toward compiles an ASL module to WebAssembly and runs it inside an isolated engine in the agent's own process, with no daemon and no container.

The compiler half exists. `asl-target-llvm`, written in ASL, lowers a linked program to LLVM IR, and for `wasm32-unknown-unknown` it brings its own allocator and garbage collector. The resulting module imports four functions from its host and nothing else: `asl.write`, `asl.exit`, `asl.nowNs` and `asl.trap`. On that target `print` is the only host builtin; a program that reads a file, the environment or a socket fails to compile with `ERR_CAPABILITY_ABSENT` naming the call. This site is built this way: `web/tools/build.asl` compiles `web/site` to `site.wasm`, and a short JavaScript bridge loads it in your browser.

What does not exist yet is the sandbox runner: an engine embedded in the toolbelt that takes a module an agent just wrote, runs its tests under the wasm32 build, and reports back. (The older `asl-target-wat` emitter, which writes WebAssembly Text directly, handles arithmetic only and is not on this path.)

A module an agent might hand to such a sandbox:

```agentscript
(module cipher/rollingHash :x [checksum runTests] :i [])

fn checksum bytes: (List Int64) -> Int64
  (fold (fn [acc b] (mod (+ (* acc 31) b) 4294967296)) 0 bytes)

fn runTests -> Bool
  (do (assert (= (checksum [1 2 3]) 1026) "hash of 1 2 3") true)
```

### Why WebAssembly Is the Right Boundary

The isolation properties below come from the WebAssembly specification, which is why we chose it as the target:

* **Linear memory bounds:** An instance can only address its own linear memory, allocated in 64 KiB pages. An access outside it traps (`out of bounds memory access`), and the host catches the trap without crashing.
* **Capabilities by import:** A WebAssembly module reaches the outside world only through the functions its host chooses to import. ASL's wasm32 build takes four, so the host decides everything the guest can touch.
* **Fuel metering:** Engines such as Wasmtime can count executed instructions and halt an instance when a budget runs out, which bounds runaway loops. We intend to use it; we have not wired it up.

---

## 3. What We Have Measured

We have not benchmarked a WebAssembly sandbox, because the runner does not exist yet, so this post quotes no sandbox latency.

What we can measure is the loop an agent already uses: checking and running a test on the stage-0 host, a native C program with no container. We ran `asl/host/out/asl-host test` on the module above 50 times on 2026-10-14, on a 4-core Linux cloud VM (Intel Xeon, 2.8 GHz), timing the whole process from Python's `subprocess.run`: median 11.9 ms, minimum 10.5 ms, maximum 28.5 ms. That covers loading the prelude, reading, name resolution and the test itself. It has no sandbox, which is the gap the wasm32 target is meant to close without giving back the speed.

---

## 4. Cross-Compilation Without Semantic Drift

A sandbox is only useful if the code verified inside it behaves the same where it is deployed.

Testing in one environment and deploying to another creates environment drift: code that passes in a Python sandbox can behave differently in a Go or TypeScript service.

The direction AgentScript takes is a single source with several lowerings. The repository holds target packages for C, Go, LLVM, Python, Rust, shell, Swift, TypeScript and WebAssembly Text (`asl/packages/asl-target-*`). Only `asl-target-llvm` compiles real multi-module programs today, natively and to wasm32; the source-to-source targets are prototypes.

1. **Verify once:** The agent iterates until the unit tests pass.
2. **Lower to the target:** The same syntax tree is emitted for each target.
3. **Check for drift:** Sharing a source does not by itself guarantee equal behaviour; numeric semantics, integer overflow and string encoding differ between targets. The guarantee has to come from a differential gate that runs the same tests on every target and compares results. That gate is part of the plan, not something we ship today.

### Conclusion

Autonomous agents should not wait on virtualization to run a 20-line function. WebAssembly's memory isolation and import-based capabilities make an in-memory sandbox possible. The compiler to wasm32 exists and runs this site; the embedded runner, fuel metering and differential gate are the work ahead.
