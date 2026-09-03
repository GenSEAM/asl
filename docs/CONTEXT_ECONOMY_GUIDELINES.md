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
;; ❌ BAD: 44 BPE Tokens (Verbose legacy naming)
(defschema UserProfile
  (:field user_identifier String "Unique ID of user")
  (:field configuration_parameters (Map String String) "Key-value config")
  (:field default_role String "Fallback role"))

;; ✅ GOOD: 24 BPE Tokens (Single-Token Hygiene enforced)
(dfs UserProfile
  (:f id String "ID")
  (:f cfg (Map String String) "Config")
  (:f dflt-role String "Role"))
```
*Savings: 45% fewer tokens in code while remaining 100% valid under the v0.2 parser!*

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

## 4. Array & Tabular Object Deduplication in ASN

### The Disaster of Arrays of Objects in JSON
In JSON, an array of objects repeats every field name on **every single item**:
```json
[
  {"id": 1, "sku": "SSD-1TB", "price": 89.99, "status": "in_stock"},
  {"id": 2, "sku": "RAM-32GB", "price": 129.50, "status": "in_stock"},
  {"id": 3, "sku": "GPU-4070", "price": 549.00, "status": "low_stock"}
]
```
If you return 100 database records with 6 fields each, JSON transmits **600 duplicated keys, 600 colons, 600 commas, and 100 curly brace pairs**. For 1,000 rows, this consumes **15,000 to 25,000 pure boilerplate tokens**!

### The ASN Solution: Schema Constructor Grouping & Key-Row Pairs

To stay 100% compliant with Single-Token Hygiene, ASN does NOT introduce multi-token keywords like `@table` or `@with` (which split into `@` + `word`). Instead, ASN re-uses **existing native structures** and **standard S-expression pairs**:

#### 1. Pre-Declared Schema Re-Use: `(Schema [rows...])`
When a structure is declared in the schema:
```lisp
(dfs Item
  (:f id Int64 "ID")
  (:f sku String "SKU")
  (:f price Float64 "Price")
  (:f status String "Status"))
```
An array of records simply re-uses the schema constructor as the group head:
```lisp
;; ✅ Native Schema Grouping: Constructor declared ONCE, rows are zero-key positional vectors
(Item
  [1 "SSD-1TB" 89.99 :in-stock]
  [2 "RAM-32GB" 129.50 :in-stock]
  [3 "GPU-4070" 549.00 :low-stock])
```
*Token count:* `Item` is **1 token**. Each row has **0 keys**. Zero token bloat.

#### 2. Ad-Hoc Dynamic Tables: `([keys...] [[rows...]])`
When data is dynamic (e.g. ad-hoc SQL query results without a pre-compiled schema), ASN uses a standard 2-vector tuple `(Keys Rows)` without any extra keywords:
```lisp
;; ✅ Pure Ad-Hoc Table: ([keys] [[rows]]) — Zero special keywords!
([:id :sku :price :status]
 [[1 "SSD-1TB" 89.99 :in-stock]
  [2 "RAM-32GB" 129.50 :in-stock]
  [3 "GPU-4070" 549.00 :low-stock]])
```

### Factoring Out Common Invariants (Shared Field Envelopes)
Instead of inventing an external `@with` form, common invariant fields are placed directly in the parent record, with the positional items in a `:data` vector:

```lisp
;; ✅ Common fields in parent record, rows in positional list (100% 1-token keys)
(:curr "USD" :env :prod :tenant 1042
 :data (Item
         [1 "SSD-1TB" 89.99]
         [2 "RAM-32GB" 129.50]
         [3 "GPU-4070" 549.00]))
