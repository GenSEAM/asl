# SPEC_REVIEW.md — Critique of `AGENT_SPEC.md` (AgentS DSL)

Reviewed document: [`AGENT_SPEC.md`](AGENT_SPEC.md), as supplied.
Targets in scope: TypeScript/Node (React, Vue), Python, Go, Rust. C99 out of scope except
where a finding is C-fatal.
Findings that may legitimately live in the companion `SPECIFICATION.md` (RFC-001 v2.0),
which was not available, are tagged `[may-be-in-RFC-001]`.

---

## 1. Verdict

`AGENT_SPEC.md` is a **style guide presented as a language specification**. Its stated purpose
(§1) is to make an LLM emit deterministic, transpilable AgentS. That requires the document to be
*closed*: an LLM can only be reliable about forms the document actually defines. It is not closed.

Twenty-four identifiers appear in the spec's own examples without ever being defined by it —
including `let`, `if`, `fn`, `ok`, `err`, `get`, `set!`, and the type `SearchResponse`
(§7 tabulates all of them). The document defines four `def*` forms and eight meta-library
functions; everything holding those examples together is assumed.

Two consequences, in order of severity:

1. **Real programs cannot be written.** Of four minimal programs attempted below using only
   spec-defined forms, three become unwritable within five lines. The fourth is writable but
   its behavior is unspecified.
2. **The spec contradicts itself in five places**, so two generators can both be "compliant"
   and disagree. C3 in particular gives one syntax two meanings.

None of this is fatal to the project. The architecture is sound (§8) and the gaps are additive
rather than structural — the fixes in §9 are mostly *writing down* decisions, not redesigning.
But as it stands the document cannot deliver the determinism its §1 claims, and the §6 checklist
asks the model to compensate for that by trying harder.

**Every Tier 1 and Tier 2 fix has a shipped precedent** (§11). Clojure solved C3 with a
one-character prefix; Gleam and Rust settled B1's ergonomics; serde and pydantic agree on A2;
MCP standardizes G1's tool schema. Two findings there are load-bearing enough to change plans
rather than just wording:

* **§6.1 is solving the paren problem in the wrong layer.** Grammar-constrained decoding
  *guarantees* balanced delimiters at the token level. Shipping a grammar replaces a prompt rule
  with a hard guarantee, and gives the spec the normative syntax definition it currently lacks.
* **BAML — the closest shipped system to AgentS — does not transpile.** It compiles to bytecode
  and binds four languages to one shared Rust runtime, which is what keeps their behavior
  identical. AgentS's N-native-backends design is strictly harder, and it is exactly where A1,
  A2, A3, G8, and B6 converge. Worth choosing deliberately rather than by default.

### 1.1 Falsification: four minimal programs

The method: attempt each program using **only** forms `AGENT_SPEC.md` defines, and record the
exact line where it becomes unwritable.

**Program 1 — fetch and parse.** Get a URL, parse JSON into a schema, return a `Result`.

<!-- not-agentscript: quoted from the superseded v0 draft this document critiques -->
```lisp
(defschema User
  (:field id   Int    "User id")
  (:field name String "Display name"))

(defun fetch-user (url String) -> (Result User String)
  (let ((resp (http:get url)))
    ;; resp : (Result HttpResponse String)
    ;; ⛔ STOP. No form exists to branch on a Result.
```

Stops at the first line that touches I/O. §4.1 hands back `Result[HttpResponse, String]`; the
spec defines `ok` and `err` as constructors (§3.2) and nothing that eliminates them — no `match`,
no `case`, no `?`/try, no bind. `if` cannot help: it takes a boolean, and no predicate on `Result`
is defined either. **→ B1.**

Two further walls sit behind this one. `HttpResponse` is referenced by §4.1 and never given
fields, so the response body is unreachable even after a successful branch (**B7**). And
`json:parse` returns another `Result`, so the function needs two eliminations and a way to
map the error — of which the spec defines zero (**B1** again, **G6**).

**Program 2 — agent with a tool.** The use case §3.3 is titled after.

<!-- not-agentscript: quoted from the superseded v0 draft this document critiques -->
```lisp
(defschema WeatherQuery (:field city    String "City name"))
(defschema WeatherReply (:field summary String "Forecast summary"))

(defagent WeatherAgent
  :description "Answers weather questions"
  :input  WeatherQuery
  :output WeatherReply
  :body
  ;; ⛔ STOP. No form declares a tool; no key attaches one to an agent.
```

Stops before the body's first line. §3.3 is headed "autonomous **tool calling**" and the spec
contains no `deftool`, no `:tools` key, no iteration cap, and no result-handling loop.
**→ G1.**

Even the degenerate tool-free version does not survive: `agent:call-llm` has no declared return
type (§3.3 binds its result directly, implying bare `T`), so failure is unhandleable (**C1**),
and nothing in the spec can construct a `WeatherReply` to return (**B2**).

**Program 3 — dynamic list UI.** Render `(List Item)` with a computed total.

<!-- not-agentscript: quoted from the superseded v0 draft this document critiques -->
```lisp
(defschema Item
  (:field label String "Row label")
  (:field count Int    "Row count"))

(defschema CartProps (:field items (List Item)))

(defui Cart [props CartProps]
  (let ((items (signal (.items props))))
    (ui:div {:class "cart"}
      ;; ⛔ STOP. No iteration form; no keyed-list form.
```

