# AgentScript Context Economy & Intent Separation Guidelines

> **Advisory.** This document is normative for nothing. [`AGENT_SPEC_CORE.md`](../AGENT_SPEC_CORE.md)
> defines the language, [`ASN_SPEC.md`](ASN_SPEC.md) defines the data format, and
> [`AGENTIC_PROTOCOL.md`](AGENTIC_PROTOCOL.md) defines the wire. This page is advice about using
> them well.
>
> Every `lisp` example is parsed on every run by `grammar/validate_asn.py`, against
> `agentscript.lark` when it is a declaration and `asn.lark` when it is data. Every number comes
> from `bench/asn_tokens.py` and is locked in `bench/asn_tokens.lock`.
>
> The previous version of this page asserted -80%, -75%, -70%, -67%, -50% and -45%, and a table
> claiming fourteen abbreviations were each one BPE token. None of it had been counted. When it was,
> four of those abbreviations turned out to cost *more* than the word they replaced.

---

## 1. Separation of code and intent

### The problem

Human code carries comments that restate it:

```python
# Loop through the orders and add up total prices
total = 0
for order in orders:
    total += order.price  # add order price
```

For an agent reading the file these are pure cost. The code already says what it does, and a
comment that paraphrases it rots the moment the code changes.

### The standard

1. **No comment that restates the code.** Names carry the *what*.
2. **Comments carry the why**: the tradeoff, the workaround, the spec quirk, the race the ordering
   protects against.
3. **Longer rationale goes out of band**, keyed by a shortcode.

The declaration keeps a one-line `:d`, and nothing else:

```lisp
(df calculate-hash [(payload Str) (nonce I64)] -> Str
  :d "Fingerprint a payload with its nonce."
  "@s02"
  (str payload (string-from-int64 nonce)))
```

**Recommendation on Symbolic Anchors**: Default to ultra-minimalist **3-alphanumeric character tags** (e.g. `@s02`, `@d01`, `@sec`, `@h99`) which guarantee 1–2 token density across BPE vocabularies. If an artificial tag is undesirable, reference the code path directly via module and method (e.g. `auth/calculate-hash`).

The rationale itself is stored out-of-band in the architecture ledger rather than inside code:

```asn
([:id :type :fn :invariant :why]
 [["s02" :decision "calculate-hash" "constant-time" "A constant-time primitive, so comparison cannot leak by timing."]])
```

An agent that understands the logic reads only the declaration. One that needs the reason queries it out-of-band:

```bash
asl meta get s02
asl meta get auth/calculate-hash
```

---

## 2. Compact Token Compression & Structural Economy
 
AgentScript (ASL) is always compact. There is no verbose format in production —
verbose syntax (`defun`, `defschema`, etc.) is strictly an ephemeral debugging view (`asl view`),
forbidden in saved code (`tools/verbose_linter.py`).

