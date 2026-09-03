# Roadmap & Implementation Plan: Multi-Target ASN (AgentScript Notation) Codec SDKs (`asl-universal-codec-v1`)

**Goal**: Establish **ASN (AgentScript Notation)** as a compact, agent-oriented data serialization
format and wire payload, by specifying it normatively, implementing a reference reader and writer
in pure AgentScript under `packages/asl-codec`, and compiling that one implementation into
zero-dependency client SDKs across TypeScript, Python, Rust, Go and WebAssembly
(@pcp:d-bda8, @pcp:d-b0a9).

## Status: Phase 0 and Phase 1 DONE. Phase 2 next.

**Correction to the stated goal.** This plan opened with "-80% tokens vs JSON/YAML" and "aggressive
key compaction (`:dflt`, `:f`, `:c`)". Both are now measured, and both were wrong:

- Schema-grouped rows save **58%** against pretty-printed JSON at 100 rows of four fields, not 80%.
  `bench/asn_tokens.py`, locked in `bench/asn_tokens.lock`.
- `:dflt` costs exactly what `:default` costs — two tokens each — so it buys nothing and is **not**
  adopted. `:f` and `:c` do pay, and are already in `prelude/prelude.json`'s projection.

The saving is real and worth the project. The number was not, and DESIGN.md §5 makes that the
difference between a design choice and a false claim.

---

### Phase 0: Normative specification (`docs/ASN_SPEC.md`) — **DONE**
- [x] Write `docs/ASN_SPEC.md`, normative for data, layered on `AGENT_SPEC_CORE.md` §2's lexical
      structure rather than defining a second language.
- [x] State the document precedence rule: Core governs the language, ASN_SPEC governs data,
      `docs/AGENTIC_PROTOCOL.md` governs the wire, and the two guides are advisory.
- [x] Settle every construct the guides had asserted: keywords as values, the `_` nil sentinel,
      `:pool` / `:ref` scope and resolution, the envelope merge rule, schema-grouped rows and
      sparse tail overrides, ad-hoc tables, map literals, qualified heads.
- [x] Reject, with a reason, the constructs that cannot be built from Core's lexemes: the `&`
      identity anchor (deleted, not respelled — an anchor is a pool entry), `#"""…"""#` raw
      strings, and the `!` / `?` / `~` frame heads (handed to the protocol document).
- [x] `grammar/asn.lark` — a data grammar with a SHARED TERMINALS block copied from
      `agentscript.lark`, and a drift check that fails when the copy stops being one.
- [x] `grammar/corpus/asn/{valid,invalid,semantic}` — 16 valid, 12 invalid, 10 semantic fixtures,
      one construct or one rule each, in the house style.