Stops at the first dynamic child. No `map`, `for`, `ui:for`, or recursion is defined, and
`(List Item)` has no elimination form (**B5**). The computed total is separately blocked:
§3.4's prose names `computed` and `effect`, and the document never gives either a syntax
(**G2**). Keys for list reconciliation are not mentioned at all (**G3**).

**Program 4 — JSON round-trip.** The only one of the four that is writable:

<!-- not-agentscript: quoted from the superseded v0 draft this document critiques -->
```lisp
(defschema SearchRequest
  (:field query       String "The prompt query string")
  (:field max-results Int    "Maximum search items" :default 5))

(defun round-trip (req SearchRequest) -> (Result SearchRequest String)
  (json:parse SearchRequest (json:stringify req)))
```

This parses and type-checks against §4.2. It is also **semantically undefined**: the spec never
says whether the intermediate JSON is `{"max-results":5}`, `{"maxResults":5}`, or
`{"max_results":5}` (**A2**). So the one writable program is the one whose observable behavior
cannot be predicted — and that same unknown decides whether §3.3's `:response-schema` interops
with any provider's structured-output API.

**Result: 3 of 4 unwritable, 1 of 4 unspecified.**

---

## 2. Contradictions

The spec disagreeing with itself is worse than the spec being silent: silence prompts a question,
contradiction produces confident divergence.

**C1 — "always `Result`" vs. the LLM call.**
§6.2 requires *every fallible I/O operation* to return `Result[T, E]`. §3.3's canonical example
binds `agent:call-llm` straight to `results` and passes it to `agent:respond`, so it returns a
bare `SearchResponse`. The single most failure-prone call in an agent language (network, rate
limits, refusals, schema-validation failure, truncation) is the one that violates the rule,
demonstrated in the document's own showcase example. Models weight examples over prose; expect
generated code to skip error handling on exactly the call that needs it most.

**C2 — "no native leaks" vs. unrestricted FFI.**
§6.5 says to use meta-libraries "unless wrapped in `if-target`". §5.1 introduces
`(.method-name object arg1 arg2)` as a general native method call with no wrapper requirement
and no restriction on where it may appear. One rule forbids what the other grants.

**C3 — field access and FFI share a syntax.** *(worst single defect)*
§3.2 reads a schema field as `(.query req)`. §5.1 defines `(.method-name obj args)` as a native
FFI method call. Identical surface syntax, two completely different semantics, disambiguated
only by whether the receiver is an AgentS record or a foreign object — which is undecidable
when the receiver's type is itself foreign or inferred. Consequences:

* The generator cannot tell you which one it meant, so neither can a reader.
* An LLM will produce `(.trim s)` intending a string method and `(.name user)` intending a field
  read, with no marker distinguishing them.
* A zero-arg FFI method and a field read are *textually identical*. `(.close handle)` is
  unresolvable.

**C4 — two parameter-list syntaxes.**
`defun` binds parameters as a list: `(defun process-query (req SearchRequest) ...)`.
`defui` binds them as a vector: `(defui Counter [props CounterProps] ...)`. Same concept, two
bracket types, no rule stating when each applies. A model asked to write `defagent` with
explicit params has no basis to choose.

**C5 — two conventions for "keys".**
§2.3 assigns `kebab-case` to "field keys" *and* `:keywords` to "map keys". `defschema` then
declares fields as bare symbols (`max-results`), while UI attribute maps use keywords
(`:class`). Whether a schema field is a symbol or a keyword — and what a map key is when the
map represents a record — is never settled. This propagates directly into A2 (wire casing).

---

## 3. Blockers

A blocker means a class of real program cannot be expressed at all.

**B1 — `Result` cannot be consumed.** No `match`, `case`, `cond`, destructuring bind, `?`
operator, `unwrap-or`, `map-err`, or monadic `do`. `ok`/`err` construct; nothing eliminates.
Combined with §6.2's mandate that all I/O return `Result`, **the spec requires every I/O value
to be in a form the language cannot read.** This is the highest-priority fix in the document.

**B2 — Schema values cannot be constructed.** `defschema` declares record types; no literal,
constructor call, or builder form is defined. The only `SearchResponse` in the spec materializes
from `agent:call-llm :response-schema`. A `defun` declared `-> SearchResponse` has no way to
produce its return value. Records are read-only types with no introduction form.

**B3 — `Option` is type-only.** Appears in a field type (§3.1) with no `some`/`none`
constructors and no eliminator. `filters` in `SearchRequest` can be declared and never set or read.

**B4 — No modules, imports, or namespaces.** Every example is a single top-level file.
`meta:http` and friends arrive via an implicit prelude the spec never describes. There is no way
to reference a schema defined in another file, no visibility rules, and no compilation-unit
concept. Multi-file projects are outside the language. `[may-be-in-RFC-001]`

**B5 — No iteration and no collection introduction.** No `map`/`filter`/`fold`/`for`/`while`,
no recursion guidance, no list or map literal semantics. §2.1 admits `[...]` and `{...}` as
grammar productions, but they are only ever used as a parameter vector and an attribute map —
never as values with types. `(List String)` is a type inhabited by nothing.

