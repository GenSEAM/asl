# asnSpec.md — AgentScript Notation v0.1

**Status:** normative for data. This document defines ASN: what a payload may contain, what each
form means, and what a decoder must do when a payload is wrong.

## 0. Document precedence

Three documents describe overlapping surfaces. On any conflict, the first one that covers the
question wins.

| Document | Governs |
|---|---|
| `asl/agentSpecCore.md` ("Core") | The **language**: lexical structure, types, declarations, expressions. |
| `asl/docs/asnSpec.md` (this file) | **Data**: what one ASN value is and what it means. |
| `asl/docs/agenticProtocol.md` | The **wire**: framing, handshake, streams, error frames (a target design). |

ASN adds no type to Core. It reuses Core §2's lexical structure and defines a different phrase
structure over it — the same relationship a JSON document has to JavaScript's lexer. The
executable reader is `asl/packages/asl-transpile/src/core/asn.asl`, which takes its tokens from
the language lexer (`asl/packages/asl-parser/src/lexer.asl`) rather than a second scanner. The one
lexeme ASN keeps that Core retired is the `;` comment (§2.1).

**ASN keys are data.** Core §2.1 makes an ASL compact alias significant only in the one
position it names. ASN has none of those positions, so `:f`, `:d`, `:x`, `:c`, `:i` and `:a` in an
ASN payload are ordinary keys spelled with those letters and mean nothing else. No tool may
rewrite them.

## 1. Lexical structure

Every token is Core §2's:

```
comment    ::= ";" <any char except newline>*
ident      ::= [a-z] [a-z0-9-]* [?!]?
qualified  ::= ident "/" ident
qual-type  ::= ident "/" type-name
type-name  ::= [A-Z] [A-Za-z0-9]*
keyword    ::= ":" ident
int-lit    ::= "-"? [0-9]+
float-lit  ::= "-"? [0-9]+ "." [0-9]+
string-lit ::= '"' ( char | escape )* '"'
escape     ::= "\\" ( '"' | "\\" | "n" | "t" | "r" | "0" )
bool-lit   ::= "true" | "false"
unit-lit   ::= "()"
nil-lit    ::= "_"
```

`nil-lit` is not a new token. `_` is the character Core §2 already produces as `WILDCARD` in a
pattern; ASN gives it a meaning in a position Core has no phrase for, so nothing about the lexer
changes. §3 and §5 of Core carry over unchanged: a sign belongs to the digits it touches, there is
no exponent form, and `.5` and `1.` are not numbers.

`{` and `}` are likewise already produced — Core binds type variables in them — so map literals
cost no new character either.

**Names.** The dialect rule is camelCase whole words for user-chosen keywords and symbols
(`:timeoutMs`, not `:timeout-ms`); the language's builtins keep their one hyphenated spelling
(`listLength`, `stringContains?`). What today's reader admits:

- **Keywords** in either spelling: `(:timeoutMs 5)` and `(:timeout-ms 5)` both read and write back
  unchanged. Write keys camelCase.
- **Case heads and alias prefixes** only as the `ident` rule above: lowercase, digits and single
  hyphens. `(some-case 1)` reads; `(someCase 1)` is a `parse` error. Target: camelCase heads, per
  the dialect rule; until the reader changes, a camelCase case head does not read.

## 2. Documents

**An ASN document is exactly one balanced value.** Comments and whitespace are insignificant
except as separators.

A sequence of documents is a **stream**, and delimiting one document from the next is framing.
Framing is `asl/docs/agenticProtocol.md`'s job, not this file's: see §12.

### 2.1 Comments, and why ASN has no notes

The language has a **note**: a free-standing string literal at top level, bound to nothing
(`asl/grammar/corpus/valid/33-notes.asl`).

**ASN admits no notes, and keeps `;` comments.** The reason is not preference, it is that a note
cannot exist here. A program is a *sequence of declarations*, so a bare string between two of them
is unambiguously not a declaration and can be read as prose. A document is *one value*, and a bare
string **is** a value — the two are the same phrase. There is nowhere for a note to stand and no
way to tell one from data if it stood there.

