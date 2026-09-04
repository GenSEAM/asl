# @genseam/asl-harness

Universal Autonomous Agent Harness with Anti-Hallucination Epistemic Grounding Firewall and sub-millisecond in-memory Wasm execution.

## Adapters
- `CodeEngineAdapter`: AST synthesis and in-memory WebAssembly verification.
- `BrowserAdapter`: Headless browser viewport and DOM tree extraction.
- `ComputerUseAdapter`: Desktop OS execution and signed build receipts.
- `ChatRAGAdapter`: Vector similarity memory recall and prompt compression.
- `MetasearchAdapter`: Decentralized multi-engine search aggregation.

## Anti-Hallucination Grounding Firewall
- **Verbatim Quote Verification**: Validates claims strictly against exact quotes from retrieved documents (`asl-context`).
- **Namespace-Isolated Prompt Caching**: Enforces strict boundaries between agent sessions to eliminate prompt bleed.
- **Action Firewall**: Blocks ungrounded actions before side effects can take place.