**B6 — No mutability or ownership model.** §1 promises "memory-safe" output; the document
contains no statement about whether bindings are mutable, whether values are copied or shared,
or who owns what. Rust codegen cannot be deterministic without this — every non-trivial function
forces an arbitrary choice among move, `&`, `&mut`, and `.clone()`, and that choice is
observable in the API. C99 is unimplementable outright (no allocation or lifetime story at all).
`[may-be-in-RFC-001]`

**B7 — `HttpResponse` is undefined.** §4.1 returns it; no `defschema` or field list is given.
Status code, headers, and body are all unreachable, so `meta:http` cannot actually be used even
once B1 is fixed.

---

## 4. Ambiguities

Two defensible readings ⇒ two different valid outputs ⇒ the determinism claim in §1 fails.

**A1 — Identifier mangling is unspecified.** `fetch-user-data` must become `fetchUserData`
(TS), `fetch_user_data` (Python), and `FetchUserData` or `fetchUserData` in Go depending on
export intent — which the spec has no way to express. No algorithm, no export rule, no
collision policy: `fetch-user`, `fetch_user`, and `fetchUser` are three distinct AgentS
identifiers that can mangle to one target identifier. Also unhandled: leading digits,
target keyword collisions (`type`, `func`, `match`, `class`), and acronym casing
(`parse-html-url`).

**A2 — Wire-format key casing is unspecified.** Does `json:stringify` emit `max-results`,
`maxResults`, or `max_results`? This is externally observable, breaks compatibility silently,
and gates §3.3's `:response-schema` — provider structured-output APIs will validate against
whichever casing the schema declares. Needs a normative rule plus a per-field override
(e.g. `:json "maxResults"`).

**A3 — Numeric types are unspecified.** `Int` maps to Rust `i32`/`i64`, Go `int` (platform-width),
JS `number` (exact to 2^53), Python arbitrary precision. Same program, four different overflow
behaviors. No `Float`, `Decimal`, or `Bool` type is listed anywhere despite `if` requiring a
boolean and `:default 0` implying numeric literals.

**A4 — UI attribute map vs. first child.** `(ui:div {…} kids…)` has attributes; `(ui:h2 (str …))`
does not. The parser must decide positionally whether argument 1 is an attribute map or a child,
which is fine until a child *is* a map — at which point the form is unresolvable. Needs either a
mandatory (possibly empty) attribute map, or an explicit marker.

The spec also disagrees with itself here: §6.3 gives the canonical form as
`(ui:tag {:attr val} ...)`, with the attribute map present, while §3.4's example writes
`(ui:h2 (str "Count: " (get count)))` without one. Adopting §6.3's form as normative resolves
the ambiguity outright, at the cost of some `{}` noise.

**A5 — `set!` is overloaded.** In §3.4 it writes a signal. In every Lisp tradition it mutates a
variable binding. Its meaning on a plain `let` binding is undefined, and whether `let` bindings
are immutable is never stated. Related: `get` is used as the signal read, but `get` is also the
conventional name for map/collection lookup — a collision waiting for B5 to be fixed.

**A6 — `let` semantics.** Sequential (`let*`) or parallel (`let`)? Recursive? Every example has
exactly one binding, so the document never reveals which. Shadowing rules absent.

**A7 — `if` totality.** Is `(if cond then)` legal with no else? If so, what is its type and
value? When both branches are present, how are differing branch types unified? Unspecified.

**A8 — `if-target` exhaustiveness.** §5.2 lists all five targets in its only example. Must all
be present? If a program compiles to Go and only `:python` and `:js` arms exist, is that a
compile error or a silent no-op? No `:else`/default arm exists. A silent no-op would let an
`if-target` block vanish from a build without any diagnostic.

**A9 — `->` in `defun`.** The return-type arrow appears in §3.2's example and is never described
in §2.1's grammar, which admits only atoms, lists, vectors, and maps. Is `->` an atom in the
parameter position, or dedicated syntax? A model writing a multi-clause or zero-arg `defun` has
no template.

---

## 5. Gaps

Absent rather than wrong. These do not contradict anything; they are simply not there.

**G1 — `defagent` is the thinnest and most consequential section.** Missing: any tool
declaration form (`deftool`), any way to attach tools to an agent (`:tools`), iteration/step
limits, stop conditions, streaming, temperature/max-tokens/timeout, retry policy, credential
sourcing, conversation state or memory, and multi-turn structure. Additionally:

* `input` is used in `(.query input)` and is **never bound** — `defagent` magically injects a
  name that `defun` requires you to declare. Inconsistent, and the injected name is undocumented.
* `agent:respond` is undefined as return-vs-emit. May it be called twice? Mid-body? Is code
  after it reachable?
* `agent:call-llm`'s return type is never stated (see C1).

For a language whose first-class construct is the agent, this section defines a name and four
keyword arguments.

**G2 — `computed` and `effect` have no syntax.** Named in §3.4's prose ("Use `defui` with
`signal`, `computed`, and `effect`"), never shown. Cleanup/teardown for `effect`, and dependency
tracking for both, are likewise absent.

**G3 — React/Vue divergence is unaddressed.** §3.4 claims one `defui` yields both. Specifically
missing:
* React has no native signal primitive; lowering requires `useState`, `useSyncExternalStore`, or
  a signals library — a decision with real API consequences that the spec does not make.
* `(signal …)` inside a conditional or loop violates the Rules of Hooks. Nothing states where
  signals may be declared.
