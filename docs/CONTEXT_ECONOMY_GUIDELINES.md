# AgentScript Context Economy & Intent Separation Guidelines

> **The Golden Rule**: Code carries the **HOW** and the **WHAT**. Never write comments explaining what the code already says. Document only the **WHY**, the **MOTIVATION**, and the **ARCHITECTURAL INVARIANTS** — and store them out-of-band to keep code 100% compact algorithms.

---

## 1. Separation of Code and Intent

### The Problem in Legacy Codebases
Human developers often write comments describing literal actions:
```python
# Loop through the orders and add up total prices
total = 0
for order in orders:
    total += order.price  # add order price
```
For an AI agent reading this file, these comments are **100% pure token waste**. The code already says what it does. Reading 5,000 lines of such comments burns context windows, causes attention dilution, and triggers comment-rot when code changes.

### The AgentScript Standard
1. **Zero Explanatory Comments in Code**: The code is self-sufficient. Variable and function names are crisp.
2. **Document Only the Motivation (The "WHY")**:
   - Why was this algorithm chosen over another?
   - What edge case or race condition is this protecting against?
   - What architectural requirement (ADR) mandated this decision?
3. **Store Intent Out-of-Band via Semantic Tags**:
   ```lisp
   (defun calculate-hash ((payload Bytes) (nonce U64)) Bytes
     (@tag :arch "d-sec-02" :why "resist timing-attacks via constant-time primitive")
     (crypto/blake3 payload nonce))
   ```
   If an agent understands the logic, it reads only the compact code. If it needs the rationale or motivation, it queries the reference:
   ```bash
   asl meta get d-sec-02
   # or by symbol:
   asl meta get calculate-hash
   ```

---

## 2. Predictable BPE Identifier Compaction

Language models process code through Byte-Pair Encoding (BPE) tokenizers (e.g., tiktoken, SentencePiece). By following standard, universal abbreviations, agents reduce token footprint by **35% to 50%** while preserving 100% cognitive clarity for any reasoning model:

| Full English Word | Recommended Compact Identifier | BPE Token Count |
|---|---|---|
| `default` | `:dflt` | 1 token |
| `config` / `configuration` | `:cfg` | 1 token |
| `context` | `:ctx` | 1 token |
| `request` | `:req` | 1 token |
| `response` | `:res` or `:resp` | 1 token |
| `argument` / `parameter` | `:arg` / `:param` | 1 token |
| `message` | `:msg` | 1 token |
| `error` | `:err` | 1 token |
| `function` | `:fn` | 1 token |
| `length` | `:len` | 1 token |
| `index` | `:idx` | 1 token |
| `authentication` | `:auth` | 1 token |
| `timeout_ms` | `:t-out` or positional | 1 token |

**Rule of Thumb**: Drop vowels from common technical nouns (`dflt`, `msg`, `auth`, `cfg`), or use standard single-letter keys for core schemas (`:f` for field, `:c` for case, `:d` for doc).

---

## 3. Positional Frames vs Key-Value Noise

In hot execution paths, passing repetitive schema keys consumes up to 70% of payload tokens.

### Bad (Chatty Key-Value Noise — 68 Tokens):
```json
{
  "action": "execute_command",
  "command": "git",
  "arguments": ["status", "--porcelain"],
  "timeout_milliseconds": 5000,
  "working_directory": "/workspace"
}
```

### Good (Positional AgentScript Wire Frame — 14 Tokens):
```lisp
(! cmd "git" ["status" "--porcelain"] 5000 "/workspace")
```
Both machines already know the parameter order from the formal signature `(defun cmd ((bin Str) (args (List Str)) (timeout-ms U64) (cwd Str)) ...)`. Repeating parameter names is redundant.

---

## 4. Context Offloading via Handles (`@offload`)

When an agent executes an operation that yields a massive output (e.g. 50KB of raw web scraping, test logs, or large database query results), **NEVER dump the entire raw output into the conversational prompt window**.

### The Offloading Protocol
1. The execution tool/companion stores the full blob in local memory, disk, or temporary KV store (`.asl/offload/<id>.bin`).
2. The tool returns a compact **Offload Pointer**:
   ```lisp
   (! data/offload
     :id "scrape-9481"
     :summary "Extracted 42 product items. Status: 200 OK. Zero parsing errors."
     :size-bytes 54200
     :sample [(:sku "A1" :price 24.50) (:sku "A2" :price 12.00)])
   ```
3. The reasoning agent reads the 3-line summary. If and only if it needs a specific slice, it queries:
   ```lisp
   (? data/slice :id "scrape-9481" :offset 10 :limit 5)
   ```
This prevents conversational context exhaustion and keeps the agent's attention sharp.

---

## 5. Summary Reference Workflow

```
[Pure Code: Pure HOW & WHAT]
       │
       ├──> (@tag :arch "d-4a1b" :doc "fn-calc")
       │
       └──> Question: "Why does this exist? What was the motivation?"
                   │
                   ▼
       [Out-of-Band Knowledge Matrix: asl meta get d-4a1b]
       - Motivation: Prevent memory leak under high-concurrency SSE stream
       - Architectural Decision: Approved in ADR-4a1b
       - Invariants: Must release buffer within 50ms
```
