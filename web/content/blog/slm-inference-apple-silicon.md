# Small Models on Local Hardware: What AgentScript Offers Them Today
*Published on September 10, 2026 · 4 min read · By the GenSEAM Team*
*Canonical URL: https://aslang.dev/blog/slm-inference-apple-silicon*

## 1. Why Local Small Models

Much agent work is narrow: a structural refactor, a rename, a syntactic transformation. Doing it with a small language model (SLM) on the developer's own machine removes the network round trip and the per-token bill. Apple Silicon machines, with CPU and GPU sharing one pool of memory, are a natural place to try.

We have not benchmarked any model's speed, memory use or accuracy in this repository, so this post quotes none. An earlier version gave tokens-per-second, memory and pass-rate figures with no run behind them; we removed them.

## 2. The Grammar Argument

The design bet is that a small model does better on a language whose structure is carried by delimiters than on one carried by indentation. In ASL every form is a balanced S-expression, so a malformed output is caught by counting brackets, and the set of tokens that may come next is easy to compute.

That second point is what `packages/asl-slm` builds on. It compiles a grammar into an automaton (`compileGrammarToDfa`), tracks the parser state as tokens arrive (`advanceMaskerState`), and computes the set of vocabulary ids allowed at that state (`computeTokenMaskBitset`). Its suites pass on the stage-0 host (`asl-host test`, 2026-10-14: `maskerTest` 114 checks, `slmTest` 35). It is not yet wired into a sampler, so it does not constrain any model's decoding today, and whether it raises a small model's pass rate is unmeasured.

## 3. Reaching a Model

The gateway (`packages/asl-gateway`) can route requests to an Ollama endpoint: the `ollama/` provider prefix, with `OLLAMA_BASE_URL` pointing at a local server. That is the path to a local model today; it is plumbing, not a measured result.

## 4. Native Code on Apple Silicon

The one piece of the toolchain that is specific to Apple Silicon is the native compiler seed: `seed/arm64-apple-darwin` holds the self-hosted compiler `asl1` as LLVM IR, and it is the only triple with a seed so far. Self-hosting is in progress. A local loop that has a small model propose ASL and the native toolchain check and run it is the direction, not something we have measured end to end.