* No attribute mapping table: `:class` → `className` (React) vs `class` (Vue), `:on-click` →
  `onClick` vs `@click`, plus `:for`/`htmlFor`, `:style` (string vs object), boolean attributes,
  and `:key`.
* No event-handler payload type — `(fn () …)` takes zero arguments in the example, so reading
  `event.target.value` has no expression.
* Keyed lists: unaddressed (see B5).
* Component composition is never shown. Can `Counter` be used inside another `defui`? Presumably
  `(Counter {:initial-count 3})`, but PascalCase in call position is nowhere specified, and it
  collides visually with C3's dot-call and A4's attribute map.
* Children/slots, fragments, and conditional rendering: absent.

**G4 — `*:exec` takes an unstructured source string.** `(py:exec "import os; …")` accepts raw
foreign source with no type, no result binding, no declared effects, and no interpolation rules.
The spec's own Rust arm already needs `\"` escaping inside the DSL string, and any interpolation
of AgentS values into that string is an injection hazard at the codegen boundary with no escaping
contract. There is also no way to *return* a value from an `if-target` arm into surrounding code,
which makes the construct nearly useless for anything but side effects.

**G5 — Missing language basics.** Each of these is used or implied by the spec and never defined:

| Missing | Evidence it is needed |
|---|---|
| Comment syntax | §6.4 says to omit "redundant prose comments *inside code blocks*" |
| `Bool`, `Float`, `Unit`/`Nil`, `Char`, `Bytes`, `Map`, `Any` | `if` needs Bool; `:default 0` implies numeric literals |
| String escapes, multiline strings | §5.2 already escapes `\"` and `\\n` inside a DSL string |
| Arithmetic and comparison operators | `+` used in §3.4, defined nowhere |
| Equality / structural comparison | required by any real predicate |
| `meta:string` | `string:empty?` used in §3.2; §4 documents only http/json/async |
| `cond`, `case`, `when`, `unless` | `if` alone forces deep nesting, which is L1's failure mode |
| Type aliases, generics, user-defined sum types | without them `Result`/`Option` are unextendable magic |
| Truthiness rules | is `(if "" …)` false? empty list? `none`? |

**G6 — Errors are stringly-typed.** §4.1/§4.2 fix `E = String`. Callers cannot distinguish a
404 from a DNS failure from a JSON syntax error without parsing prose. This forecloses error
matching, produces non-idiomatic Rust (`Box<dyn Error>` at best, never a real error enum) and
non-idiomatic Go, and makes retry logic — table stakes for an agent language — unwritable.

**G7 — `:default` × `Option` interaction.** Is a field with `:default` optional at construction?
Is `(Option T)` with a default coherent? Does a default apply on deserialization when the key is
absent, or only at construction? Three separate unanswered questions, all wire-visible.

**G8 — `meta:async` ignores function coloring.** `async:spawn`/`channel`/`send`/`recv` map almost
directly onto Go. In TS and Python, async-ness propagates through every transitive caller, so the
spec must state whether *all* generated functions are async, whether coloring is inferred, or
whether a runtime is bundled. Rust additionally needs a chosen executor (tokio/async-std) and a
channel type (`mpsc`/`crossbeam`/`tokio::sync`). None of the four decisions is made. No return
types are given for any of the four functions, and `async:recv` on a closed channel is undefined.

**G9 — No evaluation-order or effect guarantees.** Argument evaluation order, short-circuiting of
any future `and`/`or`, and whether the compiler may reorder or elide pure calls are unstated —
all four targets differ in what is observable.

---

## 6. Per-target lowering

What each construct should become, and the spec fact missing to get there.

| Construct | TS/Node | Python | Go | Rust | Blocking unknown |
|---|---|---|---|---|---|
| `defschema` | `interface` + zod schema | `@dataclass` / pydantic | `struct` + tags | `struct` + serde | A1 casing, A2 wire keys, A3 widths, G7 defaults |
| `Result`/`Option` | discriminated union | `Result` class / `\|None` | `(T, error)` tuple | `Result`/`Option` | **B1** (no eliminator), G6 (error type) |
| `defun` | `function` | `def` | `func` | `fn` | A1 mangling, A9 arrow, B6 ownership |
| `defagent` | SDK client call | SDK client call | SDK client call | SDK client call | **G1** (no tool form), C1 (no Result) |
| `defui` | React / Vue SFC | — | — | — | **G2**, G3, A4, B5 |
| `meta:async` | Promise + async | asyncio | goroutine + chan | tokio + mpsc | **G8** (coloring, runtime, channel type) |
| FFI dot-call | `obj.m()` | `obj.m()` | `obj.M()` | `obj.m()` | **C3** (field vs method), G4 |

**Rust** is the least served target. B6 alone blocks it: without a mutability/ownership model,
every function signature is a coin flip between `T`, `&T`, and `&mut T`, and the generator will
default to `.clone()` everywhere — which contradicts the reason to target Rust. A3 forces an
arbitrary integer width into every schema, and G6 means idiomatic `thiserror` enums are
impossible. G8 requires picking an executor the spec does not name.

**Go** is closest to a clean lowering (channels are native, structs are native), and is blocked
mostly on naming: A1 becomes load-bearing because capitalization *is* visibility, and the spec
has no export annotation. G6 is a smaller problem here (`errors.New` is idiomatic) but
`errors.Is`/`As` remain unreachable.