So `; …` is the only way to annotate an ASN text, and the reader strips it before reading
(`(:a 1) ; note` reads as `(:a 1)`). Core's specification retired `;` on 2026-09-03 in favour of
the note; ASN kept it for the reason above, and moving `; canonical:` / `; expect:` into a
sidecar is a cost with no payoff while `;` can still annotate. The price is stated plainly: ASN
carries one lexeme on its own authority. (The stage-0 host still reads `;` as a comment in
`.asl` files too.)

**A raw newline inside an ASN string literal is legal**, and both the grammar and the reader accept
it. The one-line restriction the language currently places on a note does not reach ASN: it exists
because a note is lowered into a target language's source, where an unescaped newline lands inside
that target's quotes. ASN text is data, read at runtime and never lowered, so there is no target
quote to escape out of. §10's "no line breaks" governs whitespace *between* tokens; a newline
inside a string is part of that string's lexeme and is preserved.

## 3. The value grammar

```
value  ::= scalar | vector | map | record | table | ctor | row-group | case-value

scalar     ::= int-lit | float-lit | string-lit | bool-lit | unit-lit | keyword | nil-lit
vector     ::= "[" value* "]"
map        ::= "{" map-entry* "}"
map-entry  ::= keyword value | "(" map-key value ")"
map-key    ::= string-lit | int-lit | bool-lit | keyword
record     ::= "(" ( keyword value )+ ")"
table      ::= "(" "[" keyword* "]" "[" row* "]" ")"
ctor       ::= "(" type-head ( keyword value )* ")"
row-group  ::= "(" type-head row+ ")"
row        ::= "[" value* "]"
case-value ::= "(" case-head value* ")"
type-head  ::= type-name | qual-type
case-head  ::= ident | qualified
```

`asl/packages/asl-transpile/src/core/asn.asl` (`asnRead`, `asnWrite`) is the executable form of
this table.

**Every parenthesised form is decided by its first token**, in one token of lookahead: a keyword
opens a record, a `[` opens a table, a PascalCase name opens a `ctor` or a `row-group` (settled by
the *second* token), a lowercase `ident` opens a case value, and `()` is unit. There is no
backtracking anywhere in the grammar, so a reader is single-pass.

A bare identifier is **not** a value. `x` alone is a parse error. Names appear only as heads.

### 3.1 Scalars

| Form | Meaning |
|---|---|
| `1`, `-1` | Integer. Widths and overflow are Core §3's. |
| `1.5` | `Float64`. |
| `"text"` | String, with Core §2's five escapes and no others. |
| `true` / `false` | Boolean. |
| `()` | Unit. |
| `:kw` | **Keyword.** A self-denoting symbolic scalar. See §3.2. |
| `_` | **Nil.** The absence of a value. See §3.3. |

### 3.2 Keywords as values

A keyword in value position is a scalar denoting itself: `[:alpha :beta]` is a two-element vector
of the keywords `:alpha` and `:beta`, not a record and not a reference to anything.

A keyword is **not** admissible where a value is bound to a declared Core type, because Core §3
declares no keyword type. Concretely: a keyword may not fill a column of a `row-group` (§6) or a
`table` (§7) that a schema maps to any Core type at all. Write the string, or write the enum case.

This rule is **not** free. Measured where the value actually sits — after a space, which BPE
merges into the token — ` :inStock` is three tokens and ` "inStock"` is four (cl100k_base via
tiktoken, 2026-09-24; the kebab spellings count the same, and `asl/bench/asn_tokens.lock` records
`column-keyword` 3 against `column-string` 4). The rule costs one token per cell.

It stands anyway, because the argument for it was never price. Core §3 declares no keyword type, so
a keyword in a schema-bound column has nothing to bind to; a format that admitted it would
materialise a value the checker says cannot exist. A rule that buys type soundness for a token per
cell is a rule worth having, and saying so is better than the earlier claim that it was free — which
was measured on the bare spellings and was wrong for that reason.

Keywords remain free as map keys, record keys, and values in schemaless positions — vectors, map
values, record values — where no Core type is claimed.

### 3.3 Nil

`_` denotes the absence of a value.

- In a **schemaless** position — a vector element, a map value, a record value — `_` is the nil
  scalar unconditionally.
