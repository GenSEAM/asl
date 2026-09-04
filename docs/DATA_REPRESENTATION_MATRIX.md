# AgentScript Data Representation & Edge-Case Coverage Matrix

> **Advisory.** This document is normative for nothing. [`ASN_SPEC.md`](ASN_SPEC.md) defines ASN;
> this page illustrates it, one real-world data shape at a time. Where the two disagree, the
> specification is right and this page is a bug.
>
> Every example below is a document `grammar/asn.lark` accepts and
> `packages/asl-codec` reads. `grammar/validate_asn.py` parses each one on every run, so an example
> cannot rot into a form no reader takes — which is what happened to the previous version of this
> page, where roughly a dozen constructs parsed under neither grammar.
>
> Every percentage is a figure `bench/asn_tokens.py` counts under `cl100k_base`, locked in
> `bench/asn_tokens.lock`. The version of this page that asserted -82%, -75%, -70%, -60%, -50%,
> -45% and -99% had measured none of them, and the real numbers are roughly half the claimed ones.

---

## 1. Taxonomy of data cases

| # | Data case | JSON failure mode | ASN representation | Measured |
|---|---|---|---|---|
| **01** | Flat homogeneous records | Key names repeated on every object | Schema-grouped rows `(Item [1 "SSD-1TB" 89.99])` | **-58%** at 100 rows |
| **02** | Sparse / nullable fields | Missing keys shift positional arrays | Nil sentinel `_`, or a sparse tail override `(:promo "X")` | — |
| **03** | Polymorphic collections | Disjoint unions need a `{type, data}` wrapper | Union case values `[(user 1 "Alice") (bot 2 "code-bot")]` | — |
| **04** | Deep recursive trees | Quote escaping and bracket nesting | Balanced S-expressions, zero escapes | — |
| **05** | Dynamic key dictionaries | Quotes on every key | `{:k1 v1}`, or `{("dotted.key" v)}` for keys a keyword cannot spell | **-25%** on a four-element vector |
| **06** | Large binary blobs | Context exhaustion on base64 | An offload pointer record, the blob left on disk | — |
| **07** | Multi-line code with quotes | Escaping | Core §2's five escapes, or a vector of lines | — |
| **08** | Chunked real-time streams | An unclosed `[` breaks `JSON.parse` | Every document is balanced; framing is the protocol's | — |
| **09** | Matrices and tensors | Comma bloat | Whitespace-delimited nested vectors | **-13%** on a 3×3 |
| **10** | Circular references | `TypeError: Converting circular structure` | `:pool` entries named by `(:ref N)` | — |
| **11** | Schema evolution | Missing keys crash static decoders | Ad-hoc tables map by header name; absent fields take `:default` | — |
| **12** | Failure signals | Inconsistent HTTP error shapes | Protocol frames, not ASN — see [`AGENTIC_PROTOCOL.md`](AGENTIC_PROTOCOL.md) | — |

A dash means the case is about correctness, not size. Cases 02, 03, 04, 07, 10 and 11 exist because
JSON gets them *wrong* or unsafe, and no honest percentage attaches to "does not crash".

---

## 2. Concrete syntax and behaviour, case by case

### Case 01 — flat homogeneous records

The schema is declared once, in AgentScript:

```lisp
(dfs Item
  (:f id     Int64   "ID")
  (:f sku    String  "SKU")
  (:f price  Float64 "Price")
  (:f status String  "Stock status"))
```

The payload names the constructor once and writes bare positional rows:

```asn
(Item
  [1 "SSD-1TB"  89.99 "in-stock"]
  [2 "RAM-32GB" 129.50 "in-stock"]
  [3 "GPU-4070" 549.00 "low-stock"])
```

`status` is declared `String`, so the column carries `"in-stock"` and not `:in-stock`. Core §3
declares no keyword type, so a keyword in a schema-bound column has nothing to bind to
(`ASN_SPEC.md` §3.2). Measured in context this costs one token per cell — ` :in-stock` is three and
` "in-stock"` is four — and the rule is kept for type soundness, not for price.

Element *i* of a row fills field *i* in **declaration order**. A short row takes each missing
field's `:default`; a field with no `:default` and no value is an error, not a silent nil.