**TypeScript/Node** is the most natural fit for `defschema` and `defui`, and the most exposed to
G8 (async coloring across every caller) and G3 (React has no signals). A3's 2^53 limit needs an
explicit `Int64` → `bigint` decision.

**Python** is the easiest target for `defagent` and the hardest for `defui` (no row in the table
— the spec claims React/Vue only, leaving Python UI undefined rather than excluded). G8 applies
as in TS.

**C99** *(out of scope, noted)*: B6 makes it unimplementable — no allocator story, no lifetime
story, no closure representation for `(fn () …)` in §3.4, and `defui`'s reactivity has no
plausible C lowering. Recommend dropping C from §1 or moving it behind an explicit
"no-`defui`, no-closures" subset.

---

## 7. Closure audit

Every identifier appearing in `AGENT_SPEC.md`'s examples, classified. This is the mechanical
substantiation of §1's "not closed" verdict.

**Defined by the document (12):** `defschema`, `:field`, `:default`, `defun`, `defagent`,
`:description`, `:input`, `:output`, `:body`, `defui`, `if-target`, and the `ui:*` family as a
*pattern* (§6.3) — though no tag list, attribute set, or return type is given.

**Meta-library functions with a stated signature (4):** `http:get`, `http:post`,
`json:stringify`, `json:parse`.

**Meta-library functions with no return type (4):** `async:spawn`, `async:channel`,
`async:send`, `async:recv`.

**Used in examples, never defined (24 identifiers, in 21 rows):**

| Identifier | Where used | Kind |
|---|---|---|
| `let` | §3.2, §3.3, §3.4 | binding form |
| `if` | §3.2 | conditional |
| `fn` | §3.4 | lambda |
| `str` | §3.2, §3.4 | string builder |
| `ok` | §3.2 | Result constructor |
| `err` | §3.2 | Result constructor |
| `get` | §3.4 | signal read |
| `set!` | §3.4 | signal write |
| `+` | §3.4 | arithmetic |
| `signal` | §3.4 | reactive primitive |
| `computed` | §3.4 prose | reactive primitive |
| `effect` | §3.4 prose | reactive primitive |
| `string:empty?` | §3.2 | undocumented `meta:string` |
| `agent:call-llm` | §3.3 | no return type |
| `agent:respond` | §3.3 | no semantics |
| `input` | §3.3 | **unbound identifier** |
| `->` | §3.2 | return-type syntax |
| `String`, `Int` | §3.1 | primitive types, never enumerated |
| `Option`, `List`, `Result` | §3.1, §3.2 | type constructors, never defined |
| `SearchResponse` | §3.3 | **type never declared** |
| `HttpResponse` | §4.1 | **type never declared** |

Ratio: 20 defined forms, 24 undefined identifiers — in a document whose entire function is to
be the complete vocabulary an LLM generates from.

*(Note: `SearchComponent` in §2.3 is a naming illustration, not a dangling reference — it is
correctly excluded from this table.)*

---

## 8. What the spec gets right

Worth preserving through any revision:

* **Meta-library indirection (§4)** is the correct architecture for a multi-target compiler.
  Routing I/O through `meta:http`/`meta:json` rather than per-target imports is what makes four
  backends tractable at all.
* **`Result`-typed I/O as the default discipline (§6.2)** is the right call, and unusual to see
  stated up front. It just needs an eliminator (B1) and a real error type (G6).
* **Hyperscript UI over JSX (§6.3)** is right for an S-expression language — embedding an
  XML-ish sublanguage would have doubled the parser and multiplied LLM failure modes.
* **Explicit return types on `defun` (§3.2)** give the type checker an anchor and give the model
  a template to fill.
* **`if-target` as a scoped escape hatch (§5.2)** is better than unrestricted inline native code —
  the escape is at least visible and greppable. (It needs G4's semantics and A8's exhaustiveness
  rule to be usable.)
* **The three-way naming convention (§2.3)** is legible and gives the model a clear signal for
  which namespace a symbol belongs to — once mangling is pinned (A1) and C5 is resolved.

---

## 9. Recommendations

Ordered by reliability gained per unit of effort.

### Tier 1 — cheap, and each removes a whole failure class

1. **Split field access from FFI (C3).** Adopt Clojure's `.-` prefix: `(.-field record)` for
   schema access, `(.method obj args…)` for FFI. One grammar line, fifteen years of production
   evidence, and it fixes the silent field-loses-to-method shadowing Clojure documents
   explicitly — see §11.1.
2. **Add a `Result`/`Option` eliminator (B1, B3).** Minimum viable: `match` with `ok`/`err`/
   `some`/`none` patterns, **plus** a propagation form (Gleam's `use`, Rust's `?`) so the common
   path does not nest — §11.2. Without this the language cannot do I/O; with it, most of §4
   becomes usable. Shipping `match` alone recreates the deep nesting that causes L1.
3. **Add a record constructor (B2).** e.g. `(SearchRequest :query "x" :max-results 5)` with
   defaults applied. One form; unblocks every function that returns a schema.
