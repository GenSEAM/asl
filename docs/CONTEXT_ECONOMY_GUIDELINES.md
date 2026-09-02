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

## 2. The Single-Token Hygiene Standard (Однотокеновая гигиена)

### The Core Law
Every LLM interacts with code through Byte-Pair Encoding (BPE) tokens. When an agent emits verbose identifiers like `default_timeout_milliseconds`, the model must sample **7 separate BPE tokens**. In agent swarms exchanging millions of frames per day, this causes:
1. **7x higher LLM generation latency** (tokens are generated sequentially).
2. **7x higher token expenditure**.
3. **Severe context fragmentation and attention decay**.

**The Standard**: Every syntax keyword, record key, protocol verb, and common technical descriptor **MUST resolve to exactly 1 BPE token** wherever practically possible.

---

### The Canonical 1-Token Dictionary

Use these standard abbreviations universally across all AgentScript schemas, DTOs, and protocol frames:

| Full Word | BPE Tokens (Old) | 1-Token Standard | BPE Tokens (New) | Semantic Meaning |
|---|---|---|---|---|
| `default` | 1–2 tokens | **`:dflt`** | **1 token** | Default fallback value |
| `config` / `configuration` | 2–3 tokens | **`:cfg`** | **1 token** | Configuration object |
| `context` | 2 tokens | **`:ctx`** | **1 token** | Execution context |
| `request` | 1–2 tokens | **`:req`** | **1 token** | Inbound request frame |
| `response` | 2 tokens | **`:resp`** or **`:res`** | **1 token** | Outbound response |
| `argument` / `parameter` | 2–3 tokens | **`:arg`** or **`:param`** | **1 token** | Function argument |
| `message` | 2 tokens | **`:msg`** | **1 token** | Message payload |
| `error` | 1–2 tokens | **`:err`** | **1 token** | Error descriptor |
| `function` | 1–2 tokens | **`:fn`** | **1 token** | Function reference |
| `length` | 2 tokens | **`:len`** | **1 token** | Array or string length |
| `index` | 2 tokens | **`:idx`** | **1 token** | Sequential index |
| `authentication` | 3–4 tokens | **`:auth`** | **1 token** | Auth credentials / token |
| `timestamp` | 2 tokens | **`:ts`** | **1 token** | Epoch millisecond mark |
| `payload` | 2 tokens | **`:data`** or **`:body`** | **1 token** | Payload body |

#### For Ultra-Dense Hot Schemas (Single-Letter Keys):
When defining low-level AST nodes or high-frequency records:
- **`:f`** = field
- **`:c`** = case / constructor
- **`:d`** = documentation / description
- **`:v`** = value
- **`:k`** = key
- **`:t`** = type
- **`:p`** = parameter

---

### Boundaries: When Single-Token Hygiene is Mandatory vs Exceptions

#### 1. MANDATORY: Protocols, Schemas, and Internal Tool Calls
Single-token hygiene is strictly enforced for:
- All ASN record keys (`(:id "..." :dflt true :auth :bearer)`).
- All A2A wire frame queries and commands (`(? auth/probe :ctx ...)`, `(! exec/ack :res ...)`).
- All internal helper functions and loop counters.

#### 2. EXCEPTIONS: Where Single-Token Hygiene Does NOT Apply
Do NOT forcibly mangle identifiers in these three specific situations:
1. **High-Level Domain Business Entities**:
   - Example: `OrganizationMembershipInvite`, `HealthcarePatientRecord`.
   - *Rationale*: Aggressively dropping vowels into `OrgMmbrshpInvt` destroys LLM semantic reasoning and triggers hallucination in domain logic. Clarity takes precedence over token compression for top-level business domain models.
2. **Literal String Values & External Identifiers**:
   - Example: UUIDs (`"9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"`), ISO timestamps, user-supplied text strings, error messages for humans.
   - *Rationale*: Data payloads must reflect real-world values verbatim.
3. **Foreign Host Language Interoperability (FFI)**:
   - Example: Calling JavaScript `window.requestAnimationFrame()` or Python `torch.nn.functional.cross_entropy()`.
   - *Rationale*: External runtime APIs must match foreign symbol names exactly to avoid runtime linkage errors.

---

### Concrete Before & After Comparisons

#### Example A: Wire Protocol Frame
```lisp
;; ❌ BAD: 42 BPE Tokens (Verbose legacy style)
(? authentication_service/validate_token 
   :authentication_bearer_token "jwt.xyz" 
   :client_configuration_context {:timeout_milliseconds 5000 :default_retry true})

;; ✅ GOOD: 14 BPE Tokens (Single-Token Hygiene enforced)
(? auth/validate 
   :auth "jwt.xyz" 
   :cfg {:t-out 5000 :dflt true})
```
*Savings: 67% fewer tokens, 3x faster generation latency, 100% equivalent semantic execution.*

#### Example B: Data Type Schema Definition
```lisp
;; ❌ BAD: 38 BPE Tokens
(defschema UserProfile
  (:field user_identifier Str)
  (:field configuration_parameters (Map Str Str))
  (:field default_role Str))

;; ✅ GOOD: 18 BPE Tokens
(dfs UserProfile
  (:f id Str)
  (:f cfg (Map Str Str))
  (:f dflt-role Str))
```
*Savings: 53% fewer tokens.*

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
