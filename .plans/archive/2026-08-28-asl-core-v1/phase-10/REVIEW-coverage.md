# Lens: COVERAGE

## Verdict: reject

## Blockers

1. **Missing Timeouts Implementation and Testing**
   - **Evidence:** The `WasmRunOptions` interface in §1 lacks a timeout property, and W2 ("Implement test cases covering stdout/stderr capture, proc_exit handling, CLI argv passing, env var reading, and trap recovery") omits timeout testing. The lens explicitly requires checking if timeouts are thoroughly tested.
   - **Fix:** Add a timeout mechanism (e.g. `timeoutMs` in `WasmRunOptions`, and running in a Web Worker if needed) and explicitly test timeout behavior in W2.

2. **No Actual In-Browser Verification**
   - **Evidence:** The scope (§1) calls for "Browser and Node.js environments", but the plan's test suites (W2 via `node --test` and W4 via pytest launching node) exclusively test in Node.js.
   - **Fix:** Modify the plan to include headless browser testing (e.g. Playwright, Puppeteer, or a simple automated HTML runner) to ensure `wasm_runner.js` is truly zero-dependency and does not accidentally rely on Node's `Buffer` or `process`.

3. **W2 Potentially Testing Mocks**
   - **Evidence:** W2 tests edge cases (traps, proc_exit) but does not state where the WASM modules come from. Unlike W4 which uses compiled corpus programs, W2 risks using mocked or hand-crafted WASM, violating the lens requirement.
   - **Fix:** Clarify in W2 that the tests will compile and use real, minimal AgentScript or Rust programs to test trap and exit handling, rather than using mock WASM modules.

## Non-blocking

- None.

## Verified

- Error paths, traps, CLI arguments, and environment variables are included in the W2 testing plan.
- W4 tests real functionality by compiling the existing corpus.

## Unverified

- Exact WASI imports needed by `rustc --target wasm32-wasip1`, as the plan only enumerates a specific subset.