- In a **schema-bound** position — a `row-group` column or a `table` cell whose column a schema
  maps to a declared field — `_` denotes `(none)` **if and only if** that field's declared type is
  `(Option T)`. If the field's type is not an `(Option T)`, `_` is a **decode error**
  (`nil-at-required-field`).

The second half is the load-bearing one. A non-optional field has no nil inhabitant in Core's type
system, so accepting `_` there would materialise a value the checker says cannot exist, and the
error would surface later, somewhere else, as a type failure with no path back to the payload.

## 4. Maps

```asn
{:theme "dark" :font "mono" :retries 3}

{("system.memory.max" 16384)
 ("system.cpu.cores" 8)
 (:customEnvFlag true)}
```

A map is an unordered dictionary. Two entry forms:

- `:kw value` — the cheap form, for a key a keyword can spell.
- `(key value)` — for a key it cannot: a dotted path, an integer id, a boolean.

A **float may not be a map key**, by grammar. Core §3 forbids `Float64` as a `(Map K V)` key
because its equality is IEEE-754 and a `NaN` key could never be looked up again; a data format
that admitted one would produce payloads no consumer could decode.

`_` may not be a map key either — nil denotes absence, and an absent key is a key that is not
there.

**Duplicate keys are an error** (`map-duplicate-key`), not last-wins. Last-wins makes two
serialisers that disagree about ordering produce two different maps from the same intent.

Entry order is insignificant. A writer emits keys in the order it holds them; a canonical writer
(§10) emits them in the order they were read.

## 5. Records

```asn
(:ts 1714829100 :url "https://…" :status :ok)
```

A record is a parenthesised form whose first token is a keyword. Keys are always keywords, values
are any value. It is the anonymous-struct shape: a decoder maps it to a record type, a struct, or
an object.

**Duplicate keys are an error** (`record-duplicate-key`), for the same reason as §4.

Three keys are **reserved** in a record and always carry the meaning this document gives them:
`:pool` (§8), `:ref` (§8), and `:data` (§9). Every other key is ordinary.

## 6. Schema-grouped rows

```lisp
(schema Item
  (:f id    Int64   "ID")
  (:f sku   String  "SKU")
  (:f price Float64 "Price"))
```

```asn
(Item
  [1 "SSD-1TB" 89.99]
  [2 "RAM-32GB" 129.50]
  [3 "GPU-4070" 549.00])
```

A `row-group` is a PascalCase head followed by one or more row vectors. The head names a
`schema` the **decoder** holds; ASN text carries no schema of its own, and a decoder given no
schema for that name must fail (`unknown-schema`) rather than guess.

**Positional binding.** Element *i* of a row supplies field *i* in the schema's **declaration
order**. Declaration order, never alphabetical and never the order of some header — it is the one
ordering both ends can read off the same `schema`.

| Situation | Rule |
|---|---|
| Row shorter than the field list | The missing tail fields take their `:default` (Core §4.1). A missing field with no `:default` is an error (`row-missing-field`). |
| Row longer than the field list | An error (`row-too-long`), except for the one sparse-tail override below. |
| `_` at position *i* | `(none)` if field *i* is an `(Option T)`; otherwise `nil-at-required-field` (§3.3). |
| A keyword at position *i* | An error unless field *i*'s type admits it, and Core declares no type that does (§3.2). |

### 6.1 Sparse tail overrides

When a field is carried by two percent of rows, putting it in the schema costs every other row a
`_`. Instead it is written as a trailing record:

```asn
(Item
  [1 "SSD-1TB" 89.99]
  [2 "RAM-32GB" 129.50 (:promo "HOLIDAY20")])
```

**Position decides, not shape.** A record inside a row is an override only when it sits at index
*N* or beyond, where *N* is the schema's field count — that is, only after every declared
positional field is filled. Below *N* it is an ordinary positional value, which is what a row
must be able to say when a field's own type is a record.

- At most one override per row (`row-override-multi`).
- It must be the row's last element (`row-override-place`).
- Its keys name fields the schema declares (`row-override-unknown`).
- A key it names that a positional element already filled is an error
  (`row-override-duplicate`), **not** a silent overwrite. Both spellings sit inside the same row,
  so one of them is a mistake; there is no reading under which the author meant both.

