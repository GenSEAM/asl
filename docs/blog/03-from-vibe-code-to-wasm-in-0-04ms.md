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

The design we are building toward compiles an ASL module to WebAssembly in memory and runs it inside an isolated engine in the same process, with no temporary files and no daemon.

What exists today is the first stage of that pipeline: the `asl-target-wat` package, written in ASL, emits WebAssembly Text for functions, arithmetic, control flow and WASI imports (`fd_write`, `proc_exit`, `clock_time_get`). Its test suite passes on the stage-0 host (`asl-host test asl/packages/asl-target-wat/tests/emitWatTest.asl`: 119 assertions and 48 refutations executed, 167 passed, on 2026-09-24). Binary emission, an embedded engine and fuel metering are not built yet.

A module an agent might hand to such a sandbox:

```agentscript
(module cipher/rollingHash :d "Polynomial rolling hash over a byte list." :x [checksum runTests] :i [])

fn checksum bytes: (List Int64) -> Int64
  :d "Fold each byte into a base-31 hash, reduced modulo 2^32."
  (fold (fn [acc b] (mod (+ (* acc 31) b) 4294967296)) 0 bytes)

fn runTests -> Bool
  (do (assert (= (checksum [1 2 3]) 1026) "hash of 1 2 3") true)
```

### Why WebAssembly Is the Right Boundary

The isolation properties below come from the WebAssembly and WASI specifications, which is why we chose them as the target:

* **Linear memory bounds:** An instance can only address its own linear memory, allocated in 64 KiB pages. An access outside it traps (`out of bounds memory access`), and the host catches the trap without crashing.
* **Capabilities by import:** Under `wasm32-wasip1`, system calls such as `fd_read` and `fd_write` are imported host functions, not kernel interrupts. A host that provides an empty import table gives the guest no way to touch files, sockets or clocks.
* **Fuel metering:** Engines such as Wasmtime can count executed instructions and halt an instance when a budget runs out, which bounds runaway loops. We intend to use it; we have not wired it up.

---

## 3. What We Have Measured

We have not benchmarked a WebAssembly sandbox, because the embedded engine does not exist yet, so this post quotes no sandbox latency.

What we can measure today is the loop an agent already uses: checking and running a test on the stage-0 host, a native C program with no container. Running `asl-host test` on the module above 50 times on an Apple M1 Pro on 2026-09-24 took a median of 3.91 ms per run (min 3.43 ms, max 8.53 ms), measured as wall time of the whole process, including reading, name resolution and the test itself. That run has no sandbox, which is exactly the gap the WebAssembly target is meant to close without giving back the speed.

---

## 4. Cross-Compilation Without Semantic Drift

A sandbox is only useful if the code verified inside it behaves the same where it is deployed.

Testing in one environment and deploying to another creates environment drift: code that passes in a Python sandbox can behave differently in a Go or TypeScript service.

The direction AgentScript takes is a single source with several lowerings. The repository holds target packages for C, Go, LLVM, Python, Rust, shell, Swift and WebAssembly Text (`asl/packages/asl-target-*`), at different levels of completeness; `asl build` itself still returns `ERR_UNIMPLEMENTED`.

1. **Verify once:** The agent iterates until the unit tests pass.
2. **Lower to the target:** The same syntax tree is emitted for each target.
3. **Check for drift:** Sharing a source does not by itself guarantee equal behaviour; numeric semantics, integer overflow and string encoding differ between targets. The guarantee has to come from a differential gate that runs the same tests on every target and compares results. That gate is part of the plan, not something we ship today.

### Conclusion

Autonomous agents should not wait on virtualization to run a 20-line function. WebAssembly's memory isolation and import-based capabilities make an in-memory sandbox possible; the WAT emitter is the first piece, and the engine, fuel metering and differential gate are the work ahead.