4. **Pin naming and wire format normatively (A1, A2, A3, C5).** A table: AgentS identifier →
   TS/Python/Go/Rust identifier, plus the JSON key rule with a per-field `:json` override, plus
   fixed-width numeric types (`Int32`/`Int64`/`Float64`) with `Int` as a documented alias.
   Copy the shape serde and pydantic both converged on — container-level default plus per-field
   override (§11.5) — and reserve a compiler-internal identifier prefix now, as Haxe does
   (§11.8). Pure writing; kills four ambiguities and makes output byte-reproducible.
5. **Add a closed-vocabulary appendix (§7, L5).** Every builtin, with its type signature, in one
   table — including `let`, `if`, `fn`, `str`, `ok`, `err`, `match`, and the primitive types.
   This is the **single highest-value change for LLM reliability**: it converts the document from
   a style guide into a vocabulary, which is what an injected system prompt needs to be.
6. **Declare `HttpResponse` (B7)** as a `defschema` in §4.1, and version the document (L6);
   rename the header to match the filename.

### Tier 2 — moderate, and unblock the headline use cases

7. **Specify `defagent` properly (G1, C1).** `deftool` + `:tools` + `:max-iterations` +
   `:on-error`; declare `agent:call-llm -> (Result T LlmError)`; bind `input` explicitly in the
   signature the way `defun` does; define `agent:respond` as a tail return. Compile `deftool` to
   **JSON Schema** and both major provider APIs plus MCP servers come for free (§11.7); make
   `:max-iterations` required-with-a-default, since an uncapped agent loop is a safety defect
   rather than a missing tuning knob.
8. **Specify reactivity (G2, G3, A4, B5-for-UI).** Syntax for `computed`/`effect` with teardown;
   a keyed `ui:for`; a normative attribute-mapping table for React and Vue; a rule that the
   attribute map is mandatory (possibly empty) to resolve A4; a statement on component
   composition and on where `signal` may legally appear.
9. **Introduce a structured error type (G6).** Let `defschema`-style error enums be user-defined
   and let meta-libraries return them; this is what makes Rust and Go output idiomatic.
10. **Add iteration and collection literals (B5).** `map`/`filter`/`fold` plus list/map literal
    syntax and types for the `[...]`/`{...}` productions §2.1 already admits.
11. **Add negative examples and a canonical format (L3, L4).** A short "never write this" section
    — models anchor hard on shown forms, and the absence of counterexamples is a known reliability
    gap. Plus one indentation/line-breaking rule so few-shot examples and diffs stay stable.

### Tier 3 — design work, needed before the harder targets ship

12. **Mutability and ownership model (B6).** Gate the Rust backend behind this; consider marking
    Rust and C as experimental in §1 until it exists.
13. **Async coloring strategy (G8).** Decide between the three known answers — colorblind
    inference (Zig), algebraic effects (Koka), or explicit `defun-async` — per §11.6. Name the
    Rust executor and channel type.
14. **Modules and imports (B4).**
15. **Diagnostic contract (L2).** A machine-readable error format the compiler returns for the
    LLM repair loop — arguably the most important *toolchain* feature for a spec whose purpose is
    LLM codegen, and currently absent from both the spec and the workflow it implies.

### On §6.1 (L1)

"Verify delimiter counts before emitting output" instructs the model to do the one thing it
demonstrably cannot self-execute — closing-paren errors at nesting depth >4 are the dominant
failure mode for LLM-generated Lisp, and asking for vigilance does not reduce them.

The mechanism that actually delivers balanced delimiters is **grammar-constrained decoding**: a
context-free grammar compiled to a pushdown automaton tracks nesting depth and restricts the
next-token distribution to tokens that keep the output valid, so balance is guaranteed by
construction rather than checked afterward (§11.4). **Ship a GBNF-style grammar for AgentS** —
it makes §6.1 unnecessary on any grammar-capable runtime *and* doubles as the normative syntax
definition the document currently lacks (§7). Where grammar constraints are unavailable, use a
repair-tolerant parser on BAML's Schema-Aligned Parsing model, not a sterner prompt.

Either way this is a toolchain change, not a prompt change. Then reduce §6.1 to a formatting rule.
Fixes 2 and 11 above (a propagation operator and `cond`) attack the root cause from the other
side by reducing nesting depth directly.

### On §3.3's hardcoded model

The canonical example pins a specific provider and model string. Models copy canonical examples
verbatim, so that pair will propagate into generated code long after it is current. Source the
model from configuration in the example, or use an obvious placeholder.

---

## 10. Summary table

| ID | Finding | Severity |
|---|---|---|
| C3 | Field access and FFI share one syntax | Contradiction / blocking |
| B1 | `Result` has no eliminator | Blocker |
| B2 | Schema values cannot be constructed | Blocker |
| G1 | `defagent` has no tool-calling form | Gap / blocking |
| B5 | No iteration or collection values | Blocker |
| B6 | No mutability/ownership model | Blocker (Rust, C) |
| C1 | `agent:call-llm` violates the all-`Result` rule | Contradiction |
| B7 | `HttpResponse` undefined | Blocker |
| B3 | `Option` is type-only | Blocker |
| B4 | No modules | Blocker |
| A1/A2/A3 | Mangling, wire casing, numeric widths unspecified | Ambiguity |
| G2/G3 | Reactivity and React/Vue divergence unspecified | Gap |
| G6 | Stringly-typed errors | Gap |
| G8 | Async coloring unaddressed | Gap |
| C2/C4/C5 | FFI wrapper, param brackets, key convention | Contradiction |
| A4–A9 | UI attrs, `set!`, `let`, `if`, `if-target`, `->` | Ambiguity |
| G4/G5/G7/G9 | `*:exec`, language basics, defaults, eval order | Gap |
| L1–L7 | LLM-reliability findings | Process |