That last rule is deliberately the opposite of the envelope's (§9), and the difference is who
wrote the two values. Inside one row, one author wrote both. Across an envelope, the outer value
is a default supplied for the group and the inner one is the exception the group has.

### 6.2 Which names bind, and how they are compared

A schema field may carry a JSON name, `:json "..."`:

```lisp
(schema Account
  (:f holderName String "Account holder")
  (:f isoCode    String "Country" :json "countryCode"))
```

**That name is JSON's, and ASN does not use it.** An override key, a table column keyword and a
positional slot all bind to the field's **declared** name — `:isoCode`, never `:countryCode`.
(Core §4.1 also describes a `:json-case` header option; the stage-0 host rejects a schema that
carries one, so it is not shown.)

The rule has to be written down because both notations sit on one `schema` and reading it the
other way is a silent mis-bind, not an error: `:countryCode` would simply look like an unknown
column and be dropped under §7. ASN is not a JSON encoding and shares none of its naming.

**A head is compared literally, and no projection is applied to it.** A `ctor` or `row-group` head
names a schema, and ASN resolves it against the decoder's schema table as written. ASN names no
types anywhere: a head is a schema name that merely shares PascalCase with a type name. So
`(Str [1])` and `(String [1])` are two different heads to a decoder, not one head under two
spellings. A decoder holding schemas under both must normalise its own table; ASN will not do it
silently on its behalf.

## 7. Ad-hoc tables

```asn
([:id :sku :price :currency]
 [[1 "SSD-1TB" 89.99 "USD"]
  [2 "RAM-32GB" 129.50 "USD"]])
```

A table is a bare two-element form: a header vector of column keywords, then a vector of rows.
It needs no head keyword at all, which is why ASN has no `@table`. It is for data with no
pre-compiled schema — an ad-hoc query result, a CSV import.

| Situation | Rule |
|---|---|
| Row length ≠ header length | An error (`table-ragged`), long or short. A table is a rectangle; a ragged row has no benign reading, and the format has `_` for a missing cell. |
| Duplicate column keyword | An error (`table-duplicate-column`). |
| Header names a column the consumer does not know | **Ignored.** This is forward compatibility: a producer that added a field must not break an older consumer. |
| Consumer expects a field the header omits | The field takes its `:default` from the consumer's `schema`. No `:default` declared: an error (`table-missing-column`). |
| `_` in a cell | §3.3, against the column's mapped field. |

The default comes from `:default` on the `schema` field. **There is no `:dflt`** — see §13.

## 8. Shared value pool — `:pool` and `:ref`

One mechanism serves both deduplication and identity, including cycles.

```asn
(:pool ["https://api.internal.cluster.local/v2/telemetry/nodes"
        {:region :us-east :env :prod}]
 :data [(:ts 1714829100 :url (:ref 0) :ctx (:ref 1) :status :ok)
        (:ts 1714829105 :url (:ref 0) :ctx (:ref 1) :status :ok)
        (:ts 1714829110 :url (:ref 0) :ctx (:ref 1) :status :warn)])
```

**Declaration.** `:pool` is a reserved key in a **record**. Its value must be a vector
(`pool-kind`). A pool may be declared in any record, at any depth.

**Reference.** `(:ref N)` is a record whose single key is `:ref` and whose value is a non-negative
integer. A `:ref` record carrying any other key, or a non-integer index, is an error
(`ref-shape`).

**Scope.** A pool is in scope for the whole record that declares it, *including the pool vector's
own elements* and every value nested below. A nested pool **shadows** an outer one for the
subtree it governs. Scope is lexical and decidable from the text alone.

**Ordering.** A `(:ref N)` may appear before pool entry *N* in document order. Resolution is by
index, not by position, and a decoder must finish reading the document before resolving anything.
This is not a convenience: entry 0 referring to entry 1 is unavoidable in a cyclic graph.

**Dangling.** An index outside `[0, length)`, or a `(:ref N)` with no enclosing pool, is a decode
error (`ref-dangling`, `ref-no-pool`). It is never nil. Substituting nil turns a transport fault
into a data fault and moves the failure somewhere it cannot be diagnosed.

**Cycles are legal and meaningful.** A pool entry may reference itself or another entry that
references it back:

