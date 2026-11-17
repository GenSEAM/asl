# Constrained Decoding for Small Local Models: How ASL Keeps 3B Agents on the Rails
*Published on September 10, 2026 · 4 min read · By the GenSEAM Team*
*Canonical URL: https://aslang.dev/blog/slm-inference-apple-silicon*

## 1. Giving Small Local Models a Grammar Guardrail

Much of the work in an agent-built codebase is narrow and mechanical: renaming a symbol across modules, extracting a helper, or rewriting a call site from a checker receipt. Running those steps on a small language model (SLM) on local Apple Silicon hardware—where CPU and GPU share unified memory—avoids network round trips and API bills, provided the model's output parses on the first try.

AgentSlang (ASL) helps small models succeed by keeping the grammar regular—every form is a prefix S-expression—and by pairing the language with `packages/asl-slm`, a token-masking state machine that restricts decoding to tokens that keep delimiters balanced and head keywords valid. (We have not yet run speed, memory or accuracy benchmarks for local models in this repository, so this post covers the implemented masker and checker mechanics rather than throughput numbers.)

## 2. The Grammar Argument

The design bet is that a small model does better on a language whose structure is carried by delimiters than on one carried by indentation. In ASL every form is a balanced S-expression, so a malformed output is caught by counting brackets, and the set of tokens that may come next is easy to compute.

That second point is what `packages/asl-slm` builds on. It compiles a grammar into an automaton (`compileGrammarToDfa`), tracks the parser state as tokens arrive (`advanceMaskerState`), and computes the set of vocabulary ids allowed at that state (`computeTokenMaskBitset`). Its suites pass (`asl test`, 2026-10-14: `maskerTest` 114 checks, `slmTest` 35). It is not yet wired into a sampler, so it does not constrain any model's decoding today, and whether it raises a small model's pass rate is unmeasured.

## 3. Reaching a Model

The gateway (`packages/asl-gateway`) can route requests to an Ollama endpoint: the `ollama/` provider prefix, with `OLLAMA_BASE_URL` pointing at a local server. That is the path to a local model today; it is plumbing, not a measured result.

## 4. Native Code on Apple Silicon

The one piece of the toolchain that is specific to Apple Silicon is the native compiler: the compiler, written in ASL, is bootstrapped from an LLVM IR seed for `arm64-apple-darwin`, the only triple with a seed so far, and the self-compile is gated on macOS only. A local loop that has a small model propose ASL and the native toolchain check and run it is the direction, not something we have measured end to end.