**Measured:** 100 rows of four fields cost 3,802 tokens as pretty-printed JSON and 1,601 as a row
group — 58% fewer. Against ASN records with the keys repeated (2,600 tokens) the grouping saves
38%.

---

### Case 02 — sparse, optional and nullable fields

`_` is nil. It denotes `(none)` where the field's declared type is an `(Option T)`, and is an error
where it is not — a non-optional field has no nil inhabitant, so accepting one would build a value
the checker says cannot exist.

```asn
(Item
  [1 "SSD-1TB"  89.99 _]
  [2 "RAM-32GB" 129.50 15.00])
```

A field carried by two per cent of rows does not belong in the schema. It is written as a trailing
record, past the last positional column:

```asn
(Promo
  [1 "SSD-1TB"  89.99]
  [2 "RAM-32GB" 129.50 (:promo "HOLIDAY20")])
```

`Promo` declares three fields, so the record at index 3 is an override. **Position decides, not
shape**: below index 3 the same record would be an ordinary positional value, which is what a row
must be able to say when a field's own type is a record.

---

### Case 03 — polymorphic collections

A union case is written exactly as Core §4.4 writes it: kebab-case head, positional arguments. The
collection is self-describing without a wrapper on every item.

```asn
[(user 1 "Alice" :admin)
 (bot 2 "code-bot" 1200)
 (deploy-event :success 1714829100)]
```

A PascalCase head is a *record* constructor and takes `:key value` pairs instead. The two are told
apart by the head's case, never by a tag field.

---

### Case 04 — deep recursive trees

```asn
(Element :tag :html :kids
  [(Element :tag :head :kids
     [(Element :tag :title :text "Dashboard")])
   (Element :tag :body :class "dark-mode" :kids
     [(Element :tag :h1 :text "Telemetry")
      (Element :tag :p  :text "Status: Online")])])
```

Not one escape character, at any depth.

---

### Case 05 — dynamic key-value maps

```asn
{:theme "dark" :font "mono" :retries 3}
```

Keys a keyword cannot spell — a dotted path, an integer, a boolean — use the parenthesised entry:

```asn
{("system.memory.max" 16384)
 ("system.cpu.cores" 8)
 (:custom-env-flag true)}
```

A float may not be a map key. Core §3 forbids `Float64` as a `(Map K V)` key because its equality
is IEEE-754, and a `NaN` key could never be looked up again; the grammar refuses one rather than
leaving it to a checker.

**Measured:** `["alpha", "beta", "gamma", "delta"]` is 12 tokens and `[:alpha :beta :gamma :delta]`
is 9 — 25% fewer, not the 45% this page used to claim.

---

### Case 06 — heavy binary payloads

Small digests go inline:

```asn
(:algo :blake3 :hash "4f8a12e3b7")
```

Anything large is left where it is and named:

```asn
(:offload "blob-8941"
 :summary "10MB raw audio WAV, 44.1kHz."
 :size-bytes 10485760
 :sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
```

This is an ordinary record. The `(! data/offload …)` spelling this page used to carry is a
protocol **frame**, and `!` is not a character Core §2 produces; the payload is ASN and the frame
around it belongs to [`AGENTIC_PROTOCOL.md`](AGENTIC_PROTOCOL.md).

The old "-99% tokens" figure compared a pointer with a blob nobody was ever going to send, which
makes it a statement about the offloading idea rather than about the notation. It is deleted.

---

### Case 07 — multi-line text and code

```asn
(:lang :python
 :body "def query_users(db):\n    cursor = db.cursor()\n    cursor.execute('SELECT \"id\" FROM users')\n    return cursor.fetchall()")
```

Or, where the escapes get dense, a vector of lines the consumer joins:

```asn
(:lang :python
 :lines ["def query_users(db):"
         "    cursor = db.cursor()"
         "    return cursor.fetchall()"])
```

There is no `#"""…"""#` raw string. `#` is a character the language lexer cannot produce, and a
data format that adds one has forked the lexer it claims to share (`ASN_SPEC.md` §12.2).

---

### Case 08 — chunked streaming