```asn
(:pool [(:name "Orchestrator" :peers [(:ref 1)])
        (:name "Worker"       :peers [(:ref 0)])]
 :data [(:ref 0) (:ref 1)])
```

Two `(:ref 0)` occurrences denote **the same** entry, not two equal copies. That is what makes the
pool an identity mechanism and not merely a compression one.

A decoder targeting a representation that cannot hold a cycle — JSON, a tree — must report
`ref-cycle` when resolution would not terminate. It must never loop. The reader
(`asl-transpile/src/core/asn.asl`) does not substitute at all: it retains `(:ref N)` as an
ordinary record, so reading is total and round-trip fidelity is exact. Target: a separate,
depth-bounded resolution operation that raises `ref-cycle`; no code resolves references yet.

### 8.1 Why not `&`

An earlier draft spelled an identity anchor `(& 1 :name "x")`. `&` is not a character Core §2 can
produce in any position (fixture `asl/grammar/corpus/asn/invalid/ampersandAnchor.asn` fails to read): it is in no identifier, no
keyword, no operator and no literal. Admitting it would mean forking the lexer, which is the one
thing ASN exists not to do.

The replacement is not a respelling. `&` is **deleted**, and anchors are pool entries, because the
pool already had to exist for deduplication and an anchor is a pool entry someone points at twice.
Two mechanisms for one idea is two decoders, two error sets and two ways for them to disagree.

`(:id N …)` was considered as the respelling and rejected: `id` is the most common domain key in
real payloads, and a marker that turns every row carrying an id into a graph anchor is a defect
generator. `:pool` and `:ref` were already reserved; `:id` was not.

## 9. Shared-field envelope — `:data`

```asn
(:curr "USD" :env :prod :tenant 1042
 :data (Item
         [1 "SSD-1TB" 89.99]
         [2 "RAM-32GB" 129.50]
         [3 "GPU-4070" 549.00]))
```

A record carrying `:data` **and at least one other key that is not `:pool`** is an **envelope**.
Its `:data` value must be a vector, a `row-group`, or a `table` (`envelope-data-kind`).

Every key of the envelope other than `:data` and `:pool` is a **shared field**, merged into each
element of `:data`.

**The merge rule, in full:**

1. **One level, never recursive.** A shared field is merged into each direct element of `:data`
   and no deeper. Recursive merge would require deciding which nested maps are the same node,
   which is identity, which §8 owns.
2. **The element wins.** When an element already carries the key, the element's value stands and
   the shared field is discarded for that element. The envelope supplies a *default for the
   group*, not an override. The alternative makes a row unable to opt out, which forces splitting
   the envelope at every exception — exactly the token cost the envelope exists to remove.
3. **Reserved keys never merge.** `:data`, `:pool` and `:ref` are the envelope's own machinery.
4. **An element that cannot take keys is left alone.** Merging into a scalar element is an error
   (`envelope-scalar-element`), because there is no field to merge into and silently dropping the
   shared fields for that element would make the payload mean two different things depending on
   the element's type.
5. **Merging into a `row-group` element** sets the named field of each row, subject to §6: the
   key must name a declared field, and a row that filled that field positionally keeps its own
   value (rule 2).

A record carrying `:data` and nothing else is **not** an envelope. It is an ordinary record with a
field called `data`, and no merge happens.

## 10. Canonical form

A canonical ASN text is what a writer emits and what round-trip fidelity is defined against:

- no comments;
- exactly one space between sibling tokens inside a form, no whitespace after an opening
  delimiter or before a closing one;
- no line breaks between tokens, though a newline inside a string literal is part of that
  literal and survives (§2.1);
- keys, entries, elements and rows in the order they were read;
- **every scalar reproduced as its source lexeme**, character for character:
  `129.50` stays `129.50` and does not become `129.5`, and a string keeps its quotes
  and its escapes.

**The round-trip property:** for canonical text *t*, `write(read(t)) == t`, byte for byte. For any
readable text *u*, `write(read(u))` is canonical and `read(write(read(u)))` reads equal to
`read(u)`. Today `asl/packages/asl-transpile/tests/asnDriver.asl` asserts idempotence on one
input; a suite that asserts both properties against hand-written canonical strings across the
corpus is a target.

