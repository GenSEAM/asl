# @genseam/asl-toolcall

ASL S-Expression tool calling protocol, schema compressor, and zero-JSON dispatcher.

## Why ASL Tool Calling?

Standard LLM tool calling forces large JSON Schema definitions into system prompts and emits verbose JSON arguments `{"tool": "search", "parameters": {"query": "...", "limit": 5}}`. For agentic loops, this wastes 70–80% of tokens purely on JSON braces, quotes, and duplicated schema overhead.

`asl-toolcall` replaces JSON tool calls with native AgentScript S-expressions:

### JSON Tool Call (68 tokens)
```json
{
  "name": "search_ecosystems",
  "arguments": {
    "query": "cryptography",
    "ecosystem": "crates",
    "limit": 10
  }
}
```

### ASL S-Expression Tool Call (16 tokens, -76.5%)
```lisp
(call :tool search-ecosystems :query "cryptography" :ecosystem "crates" :limit 10)
```

## Features
- **Dense Tool Definitions**: Compact function signatures `(def-tool search :d "Web search" [:q Str :limit I64])`.
- **Zero-JSON Parser**: Tokenizes and validates ASL S-expressions directly in pure ASL.
- **Strict Validation**: Checks required arguments against declared parameter specifications.
- **Uniform Result Framing**: Standardized compact execution envelopes `(result :tool name :ok true :out "...")`.