```
- Every key (`:curr`, `:env`, `:tenant`, `:data`) is **1 token**.
- The receiver merges the parent keys into each materialized item.
- On 500 rows, this saves **1,500 duplicate key-value pairs** with zero syntax overhead.

### Primitive Array & Vector Economy
Even for simple arrays, ASN eliminates comma and quote bloat:
- **JSON**: `["alpha", "beta", "gamma", "delta"]` $\rightarrow$ 13 tokens
- **ASN**: `[:alpha :beta :gamma :delta]` $\rightarrow$ 5 tokens (whitespace-delimited, single-token keyword symbols)
- **Numeric Vectors**: `[1 2 3 4 5 6 7 8 9 10]` vs `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]` (-50% tokens by omitting commas).

### Token Scorecard: 100 Database Records (4 Fields Each)
| Format | Token Count | Generation Latency | Context Window Impact |
|---|---|---|---|
| **Verbose JSON** | ~2,100 tokens | ~4.2 seconds | 16% of 16K window |
| **Standard ASN Objects** | ~980 tokens | ~1.9 seconds | 7% of 16K window |
| **ASN Schema Grouping `(Item ...)`** | **~380 tokens** | **~0.6 seconds** | **<2.5% of 16K window (-82%)** |

---

### Edge Cases & Universal Robustness in Tabular Projections

Any tabular or positional serialization format must answer hard production questions. Here is how ASN deterministically handles every potential edge case:

#### 1. Sparse, Missing, or Optional Fields
- **The Problem**: In JSON, if a record has no discount, the key is omitted (`{"id": 1}`). In a positional row, omitting an entry would shift all subsequent column positions.
- **The ASN Solution**:
  1. **Nil Sentinel (`_`)**: ASN uses `_` (1 token) for `nil` / `None` / `null`:
     ```lisp
     (Item
       [1 "SSD-1TB" 89.99 _]
       [2 "RAM-32GB" 129.50 15.00])
     ```
  2. **Sparse Tail Overrides**: If only 2% of rows have rare fields, keep them out of the table headers and append them as trailing keyword pairs without corrupting positional columns:
     ```lisp
     (Item
       [1 "SSD-1TB" 89.99]
       [2 "RAM-32GB" 129.50 (:promo "HOLIDAY20")])
     ```

#### 2. Polymorphic / Heterogeneous Collections (Mixed Object Shapes)
- **The Problem**: An array containing different kinds of entities (e.g. `User`, `Bot`, `SystemEvent`).
- **The ASN Solution**:
  ASN uses **Sum Types (Tagged Variant Constructors)**:
  ```lisp
  ;; Heterogeneous Stream using Tagged Variant Constructors
  [(User 1 "Alice" :admin)
   (Bot 2 "code-bot" "gpt-4o" 1200)
   (Event :deploy :success 1714829100)]
  ```

#### 3. Deeply Nested Objects & Collections Inside Rows
- **The Problem**: A table column contains a nested list or a nested record.
- **The ASN Solution**:
  S-expressions compose recursively with zero escaping!
  ```lisp
  (Post
    [1 "First Post" [:ai :wasm] (:views 1200 :stars 45)]
    [2 "Second Post" [:rust]    (:views 800  :stars 20)])
  ```
  No backslashes, no JSON string escapes, 100% clean AST.

#### 4. Schema Evolution & Backward/Forward Compatibility
- **The Problem**: Producer adds a new field, but Consumer expects older version.
- **The ASN Solution**:
  When using ad-hoc `([keys...] [[rows...]])`, mapping is dynamic by header name. Unknown columns are ignored; missing expected columns take the schema default (`:dflt`).

#### 5. Chunked Streaming for Infinite Generators
- **The Problem**: In JSON, an unclosed array `[ ...` fails `JSON.parse()` if a stream drops midway.
- **The ASN Solution**:
  ASN streams in self-contained chunk blocks:
  ```lisp
  (:chunk (Item [1 :ok] [2 :ok]))
  (:chunk (Item [3 :retry] [4 :ok]))
  ```
  Every chunk is balanced and valid on arrival. If the network drops at chunk 40, the first 39 chunks remain 100% valid in host memory with zero parser exceptions.

---

### Language-Level Structural Factoring (Schema Mixins: `@include` [Roadmap v1.0])

> **Compatibility Notice**: In the normative v0.2 compiler, every schema field requires a docstring `STRING` (`(:f id Int64 "doc")`). Schema mixins (`@include`) and decoupled metadata without inline docstrings are specified for the **v1.0 Suite** (`asl-decoupled-meta-v1`).

```lisp
;; [Roadmap v1.0 Preview]
;; Base audit struct defined once:
(dfs AuditMeta
  (:f id Int64 "ID")
  (:f ts Int64 "Timestamp")
  (:f tenant Int64 "Tenant"))

;; Derived schemas factor in the base structure:
(dfs UserProfile
  (@include AuditMeta)
  (:f email String "Email")
  (:f role String "Role"))

(dfs Order
  (@include AuditMeta)
  (:f total Float64 "Total")
  (:f items (List String) "Items"))
```
*Code stays clean, maintenance is centralized, and AST size remains minimal.*

---

## 6. Context Offloading via Handles (`@offload`)

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

## 7. Summary Reference Workflow

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