---

## 11. Prior art

Every Tier 1 and Tier 2 recommendation in §9 has a shipped precedent. None of these problems is
novel, and three of them have a settled answer that AgentS can adopt more or less verbatim.

### 11.1 C3 — Clojure already solved this, for the same reason

Clojure hit the identical collision: `(.foo obj)` could mean a field read or a zero-argument
method call, and the two are textually indistinguishable. Its resolution is a one-character
prefix, and the rule is normative:

> "If the second operand is a symbol starting with `-`, the member-symbol will resolve only as
> field access (never as a 0-arity method)"

So `(.-x obj)` is unambiguously a field; `(.x obj)` is a method call. Crucially, Clojure also
documents the failure mode AgentS currently has — with the plain `.` form and no arguments,
**method resolution is attempted first**, so a field silently loses to a same-named zero-arg
method. `.-` exists precisely because that silent shadowing was unacceptable. The accessor was
also motivated by aligning Clojure and ClojureScript field lookup, i.e. by *multi-target
consistency* — the same pressure AgentS is under.

**Adopt directly:** `(.-field record)` for schema access, `(.method obj args…)` for FFI. This is
a smaller change than the `ffi:call` form proposed in §9.1, preserves the spec's existing
aesthetics, and comes with fifteen years of evidence that it works.

### 11.2 B1 — `use` / `try` / `?` are the settled ergonomics