**How ASL compresses tokens:**
1. **Primitive Density (≤ 2 tokens):** Every language primitive (`df`, `dfs`, `dfe`, `mt`, `:d`, `:x`, `:i`, `:a`, `:f`, `:c`, `I64`, `Str`, `Bool`, etc.) adheres to a strict 2-token ceiling under standard BPE tokenizers (`bench/token_audit.py --check`), avoiding multi-token fragmentation.
2. **Structural Elimination (57%–65% over JSON):** The largest source of token inflation in AI workloads is syntax ceremony — repetitive JSON quotes, braces, colons, and repeated key strings. AgentScript S-expressions (AgP) and ASN tabular serialization eliminate this entirely:
   - Command frames compress by **64.7%** (18 tokens vs JSON's 51 tokens).
   - Tabular records compress by **57.9%** (1,601 tokens vs JSON's 3,802 tokens).

### Where short names are wrong regardless


1. **Domain entities.** `OrganizationMembershipInvite` mangled into `OrgMmbrshpInvt` costs an agent
   its grip on what the type means, and a hallucinated field is worth far more than two tokens —
   which, per the table above, is more than the mangling would have saved anyway.
2. **Literal values.** UUIDs, ISO timestamps, human-facing error text. A payload reflects the world
   verbatim.
3. **Foreign symbols.** An FFI name must match the host's exactly or the call does not link.

---

## 3. Positional frames against keyed frames

When both ends already know a signature, repeating its parameter names on every call is redundant.
Given this declaration:

```lisp
(df run-command [(bin Str) (args (List Str)) (t-out I64) (cwd Str)] -> Str
  :d "Run a binary with arguments, a timeout in milliseconds, and a working directory."
  (str bin " in " cwd))
```

the arguments can travel positionally. Measured over the spellings of one command,
`bench/token_frames.py` gives:

| Spelling | Tokens |
|---|---|
| JSON | 51 |
| AgentScript (ASL, positional) | 18 |

Positional AgentScript is 65% smaller than the JSON frame. That figure is locked in
`bench/token_frames.lock`.

The frame itself — the `!`, `?` and `~` heads — belongs to
[`AGENTIC_PROTOCOL.md`](AGENTIC_PROTOCOL.md) and is **not** ASN. Those three characters are not
producible by `AGENT_SPEC_CORE.md` §2's lexer at all, which is a problem that document has to
resolve for itself:

<!-- not-agentscript: a protocol frame; `!` is not a character AGENT_SPEC_CORE.md section 2 produces -->
```lisp
(! cmd "git" ["status" "--porcelain"] 5000 "/workspace")
```

A frame's *payload* is ASN, and that part parses:

```asn
(:bin "git" :args ["status" "--porcelain"] :t-out 5000 :cwd "/workspace")
```

**Positional is not free.** It costs the reader the names, so it pays where a signature is fixed
and hot, and costs where a shape is evolving. Prefer keys at an interface boundary and positions
inside a loop.

---

## 4. Deduplicating tabular data

### The problem

In JSON, an array of objects repeats every field name on every item:

```json
[
  {"id": 1, "sku": "SSD-1TB", "price": 89.99, "status": "in-stock"},
  {"id": 2, "sku": "RAM-32GB", "price": 129.50, "status": "in-stock"},
  {"id": 3, "sku": "GPU-4070", "price": 549.00, "status": "low-stock"}
]
```

At 100 rows of four fields that is 400 repeated keys, and 3,802 tokens.

### Schema-grouped rows

Declare the shape once:

```lisp
(dfs Item
  (:f id     I64 "ID")
  (:f sku    Str "SKU")
  (:f price  F64 "Price")
  (:f status Str "Stock status"))
```

Then name the constructor once and write bare positional rows:

```asn
(Item
  [1 "SSD-1TB"  89.99 "in-stock"]
  [2 "RAM-32GB" 129.50 "in-stock"]
  [3 "GPU-4070" 549.00 "low-stock"])
```

| 100 rows, four fields | Tokens | Against JSON |
|---|---|---|
| JSON, pretty-printed | 3,802 | — |
| ASN records, keys repeated | 2,600 | -32% |
| ASN schema-grouped rows | **1,601** | **-58%** |

The `-82%` this page used to claim was never counted. The real figure is 58%, and it is worth
having.

ASN needs no `@table` or `@with` keyword to get there. It reuses the constructor position the
language already has.

### Ad-hoc tables

Without a compiled schema — an ad-hoc query result, a CSV import — the header travels with the
data as a bare two-element form:

```asn
([:id :sku :price :status]
 [[1 "SSD-1TB"  89.99 "in-stock"]
  [2 "RAM-32GB" 129.50 "in-stock"]
  [3 "GPU-4070" 549.00 "low-stock"]])
```

Mapping is by header name, so an unknown column is ignored and an absent one takes its `:default`.
A row whose length differs from the header's is an error: a table is a rectangle, and `_` is
already there for a missing cell.

### Shared-field envelopes

A field with the same value on every row goes in the parent instead:

```asn
(:curr "USD" :env :prod :tenant 1042
 :data (Order
         [1 "SSD-1TB"  89.99]
         [2 "RAM-32GB" 129.50]
         [3 "GPU-4070" 549.00]))
```

The receiver merges each shared field into every element of `:data`, **one level deep**, and where
an element carries the key itself the **element wins** — the envelope is a default for the group,
not an override, so a row can opt out without splitting the envelope.

**Measured:** on three rows carrying three shared fields, the envelope saves 11% (65 tokens to 58).
It grows with the row count, so on 500 rows it is most of the payload; on three it is a rounding
error. Reach for it when the group is large.

### Vectors

- `["alpha", "beta", "gamma", "delta"]` is 12 tokens; `[:alpha :beta :gamma :delta]` is 9. **-25%**,
  not the 45% claimed here before.
- A 3×3 float matrix is 45 tokens as JSON and 39 as ASN. **-13%**, not 50%: in `cl100k_base` a
  comma usually merges with the digit beside it rather than costing a token of its own.

### Edge cases

**Sparse fields.** `_` is nil. It denotes `(none)` where the field is an `(Option T)` and is an
error where it is not, because a non-optional field has no nil inhabitant to denote.

```asn
(Item
  [1 "SSD-1TB"  89.99 _]
  [2 "RAM-32GB" 129.50 15.00])
```

A field carried by two per cent of rows is written as a trailing record instead, past the last
positional column:

```asn
(Promo
  [1 "SSD-1TB"  89.99]
  [2 "RAM-32GB" 129.50 (:promo "HOLIDAY20")])
```

**Mixed shapes.** A union case is a kebab-case head with positional arguments, exactly as Core §4.4
writes it:

```asn
[(user 1 "Alice" :admin)
 (bot 2 "code-bot" "gpt-4o" 1200)
 (deploy-event :success 1714829100)]
```

A PascalCase head is a record constructor and takes `:key value` pairs. The two are told apart by
the head's case, not by a tag field.

**Nesting.** A row column may hold a vector or a record:

```asn
(Post
  [1 "First Post"  [:ai :wasm] (:views 1200 :stars 45)]
  [2 "Second Post" [:rust]     (:views 800  :stars 20)])
```

**Streaming.** Every ASN document is balanced, so a stream cut at chunk 40 leaves the first 39
readable. What delimits one chunk from the next is framing, and framing belongs to
[`AGENTIC_PROTOCOL.md`](AGENTIC_PROTOCOL.md).

---

## 5. Shared value pools

Long values that recur — a URL, a trace id, a context map — are written once and named by index:

```asn
(:pool ["https://api.internal.invalid/v2/telemetry/nodes"
        {:region :us-east :env :prod}]
 :data [(:ts 1714829100 :url (:ref 0) :ctx (:ref 1) :status :ok)
        (:ts 1714829105 :url (:ref 0) :ctx (:ref 1) :status :ok)
        (:ts 1714829110 :url (:ref 0) :ctx (:ref 1) :status :warn)])
```

Two `(:ref 0)` occurrences denote *the same* entry, not two equal copies, which is what also makes
the pool the way to write a cyclic graph. A reference may precede the entry it names; a dangling
index is a decode error and never nil. See [`ASN_SPEC.md`](ASN_SPEC.md) §8 for the scoping and
resolution rules.

**Measured:** on the three events above, pooling saves 12% (121 tokens to 107). Neither `:pool` nor
`:ref` is one token — both are two — so the pool pays through repetition alone, and a pool that
carries a value used twice is not worth its own two tokens.

---

## 6. Schema mixins — a proposal, not a feature

Composing a schema from a shared base is a **language** question and belongs to
[`AGENT_SPEC_CORE.md`](../AGENT_SPEC_CORE.md), not to a data format: a payload never sees how a
schema was assembled, only the field list it produced.

The form below **does not parse under v0.2** and is reproduced as a proposal:

<!-- not-agentscript: `:use` is a v1.0 proposal for AGENT_SPEC_CORE.md and has no v0.2 spelling -->
```lisp
(dfs AuditMeta
  (:f id I64 "ID")
  (:f ts I64 "Timestamp")
  (:f tenant I64 "Tenant"))

(dfs UserProfile
  (:use AuditMeta)
  (:f email Str "Email")
  (:f role Str "Role"))
```

Under v0.2 every field carries a doc-string and there is no `:use`. Write the fields out.

---

## 7. Context offloading

When a tool produces 50KB of output, do not put it in the prompt. Store it and return a pointer:

```asn
(:offload "scrape-9481"
 :summary "Extracted 42 product items. Status 200. Zero parse errors."
 :size-bytes 54200
 :sample [(:sku "A1" :price 24.50)
          (:sku "A2" :price 12.00)])
```

The reasoning agent reads the summary. If it needs a slice, it asks for one, and that request is a
protocol frame rather than a value:

<!-- not-agentscript: a protocol frame; `?` is not a character AGENT_SPEC_CORE.md section 2 produces -->
```lisp
(? data/slice :id "scrape-9481" :offset 10 :limit 5)
```

This page used to score offloading at "-99% tokens", comparing a pointer against a blob nobody was
going to send. That is a statement about the idea, not about the notation, so it carries no number
here.

---

## 8. The workflow, end to end

```
[ .asl source: the how and the what ]
        |
        +--> :d "... Rationale: d-4a1b."
        |
        +--> "why does this exist?"
                    |
                    v
        [ out-of-band ASN: asl meta get d-4a1b ]
        (:tag "d-4a1b" :why "..." :adr "ADR-4a1b" :invariant "release within 50ms")
```
