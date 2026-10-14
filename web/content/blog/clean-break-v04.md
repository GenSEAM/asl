# Clean Break v0.4: One C Host, Everything Else in ASL
*Published on September 12, 2026 · 4 min read · By the GenSEAM Team*
*Canonical URL: https://aslang.dev/blog/clean-break-v04*

## 1. The Clean Break Goal

Projects that let a new language coexist indefinitely with the scripts that bootstrapped it tend to drift: the wrapper becomes the real implementation, and the language becomes a front end to it. The v0.4 line set the opposite goal for AgentScript: the compiler, the standard library and the agent tooling are written in ASL, and the only foreign code on the critical path is a small C host that reads, checks and runs it.

That is a direction, not a finished state. This post says how far it has got, measured on the repository as it is today.

## 2. What the Tree Holds

Counted with `git ls-files` on the current tree:

- `packages/` tracks 1,602 `.asl` files and no `.py`, `.js` or `.ts` files. Its only foreign files are two `.sh` test fixtures.
- Outside `packages/`, the remaining foreign files are build and delivery glue: `host/build.sh`, `web/build.sh`, the installer `web/public/install.sh`, and `web/bridge/boot.js`, the small script that loads `site.wasm` in the browser and applies the DOM operations it prints.

Retiring code that is not ASL is ongoing work, tracked by the foreign-code audit in the repository rather than declared done.

## 3. The C Host

The stage-0 host, `host/out/asl-host`, is 33 C source and header files (about 10,200 lines by `wc -l`), built by `host/build.sh` with `-std=c11 -Wall -Wextra -Werror`. It parses ASL and checks names, arity, enum exhaustiveness and effect markers (`ERR_EFFECT_UNMARKED`) before running anything:

```bash
asl/host/out/asl-host eval '(+ 1 2)'
asl/host/out/asl-host check FILE
asl/host/out/asl-host test FILE
asl/host/out/asl-host run FILE
```

It is the reference engine: when a document and `asl-host` disagree, `asl-host` wins.

## 4. Self-Hosting, in Progress

The native compiler `asl1` is itself an ASL program (`packages/asl-compiler/src/asl1.asl`). Its whole-program LLVM IR is checked in as a seed under `seed/`, today for `arm64-apple-darwin` only, and the seed is regenerated when the stage-2 and stage-3 outputs of the compiler stop matching. Other triples, and a build that needs no C host at all, are still ahead.

The same LLVM lowering (`asl-target-llvm`) already produces real artifacts: aslang.dev is an ASL program compiled to `wasm32-unknown-unknown`, with its own allocator and garbage collector, importing only `asl.write`, `asl.exit`, `asl.nowNs` and `asl.trap` from the page.
