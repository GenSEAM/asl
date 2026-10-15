# Stop Burning Money on JSON Context: Structural Compaction Saves Tokens, Abbreviation Does Not
*By GenSEAM | September 2026*

In AI-assisted software engineering, tokens are currency and bandwidth. Every extra token in an agent prompt adds to the inference bill, adds latency to tool-calling loops, and dilutes attention.

Faced with this, developers often jump to an intuitive conclusion: *if we abbreviate everything (shorten `function` to `fn`, `config` to `cfg`, `message` to `msg`) we will slash our token consumption.*

Under a byte-pair tokenizer, that assumption is mostly false.

In this essay we measure why abbreviating keywords saves little or nothing, and where the large reductions actually come from: **structural compaction and tabular serialization**. Every count below was taken with js-tiktoken 1.0.15 on 2026-10-14, and each covers only the strings shown.

---

## 1. The Abbreviation Fallacy: Why Shortening Words Fails Under BPE

Byte-pair encoding tokenizers (such as OpenAI's `cl100k_base` and `o200k_base`) do not tokenize by character. They assign single token IDs to frequent subwords and whole English words, so common words are already cheap.

### The Measurement

Counting single keywords under `cl100k_base`, first bare and then after a space as they appear inside a form:

| Keyword | Bare | In context | Abbreviation | Bare | In context |
|---|---|---|---|---|---|
| `:config` | 2 | 2 | `:cfg` | 2 | 2 |
| `:message` | 1 | 2 | `:msg` | 2 | 2 |
| `:error` | 1 | 2 | `:err` | 2 | 2 |
| `:function` | 1 | 2 | `:fn` | 2 | 2 |
| `:default` | 2 | 2 | `:dflt` | 2 | 3 |

Most abbreviations tie in context, and some cost more: `:dflt` takes 3 tokens where `:default` takes 2.

The effect across a whole codebase is small. Rewriting every camelCase identifier in the tracked `.asl` and `.asn` files (2964 files, 169852 identifiers) to kebab-case and counting both versions gave a saving of 1.90% for camelCase under `o200k_base` and 1.68% under `cl100k_base` (measured 2026-09-22, recorded in the project ledger as `CamelCaseCorpusSaving` and listed in `bench/publishedClaims.asn`). Naming conventions move token counts by a few percent, not tens of percent.

---

## 2. One Spelling per Concept

If shortening keywords does not pay, what should a language choose? AgentSlang's rule is whole words in camelCase and one spelling per concept, and among names that carry the meaning, the measured cheapest wins.

The forms the stage-0 host accepts today:

| Concept | Form | Accepted alias |
|---|---|---|
| Function | `fn name a: Type -> Type` line | `lambda` for anonymous `fn` |
| Record type | `schema Name` with field lines | |
| Variants | `enum Name (case field: Type) ...` | |
| Match | `mt` | `match` |
| Sequence | `do` | `begin` |
| Module exports, imports | `:x`, `:i` | |
| Primitive types | `Int64`, `Float64`, `String`, `Bool` | |

The older `defun` and `df` definition heads are rejected by the host (`ERR_UNSUPPORTED_TOPLEVEL`), and so are `:d` docstrings (`ERR_READ_DOC`): documentation lives as rows in each package's `doc.asn`, not in the source.

```agentslang
(module math/vector :x [dot runTests] :i [])

schema Point
  x: Float64
  y: Float64

fn dot a: Point b: Point -> Float64
  (+ (* a.x b.x) (* a.y b.y))

fn runTests -> Bool
  (do (assert (= (dot {:x 1.0 :y 2.0} {:x 3.0 :y 4.0}) 11.0) "dot product") true)
```

This module passes `asl-host check` and `asl-host test`.

---

## 3. Rationale Out of Band

Where tokens *are* wasted in source code is in comments that restate the code:

```python
# Check if the user is authenticated and has permission to access the resource
if user.is_authenticated and user.has_permission(resource):
    allow_access()
```

The comment repeats what the names already say.

The convention we adopt:
1. **No restating comments:** names carry the *what*.
2. **Docs out of the source:** a symbol's contract is one row in the package `doc.asn`, looked up with `asl '(:doc :symbol "path#name")'`.
3. **Rationale in the ledger:** long design justifications live in the project memory under `.asl/mem/` (principles, decisions), where an agent retrieves them only when it needs them, with `(:mem :op query ...)` or `(:query :text "..." :in text)`.

---

## 4. Structural Compaction: Where the Savings Live

If abbreviations do not save tokens, what does? **Removing repeated structure.**

In JSON tool calls, a large share of the token stream is punctuation (quotes around keys, colons, commas, braces) and key names repeated on every row.

### A Command Frame in Four Encodings

1. **JSON** (41 tokens under `cl100k_base`):
```json
{
  "target": "agent-coder",
  "action": "synthesize-fsm",
  "states": ["idle", "active", "error"],
  "timeout_ms": 50
}
```

2. **TOON (Token-Oriented Object Notation)** (27 tokens):
```text
target: agent-coder
action: synthesize-fsm
states: [idle, active, error]
timeout_ms: 50
```

3. **Keyed S-expression frame** (25 tokens):
```text
(? agent-coder synthesize-fsm :states ["idle" "active" "error"] :timeoutMs 50)
```

4. **Positional S-expression frame** (20 tokens):
```text
(? agent-coder synthesize-fsm ["idle" "active" "error"] 50)
```

On this frame, moving from JSON to the positional form saves 51.2% under `cl100k_base` (41 to 20) and 52.4% under `o200k_base` (42 to 20). The README shows a second frame, a `git status` command with its arguments, working directory and timeout: 51 tokens as JSON and 18 as a positional frame under `cl100k_base`, a 64.7% saving.

### Tabular Data: ASN Against JSON

When agents pass batches of records, JSON repeats every key on every object:

```json
[
  {"id": 101, "sku": "A-44", "qty": 5, "status": "shipped"},
  {"id": 102, "sku": "B-12", "qty": 1, "status": "pending"},
  {"id": 103, "sku": "C-99", "qty": 12, "status": "delivered"}
]
```

AgentSlang Notation (ASN) states the column names once and streams the rows as positional vectors:

```asn
([:id :sku :qty :status]
 [[101 "A-44" 5 "shipped"]
  [102 "B-12" 1 "pending"]
  [103 "C-99" 12 "delivered"]])
```

These three records take 85 tokens as JSON and 51 as the ASN table under `cl100k_base`, a 40.0% saving. The header is paid once, so the share of the stream spent on key names shrinks as rows are added, while JSON pays for every key on every row.

---

## 5. Takeaways for Agentic Systems

1. **Stop shortening identifiers:** renaming `calculateTotal` to `calcTot` saves little or nothing and makes the name harder for a model to recall.
2. **Remove punctuation overhead:** quotes, colons and commas around every key are paid on every call; whitespace-separated S-expressions do without them.
3. **Hoist repeated schemas:** in multi-record handoffs, send the column names once and the rows as positional vectors.
4. **Keep rationale out of the code:** the contract in a doc row, the long justification in the memory ledger.

Structure, not spelling, is where the tokens are. On the samples above, replacing keyed JSON with positional S-expressions and ASN tables cut token counts by 40% to 65%.