Every ASN document is balanced, so a stream severed mid-flight leaves every document that already
arrived readable. That is a consequence of the value grammar, not a construct in it.

A chunk record is an ordinary record whose key happens to be `:chunk`:

```asn
(:chunk (SensorReading [1 22.4] [2 22.8]))
```

ASN gives it no meaning. What delimits one chunk from the next, and what ends a stream, is framing,
and framing is [`AGENTIC_PROTOCOL.md`](AGENTIC_PROTOCOL.md)'s.

---

### Case 09 — numeric matrices and tensors

```asn
[[1.0 0.0 0.0]
 [0.0 1.0 0.0]
 [0.0 0.0 1.0]]
```

**Measured:** the JSON spelling of this matrix is 45 tokens and the ASN spelling is 39 — 13% fewer.
The old "-50%" assumed a comma costs a token everywhere; in `cl100k_base` a comma usually merges
with the digit beside it.

---

### Case 10 — circular references and graphs

One mechanism serves deduplication and identity alike. Values are written once in `:pool` and named
by index; two `(:ref 0)` occurrences denote *the same* entry, not two equal copies.

```asn
(:pool [(:name "Orchestrator" :peers [(:ref 1)])
        (:name "Worker"       :peers [(:ref 0)])]
 :data [(:ref 0) (:ref 1)])
```

A reference may precede the entry it names — unavoidable in a cycle — because resolution is by
index and not by document order. A dangling index is a decode error and never nil.

The `(& 1 :name "x")` anchor this page used to specify is **deleted**, not respelled: `&` is in no
Core §2 token, and an anchor was never a second idea (`ASN_SPEC.md` §8.1).

**Measured:** on three events sharing a URL and a context map, pooling saves 12% (121 tokens to
107). The pool pays on repetition, so the figure grows with the payload; it is not a constant.

---

### Case 11 — schema drift and compatibility

```asn
([:id :sku :price :currency]
 [[1 "SSD-1TB"  89.99 "USD"]
  [2 "RAM-32GB" 129.50 "USD"]])
```

- A column the consumer does not know is **ignored**, so a producer that adds a field does not
  break an older consumer.
- A field the consumer expects and the header omits takes its `:default` from the `dfs` (or `defschema`). No
  `:default` declared is an error.
- A row whose length differs from the header's is an error. A table is a rectangle, and `_` is
  already there for a missing cell.

The default comes from `:default`. There is no `:dflt`: measured in context, ` :dflt` costs
**three** tokens against ` :default`'s two, so the abbreviation is a regression as well as a second
name for one option (`ASN_SPEC.md` §13).

---

### Case 12 — errors and failure modes

An error is a **frame**, not a value, and belongs to [`AGENTIC_PROTOCOL.md`](AGENTIC_PROTOCOL.md).
Its payload is ASN:

```asn
(:status :err
 :code :permission-denied
 :msg "Path '/etc/shadow' is outside the jailed workspace"
 :retry false)
```

---

## 3. What the guarantees actually are

The four properties this page used to call invariants, restated as what a gate enforces:

1. **One-pass parsing.** Every parenthesised form is decided by its first token, and a row group is
   told from a named construction by the second. No rule anywhere backtracks —
   `grammar/asn.lark` is the executable statement of that.
2. **Balanced documents.** A document is exactly one balanced value, which is what makes a severed
   stream lose only the document in flight.
3. **Termination on a cycle.** The reader does not substitute `(:ref N)` at all; resolution is a
   separate, depth-bounded operation with a defined failure. Nothing loops.
4. **A closed error set.** Every failure a decoder may report is one of the codes `ASN_SPEC.md` §11
   names, and `packages/asl-codec/tests/test_asn.py` fails on a code outside that set.

**Single-token hygiene is not among them.** It was asserted here and it is not true. `:pool`,
`:ref` and `:default` are two tokens each, and abbreviating an identifier saves no tokens at all:
across all 36 fixtures in `grammar/corpus/valid`, the verbose and standard ASL projections cost an
identical 15,931 tokens (`bench/token_projection.py`). What ASN actually removes is **structure** —
quotes around keys, commas, braces, and a field name repeated on every row — and that is what every
measured figure above is measuring.