- [x] `grammar/validate_asn.py` — corpus verdicts, terminal drift, `; canonical:` / `; expect:`
      header presence, and every ` ```asn ` example in the three ASN documents. ASN payloads are
      fenced ` ```asn `, which `tools/doc_examples.py` ignores by design; the Core declarations in
      those files stay ` ```lisp ` and are graded by that gate. One tag, one parser, so a
      mis-tagged block fails somewhere instead of passing everywhere.
- [x] `bench/asn_tokens.py` + `.lock` — every percentage the documents publish, and the
      abbreviation table, counted under `cl100k_base`.
- [x] Rewrite `docs/DATA_REPRESENTATION_MATRIX.md` (now advisory) and
      `docs/CONTEXT_ECONOMY_GUIDELINES.md` so every example parses and every number is locked.

### Phase 1: Reference reader and writer in pure ASL (`packages/asl-codec`) — **DONE**
- [x] `src/core/asn.asl` — the `AsnValue` algebra, a shift-reduce reader over
      `packages/asl-parser`'s lexer, and a canonical writer. No second S-expression scanner was
      written; `asl-parser`'s `ast.asl` reader was deliberately NOT reused, because it normalises a
      Nano atom to its verbose spelling and an ASN key spelled `:f` must survive as a field called
      `f`.
- [x] Numbers, booleans, strings, keywords, nil, unit, vectors, maps, records, named
      construction, schema-grouped rows, ad-hoc tables, union case values, `(:ref N)`.
- [x] `src/core/asn-check.asl` — the schema-free half of §11's error set: duplicate keys, pool
      kind, reference shape and resolution, table shape, envelope shape.
- [x] Round-trip fidelity: for canonical text *t*, `write(read(t))` is *t* byte for byte. Asserted
      against a hand-written `; canonical:` header on every valid fixture, plus idempotence.
- [x] Two-implementation agreement: `grammar/asn.lark` and the AgentScript reader return the same
      verdict on all 38 fixtures.
- [x] `tests/asn_driver.asl`, `tests/harness.py`, `tests/test_asn.py` — 119 tests.
- [x] Token gate: `bench/asn_tokens.py --check`. It measures what is actually true rather than
      asserting ≥75%, which is a threshold ASN does not meet against pretty-printed JSON on every
      payload shape and never met on a matrix or a short vector.

**Not closed in Phase 1, and specified rather than built:** schema-directed materialisation.
Binding a `row-group` or a `table` to a `defschema` is what decides `row-missing-field`,
`row-too-long`, `nil-at-required-field`, `unknown-schema`, `table-missing-column` and all four
`row-override-*` codes. `docs/ASN_SPEC.md` §6, §7 and §11 define every one of them; none is
implemented, because whether a record inside a row is a sparse override or an ordinary positional
value is a question only the schema's field count answers. It is the first item of Phase 2.

### Phase 2: Schema binding, then multi-target compilation
- [ ] **Schema-directed materialisation** in `packages/asl-codec`: an `AsnSchema` supplied by the
      caller, positional binding in declaration order, `:default` fill, sparse tail overrides, and
      the nine schema-directed codes above. Fixtures for each under
      `grammar/corpus/asn/schema/`.
- [ ] Confirm the single-pass claim as a gate rather than a design note. The grammar already needs
      no backtracking — every parenthesised form is decided by its first token and a row group by
      its second — so the gate is a parser-state assertion, not a rewrite.
- [ ] Compile `packages/asl-codec` through the existing backends into:
  - **TypeScript/JavaScript**: `@genseam/asl-codec`, zero-dependency, ESM/CJS.
  - **Python**: `asl-codec`, zero-dependency pure Python.
  - **Rust**: `asl-codec`, `no_std`-compatible.
  - **Go**: `github.com/GenSEAM/asl-codec-go`.
  - **WebAssembly**: a standalone `asn.wasm`.
- [ ] Differential equivalence across all five SDKs with `backend/differential.py`, over the same
      `grammar/corpus/asn` fixtures the reference implementation uses. Binary size and cold-start
      figures go in a lock file or are not published.

### Phase 3: Native slicing and output compaction (`asl slice`, `asl filter`, `asl asn`)
- [ ] **`asl slice <file> <path>`** — query nested keys and emit only the requested slice, so an
      agent reads a value instead of a file.
- [ ] **`asl filter <cmd...>`** — intercept noisy compiler and test output, emitting only
      actionable errors and diff hunks.
- [ ] **`asl asn`** — the ASN transcoder: `asl asn --to-json <data.asn>` and
      `asl asn --from-json <data.json>`, plus `--check` over the §11 error set.

      **This replaces the `asl transcode --to-json` this plan used to propose.** `asl transcode`
      already exists and means something else: it switches a *program* between the Nano and verbose
      projections (`tools/transcoder.py`, @pcp:d-1eed). Overloading it with a data conversion would
      make one command mean two things depending on a flag, and the two operations do not even take
      the same kind of file — one takes `.asl`, the other `.asn`.

### Phase 4: Agent-facing landing endpoints (`/format`, `/protocol`)
- [ ] `/format`: JSON vs YAML vs TOON vs ASN with a live token counter. Every figure on the page
      must come from `bench/asn_tokens.lock` or `bench/token_frames.lock` (DESIGN.md §5).
- [ ] `/protocol`: the `asl/coord` frame walkthrough.
- [ ] Index both in `/llms.txt` and `/llms-full.txt`.

---

## Gates

```bash
.venv/bin/python grammar/validate_asn.py          # ASN grammar, corpus, terminal drift, ```asn examples
.venv/bin/python tools/doc_examples.py --quiet    # ```lisp examples, graded as Core AgentScript
.venv/bin/python -m pytest packages/asl-codec -q  # reader, writer, checker, agreement
.venv/bin/python bench/asn_tokens.py --check      # every published percentage
.venv/bin/python grammar/validate.py              # the language grammars, unchanged by this work
.venv/bin/python checker/gate.py                  # the semantic gate, unchanged by this work
```