Gleam is the closest analogue (small ML-family language, `Result`-typed I/O, compiles to
**two** targets — Erlang and JavaScript — so it faces AgentS's multi-backend constraint):

* `result.try` chains fallible calls, short-circuiting on the first `Error` — "railway-oriented"
  style.
* The `use` expression exists specifically because chained `try` callbacks nest badly; `use`
  flattens them into sequential-looking code.
* Gleam's own community has an open design discussion on adding a `?` operator, which is worth
  reading before AgentS picks a syntax — the tradeoffs are laid out there rather than
  needing rediscovery.

Rust's `?` is the other reference point. Either way the pairing is the same: **a `match`
eliminator for the general case plus a propagation form for the common case.** Shipping only
`match` reproduces the nesting problem that §6.1 (L1) is already struggling with — deep nesting
is the direct cause of unbalanced-paren failures in LLM output, so B1 and L1 are the same bug
seen from two ends.

### 11.3 G1 + architecture — BAML is the closest shipped system

[BAML](https://github.com/BoundaryML/baml) is a DSL for exactly AgentS's `defschema` + `defagent`
scope: typed LLM function interfaces compiled to idiomatic clients in **Python, TypeScript, Ruby,
and Go**, with a Rust compiler. Two things AgentS should take from it, and one warning.

**Take: the pipeline.** BAML's compiler runs seven phases — Lexer → Parser → HIR → TIR (typed IR)
→ VIR (validated IR) → MIR → bytecode. A concrete reference architecture for the separation
AgentS needs between parsing, type checking, validation, and target lowering.

**Take: Schema-Aligned Parsing.** SAP transforms raw LLM text into typed data, tolerating broken
JSON, markdown wrappers, and chain-of-thought preamble, and coercing types — which means it works
against models with no native function-calling API. This is the robust answer to §3.3's
`:response-schema`, and it generalizes: the same tolerance AgentS needs when *parsing
LLM-generated AgentS* (see 11.4).

**Warning: BAML does not transpile.** All four clients bind via FFI to a single shared Rust
runtime, which is what guarantees consistent behavior across languages. AgentS proposes something
strictly harder — **N independent native backends that must be semantically equivalent** — and
that is precisely where A1 (mangling), A2 (wire casing), A3 (numeric widths), G8 (async), and B6
(ownership) all bite at once. Worth deciding deliberately rather than by default: a shared runtime
with thin generated bindings sidesteps most of §4's per-target table, at the cost of the
"native output" promise in §1.

Note also that BAML — a Rust-implemented, well-resourced project — ships **no Rust client**.
That is corroboration for B6: Rust codegen from a higher-level language is the expensive target,
not the free one.

### 11.4 L1 — constrained decoding makes balanced parens a guarantee, not an aspiration

§6.1 asks the model to "verify delimiter counts before emitting output." The mechanism that
actually delivers this operates at the token level: constrained decoding restricts the next-token
distribution to tokens that keep the output valid against a grammar. Because the constraint is
enforced *during* generation rather than checked after, output is guaranteed valid — no parse
errors, no retries, no fallback parser.

For nesting specifically, a context-free grammar compiled to a **pushdown automaton** tracks depth
and enforces balance throughout generation. GBNF (llama.cpp's grammar format) is recursive and can
express exactly this.

**Implication for the project:** AgentS should ship a grammar, not a paragraph of advice. A GBNF
(or equivalent) grammar for AgentS gives balanced delimiters by construction on any
grammar-constrained runtime, and doubles as the normative syntax definition the spec currently
lacks (§7's closure problem). Where constrained decoding is unavailable — hosted APIs without
grammar support — BAML's SAP is the fallback pattern: a repair-tolerant parser, not a stricter
prompt. Either path is a toolchain change; neither is a prompt change.

### 11.5 A2 — wire casing has a conventional answer

Both mainstream ecosystems AgentS targets converged on the same design: a container-level default
plus a per-field override.

* **serde**: `#[serde(rename_all = "camelCase")]` on the struct, `#[serde(rename = "...")]` per
  field.
* **pydantic**: `alias_generator` on the model (with `to_camel`, `to_lower_camel`, `to_pascal`
  helpers), explicit `alias` per field, plus a flag to allow population by field name.

Adopt the shape wholesale: a `:json-case` option on `defschema` defaulting to one documented
convention, and a `:json "..."` override on `:field`. Note the known sharp edge — pydantic has a
reported inconsistency in how `to_camel` treats already-camelCased input — so specify the
transform on the *AgentS* kebab-case identifier only, and define it total.

### 11.6 G8 — function coloring is a known fork with three known answers

Bob Nystrom's "What Color is Your Function?" (2015) is the canonical statement of the problem
AgentS inherits in its TS and Python backends. The three live answers:

1. **Colorblind (Zig).** Infer async-ness; allow `async`/`await` on non-async functions, so
   libraries are agnostic to blocking vs. async I/O. Zig's newer I/O work relocates the color from
   blocking/non-blocking to io/non-io rather than eliminating it — the discourse is worth reading
   before claiming AgentS can avoid coloring entirely.
2. **Algebraic effects (Koka).** Effects in the type signature, handlers supplying semantics, the
   effect propagating outward until handled. The most principled fit for a language that also
   wants to track fallibility (`Result`) and target purity — but it is a research-grade
   commitment, and lowering effect handlers to Go and Rust is hard.
3. **Explicit coloring.** `defun-async`, propagate manually. Cheapest, ugliest, and honest.

The spec currently makes no choice, which means the backends will each make a different one.

### 11.7 G1 — tool schemas and the iteration cap are standardized

MCP's tool model is the reference: a tool is a schema (so the model knows how to call it), an
implementation, and a result format; discovery via `tools/list`, invocation via `tools/call`. The
schema is defined in TypeScript and published as JSON Schema for compatibility, and both major
model families accept JSON Schema tool definitions. Notably, `required` vs. optional materially
changes model behavior — a fact a `deftool` form should expose deliberately rather than
inherit accidentally from `:default` (G7).

On the agent loop itself, a hard `MAX_ITERATIONS` cap is standard practice (commonly ~10) and is
treated as a safety rail, not a tuning knob: without it a confused agent loops indefinitely.
§9.7's `:max-iterations` should therefore be **required with a default**, not optional.

Practical consequence: if `deftool` compiles to JSON Schema, AgentS gets MCP servers and both
major provider APIs for free, and §3.3's `:response-schema` stops being bespoke.

### 11.8 A1 — reserve a namespace before you need it

Haxe (nine-plus targets, the closest analogue to AgentS's ambition) reserves the identifier prefix
`_hx_` for compiler-internal use, and its docs warn that generated variable names may not
correspond to source names — which is exactly why target-specific code injection (AgentS's
`if-target`, G4) is hazardous without a stated mangling contract. Reserve a prefix in the spec now;
retrofitting one after user code exists is a breaking change.

### Sources

- [Clojure — Java Interop reference](https://clojure.org/reference/java_interop)
- [Clojure — Special Forms](https://clojure.org/reference/special_forms)
- [Gleam — Result module (language tour)](https://tour.gleam.run/standard-library/result-module/)
- [Gleam — Introducing use expressions](https://gleam.run/news/v0.25-introducing-use-expressions/)
- [Gleam — discussion: new `?` error-handling operator](https://github.com/gleam-lang/gleam/discussions/3908)
- [BAML — architecture overview (DeepWiki)](https://deepwiki.com/BoundaryML/baml)
- [BAML — getting started (DeepWiki)](https://deepwiki.com/BoundaryML/baml/1.1-getting-started)
- [Constrained decoding: forcing LLM output to a grammar](https://zeroentropy.dev/concepts/constrained-decoding/)
- [A Guide to Structured Outputs Using Constrained Decoding](https://www.aidancooper.co.uk/constrained-decoding/)
- [Flexible and Efficient Grammar-Constrained Decoding (arXiv 2502.05111)](https://arxiv.org/pdf/2502.05111)
- [Serde — field rename attributes](https://serde.rs/attr-rename.html)
- [Pydantic — alias concepts](https://pydantic.dev/docs/validation/latest/concepts/alias/)
- [pydantic#8361 — `to_camel` case-change edge case](https://github.com/pydantic/pydantic/issues/8361)
- [What is Zig's "Colorblind" Async/Await?](https://kristoff.it/blog/zig-colorblind-async-await/)
- [Zig's new I/O: function coloring is inevitable?](https://blog.ivnj.org/post/function-coloring-is-inevitable)
- [Model Context Protocol — schema reference](https://modelcontextprotocol.io/specification/2025-11-25/schema)
- [MCP — tools concept](https://modelcontextprotocol.info/docs/concepts/tools/)
- [Haxe — accessing target-specific syntax](https://haxe.org/manual/target-syntax.html)
- [HaxeFoundation/haxe#4462 — reserved identifier prefix](https://github.com/HaxeFoundation/haxe/issues/4462)