The reader retains every scalar as its **source lexeme** and the writer emits it unchanged. That is
what makes the byte-for-byte claim true rather than true-modulo-normalisation: a reader that parsed
`129.50` into a `Float64` could not write it back, and one that decoded `\n` into a newline could
not either (`(:p 129.50)` writes back as `(:p 129.50)`). Decoded values are available separately:
`asn.asl` exports `asnIntValue`, `asnFloatValue` and `asnStringValue` for exactly that.

## 11. Error codes

A decoder reports failures by code. The complete set this document defines:

| Code | Raised when |
|---|---|
| `parse` | The text is not a well-formed document under §3. |
| `map-duplicate-key` | A map repeats a key. |
| `record-duplicate-key` | A record repeats a key. |
| `pool-kind` | `:pool` names something that is not a vector. |
| `ref-shape` | A `:ref` record carries another key, or a non-integer index. |
| `ref-dangling` | A `:ref` index falls outside its pool. |
| `ref-no-pool` | A `:ref` appears with no enclosing pool. |
| `ref-cycle` | Resolution would not terminate, in a decoder whose target cannot hold a cycle. |
| `table-ragged` | A table row's length differs from the header's. |
| `table-duplicate-column` | A table header repeats a column keyword. |
| `table-missing-column` | A consumer's non-defaulted field has no column. |
| `row-override-place` | A row's override record is not its last element. |
| `row-override-multi` | A row carries more than one override record. |
| `row-override-unknown` | An override names a field the schema does not declare. |
| `row-override-duplicate` | An override names a field a positional element already filled. |
| `row-missing-field` | A short row leaves a non-defaulted field unfilled. |
| `row-too-long` | A row has more elements than the schema has fields, and no override. |
| `nil-at-required-field` | `_` at a column whose field is not an `(Option T)`. |
| `unknown-schema` | A `row-group` head names a schema the decoder does not hold. |
| `envelope-data-kind` | An envelope's `:data` is not a vector, row group, or table. |
| `envelope-scalar-element` | An envelope would merge a shared field into a scalar element. |

What is implemented: `asnRead` raises `parse`, and
`asl/packages/asl-transpile/src/core/asnCheck.asl` raises the ten schema-free codes —
`map-duplicate-key`, `record-duplicate-key`, `pool-kind`, `ref-shape`, `ref-dangling`,
`ref-no-pool`, `table-ragged`, `table-duplicate-column`, `envelope-data-kind`,
`envelope-scalar-element`. Each fixture in `asl/grammar/corpus/asn/semantic/` draws exactly the
code it is named for (asl-core run, 2026-09-24).

Target: the schema-directed codes — `row-*`, `nil-at-required-field`, `unknown-schema`,
`table-missing-column` — and `ref-cycle`. They are normative here; no code raises them yet,
because schema-directed materialisation and reference resolution do not exist.

## 12. What ASN deliberately does not define

### 12.1 Streaming chunks and error frames — the protocol's

`(:chunk …)`, `(:end …)` and error frames are **framing**, and framing is
`asl/docs/agenticProtocol.md`'s. ASN defines what one balanced value is; the protocol defines how a
sequence of them is delimited, what a chunk boundary means, and what a failure frame carries.

The self-contained-chunk property still holds, and it holds *because* of §2: every ASN document is
balanced, so a stream severed mid-flight leaves every document that already arrived readable. That
is a consequence of the value grammar, not a construct in it.

`(:chunk (Item [1 "ok"] [2 "ok"]))` is a perfectly ordinary ASN record whose key happens to be
`:chunk`. ASN gives it no meaning; the protocol does.

### 12.2 Raw strings `#"""…"""#` — rejected

`#` is not a character Core §2 produces anywhere. A raw-string form needs a new
lexeme, and a new lexeme in a data format that claims to share the language's lexer is a fork of
that lexer.

Multi-line text uses Core §2's escapes:

```asn
(:lang :python
 :body "def query_users(db):\n    cursor = db.cursor()\n    cursor.execute('SELECT \"id\" FROM users')\n    return cursor.fetchall()")
```

or a vector of lines, which a consumer joins:

```asn
(:lang :python
 :body ["def query_users(db):"
        "    cursor = db.cursor()"
        "    cursor.execute('SELECT \"id\" FROM users')"
        "    return cursor.fetchall()"])
```

The claim a raw string was carrying — that escapes cost tokens or confuse tokenizers — was never
measured. If someone measures it and it pays, the change belongs in Core §2 as a
language-wide lexeme, and ASN inherits it for free. It does not belong here first.

### 12.3 Wire verbs `!`, `?`, `~` — not ASN

The frame heads `asl/docs/agenticProtocol.md` §3 writes as `(! …)`, `(? …)` and `(~ …)` are not ASN
values and this grammar rejects them (`(! :a 1)` is a `parse` error). A frame's *payload* is ASN; the frame itself is the
protocol's. An offload pointer, for instance, is an ordinary record:

```asn
(:offload "scrape-9481"
 :summary "Extracted 42 product items. Status 200. Zero parse errors."
 :sizeBytes 54200
 :sample [(:sku "A1" :price 24.50) (:sku "A2" :price 12.00)])
```

Those three characters are also not producible by Core §2's lexer, which is a problem
`asl/docs/agenticProtocol.md` has to resolve for itself. ASN neither creates nor inherits it.

### 12.4 Schema mixins `:use`

`(:use AuditMeta)` inside a `schema` is a **language** proposal and belongs to Core, not here. ASN describes payloads; how a schema is composed is invisible to a
payload, which sees only the resulting field list in declaration order.

## 13. `:dflt` is not a spelling of `:default`

`:default` has no compact alias, on the grounds that it is already short enough. The measurement
agrees, and it is not close: measured in context — after a space, as a document actually contains
it — ` :dflt` costs **more** than ` :default`, three tokens against two (cl100k_base via tiktoken,
2026-09-24; `asl/bench/asn_tokens.lock` records `ctx:dflt` 3 and `ctx:default` 2, and a tie of 2
each in isolation). The abbreviation is not merely a wash, it is a regression.

Therefore:

- The language option is `:default`. Every document says `:default`.
- In ASN, `:dflt` is an ordinary data key, exactly like `:frobnicate`. The format assigns it no
  meaning, and §7's table default comes from the schema's `:default`.

## 14. Conformance

An ASN document is well-formed iff:

1. It is exactly one value, balanced, under §3's grammar.
2. Every token is Core §2's, with `_` admitted in value position.
3. No map or record repeats a key.
4. Every `:pool` names a vector; every `:ref` is a single-key record over a non-negative integer
   that resolves inside an enclosing pool.
5. Every table is rectangular and its header has no duplicate column.
6. Every envelope's `:data` is a vector, a row group, or a table, and no shared field would merge
   into a scalar element.

Rules 3–6 are **semantic**, not context-free. `asnRead` decides rules 1 and 2;
`asnCheck` decides 3–6. `asl/grammar/corpus/asn/semantic/` holds a fixture for each code they
cover, named for the code it violates, and each draws that code and no other. No suite asserts
this yet: a corpus test that fails a fixture rejected for the wrong reason is a target.

The list is necessary, not sufficient, and it is deliberately the **schema-free** half. Every
`row-*` rule in §6, `nil-at-required-field`, `unknown-schema` and `table-missing-column` need a
schema to decide — whether a record inside a row is an override or an ordinary positional value is
a question only the field count answers — so they are normative here and enforced where a decoder
holds a schema, not by a text-only check that would have to guess.

## 15. Gates

```bash
./bin/asl test asl/packages/asl-transpile/tests/asnDriver.asl   # reader and writer: 2 assertions
```

This runs on asl-core, which is lenient. The stage-0 host does not load the reader yet:
`asl/host/out/asl-host test` on the same file stops at `asl-text/src/text.asl`, which calls
`listTake`, a name the host does not bind (`ERR_UNKNOWN_SYMBOL listTake`).

Target: one suite that reads every fixture under `asl/grammar/corpus/asn/` — each `valid/` file
reads and round-trips, each `invalid/` file is a `parse` error, each `semantic/` file draws its
named code — and runs on the host. Today two `valid/` fixtures do not read: `12-case-values.asn`
writes the camelCase head `deployEvent`, and `empty.asn` holds `(:emptyDoc)`, a keyword with no
value.
