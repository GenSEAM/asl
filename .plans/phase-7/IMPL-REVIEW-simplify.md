# Phase 7 implementation review — simplify lens

**Lens:** simplification / over-engineering / dead code
**Verdict:** approve-with-amendments
**Blockers:** 0
**Files reviewed (on disk, by `Read`):** `backend/to_typescript.py:1-647`,
`backend/ts/rt.ts:1-806`, `prelude/generate.py:1-222`, `backend/check_corpus.py:1-138`,
`backend/differential.py:1-631`, `prelude/prelude.json:1-100` (sampled), `package.json:1-19`.
Cross-references against `backend/to_python.py`, `.plans/phase-7/PLAN.md`,
`.plans/phase-7/RECONCILIATION.md`.

---

## Findings

### M1 (medium) — `MAP_EMPTY` exported and emitted into prelude but never used

- **Where:** `backend/ts/rt.ts:79` defines `MAP_EMPTY`; `prelude/prelude.json:752`
  emits `RT.MAP_EMPTY` as the `ts` template for a `map-empty` builtin; the
  transpiler never constructs a literal map that resolves to it (`to_typescript.py`
  has no path to emit `MAP_EMPTY`). The `mFrom()` constructor takes the
  `ASPair<K,V>[]` route through every actual fixture; no corpus file imports
  `map-empty`.
- **Class:** export with a sole caller — a single fixture would reify it; absent
  one, the runtime carries a 2-line export, the prelude carries a template, and
  nothing exercises the path.
- **Cut:** keep the template (the prelude gate runs it through format-arity) but
  drop the `RT.MAP_EMPTY` reference unless a fixture lands. For the runtime,
  leave the `export const MAP_EMPTY` in place — it is small, and a future
  fixture may reach it; the cost of deletion when it lands is one line.
- **Safe?** Yes — `MAP_EMPTY` has no internal callers in `rt.ts`; nothing
  constructs one in TS source. Deletion is safe today; deletion is also the
  only behavioral change available. The right call is **leave both as written**
  and record the no-caller condition; not a blocker.

### M2 (medium) — `processRun`, `envGet`, `args()`: exported but un-templated

- **Where:** `backend/ts/rt.ts:759-789` exports `envGet`, `args()`,
  `processRun`. `prelude/prelude.json` has no `process-run`, `env-get`, or
  `args` builtin — the plan's D3 explicitly drops the three fork orphans
  (`.plans/phase-7/PLAN.md` D3, "3 fork orphans are not added"). Three
  exports, ~30 lines, zero callers in any TS source the project emits.
- **Class:** dead runtime exports kept from the fork because they cost nothing
  to compile and the prelude template can land later.
- **Cut:** delete the three exports. Each is recoverable from git history when a
  template is added. **Class enumeration:** every other fork-era export that
  lacks a `prelude/prelude.json` template is in the same class. Surveyed:
  `notFound`/`permissionDenied`/`alreadyExists`/`invalidPath`/`interrupted`/
  `other` are *called* by prelude templates (`prelude/prelude.json:1012/1022/
  1032/1042/1052/1062` — verified); `codeToIoError` is exported by design
  (W5's part-2 unit-test gate, `PLAN.md` W5 part 2) — keep. Everything else
  in `rt.ts` (`add`/`sub`/`mul`/.../`mFrom`/`optOr`/`...`) is reached by a
  prelude template (cross-checked by the `RT.\w+` invocations found by
  `Grep` against `prelude/prelude.json`); only `processRun`/`envGet`/`args`
  are orphans.
- **Safe?** Yes — no prelude template names them, the differential harness
  imports only `RT.fmtF64` and `RT.cmp` (verified, `differential.py:421/430/
  434`). Trivial to revert if a `process-run` builtin lands.

### m3 (low) — `ts_literal` and the `arg + type` literal pattern duplicate `py_literal`/`rust_literal`

- **Where:** `backend/differential.py:146-163` defines `ts_literal`. The
  `Int`/`Float`/`String`/`Bool`/`List` arms mirror `py_literal:130-145` and
  `rust_literal:108-128` line for line, only the syntax differs.
- **Class:** three near-identical literals.
- **Cut:** factor a `Literal(syntax, spec, value)` table with three syntax
  renderers, or have each backend supply a small `render` closure. Saves ~25
  lines, removes the chance that one side drifts (today, e.g. `rust_literal`
  handles non-finite float by name and `ts_literal` by name too, but the
  spelling differs — Rust wants `f64::INFINITY`, TS wants `Infinity`; if a
  reviewer missed one the differential would silently agree on a value that
  the type-checker rejects on one side).
- **Safe?** Behaviorally identical after refactor; the three call sites are
  the only consumers. Low risk; medium payoff in future-proofing.

### m4 (low) — `MAP_EMPTY` template duplicate path: `mFrom([])` already gives `MAP_EMPTY`

- **Where:** `prelude/prelude.json:752` emits `RT.MAP_EMPTY`; `mFrom(ps)` at
  `rt.ts:562-566` returns `{ entries: new Map() }` when `ps` is empty — the
  same value. A `map-empty` builtin lowered as `RT.mFrom([])` would have the
  same effect and reuse the existing template `mFrom` already proves in the
  corpus.
- **Class:** parallel-but-redundant helper.
- **Cut:** change `prelude/prelude.json` `map-empty`'s `ts` template to
  `RT.mFrom([])` and delete the `MAP_EMPTY` constant in `rt.ts`. Saves one
  export, one constant, one template; behavior unchanged.
- **Safe?** Identical observable behavior; the constant's only purpose was
  the template, and the template is the only consumer of the constant.

### m5 (low) — `IO_ERROR_NAMES` set duplicates the `IoError` union's tag spelling

- **Where:** `backend/ts/rt.ts:631-634` declares `IO_ERROR_NAMES: ReadonlySet
  <string>` containing exactly the six tags of the `IoError` union declared
  eight lines above (`rt.ts:623-630`). Used only at `rt.ts:800` inside
  `mainExit` to reject a non-`IoError` failure.
- **Class:** a hand-maintained mirror of a closed type.
- **Cut:** inline `["not-found","permission-denied","already-exists",
  "invalid-path","interrupted","other"].includes(name as string)` at the one
  call site, or — better — write a single `isIoError(x): x is IoError` helper
  that does `typeof x?.tag === "string" && IO_ERROR_TAGS.has(x.tag)` and use
  it in `mainExit`. The current shape is a `Set` literal with one consumer
  eight lines of `else if` away; the duplication is the price of writing it
  as a `Set`. Saves 4 lines and removes the "what if a tag is added to
  `IoError` but not to the set?" drift.
- **Safe?** Identical behavior today; the only risk is a future tag addition
  forgetting to update the set — that's exactly the bug this comment argues
  is unobservable in the existing code, but the existing code is what
  matters.

### m6 (low) — `_SER.keySer` is dead outside the map branch but the `ser` reach is identical

- **Where:** `backend/differential.py:418-423` defines `keySer`; called only
  inside the map branch at `:438`. The branch sorts the entries by
  `RT.cmp(a[0], b[0])` — already correct — and renders each key via
  `keySer`. The body of `keySer` is essentially `ser(k)` for the key types
  that `ser` already handles. A reader has to know that.
- **Class:** helper that's the same as the main entry point.
- **Cut:** inline: `JSON.stringify(RT.fmtF64(k))` for the number arm is the
  only non-`ser` shape, and `ser(NaN)` would route through `RT.fmtF64` anyway
  — except the JSON wrapping (`RT.fmtF64(NaN) === "nan"` without quotes).
  Replace `keySer(e[0])` with `ser(e[0])` plus a `JSON.stringify` if needed
  for the number case; the small string/bigint/bool arms already match.
- **Safe?** Saves ~6 lines; risk is mis-counting cases in the helper. The
  payoff is small.

### m7 (low) — `keyOf` in `rt.ts` hand-rolls a structural key for `ASMap`

- **Where:** `backend/ts/rt.ts:88-100`. The function emits a canonical
  rendering of an AgentScript value for `Map<string, _>` lookup. There is no
  Node/TS stdlib equivalent that does this (JSON.stringify doesn't quote
  `NaN`/`Infinity`/bigint the way the runtime requires), so this isn't a
  "reinvented stdlib" finding. It is, however, ~14 lines that the existing
  `eq` and `cmp` functions would have to mirror if the rendering were ever
  made symmetric.
- **Class:** nothing to cut — flagged only to note that the plan's "reinvented
  stdlib" lens doesn't fire here.

### m8 (low) — `Int` alias declared twice in `to_typescript.PRIM`

- **Where:** `backend/to_typescript.py:48` lists both `Int32` and `Int` as
  `bigint`. `to_python.py` and `to_rust.py` do not have an `Int` key (Python
  reads it via alias resolution; Rust aliases the type).
- **Class:** minor structural duplication — same map shape, three backends,
  one of which carries an alias entry the others don't.
- **Cut:** none safe without centralizing the type-name table across all
  backends, which is out of phase scope. **Note only.**

### m9 (low) — `prelude/generate.py` iterates the now-4-tuple by indexing into `b.get(tgt)`; `validate_templates` reformats each template's `ts` field even though templates with `{*}` are skipped

- **Where:** `prelude/generate.py:172-181` calls `tpl.format(...)` for every
  template that lacks `{*}`. A `ts` template that legitimately contains a
  literal `{` is rejected unless doubled — the comment at `:158-160`
  explains. Verified that *every* TS template in the live prelude uses `{N}`
  placeholders, none uses `{*}`, none uses literal braces. The validator does
  its job; this finding is **no action**.
- **Class:** false alarm — noted because the brief asked to check
  `validate_templates` for drift.

### m10 (low) — `tsc` invocation flags identical across three sites

- **Where:** `check_corpus.py:118-124`, `differential.py:398-403`,
  `differential.py:471-477` all spell the same flag set verbatim:
  `--strict --target es2020 --module commonjs --typeRoots <node_modules/@types>
  --types node`. `check_corpus.py:118-124` adds `--noEmit` (correct — no run).
- **Class:** copy-paste across three sites; the plan's D4 froze the flags
  precisely so any future change is mechanical. A future drift between
  sites (one site adds `--noEmit`, the others forget) is the classic
  "the gate kept green" failure mode AGENTS.md warns about.
- **Cut:** factor a `tsc_flags(*, emit: bool)` constant in a shared module —
  probably `backend/_ts.py` — and import it from all three sites. `check_corpus.py`'s
  `--noEmit` is the only branch. Saves ~6 lines and one drift vector.
- **Safe?** Same flags emitted at all three sites today; the only risk is
  adding a flag at one site and forgetting the others, which is exactly the
  risk the helper closes.

### m11 (low) — `build_typescript` vs `run_typescript` repeat the transpile + write + tsc dance

- **Where:** `differential.py:387-409` and `differential.py:451-481` both
  transpile, copy `rt.ts`, write `main.ts`, run `tsc`, raise on failure.
  The function-mode path also writes a `drv.ts` and uses a different flag
  block (no `--noEmit`, has the `drv.ts` argument, has `--outDir`). Same
  shape, two flag lists, one extra file. The duplication is real but the
  divergence is real too.
- **Class:** shared skeleton, divergent body — borderline.
- **Cut:** factor a private `_compile_ts(src, d, *, extra_inputs=(),
  out_dir=Optional)` helper that owns the `tsc` invocation. Saves ~15 lines
  and removes the chance that the two `tsc` flag lists drift (the
  function-mode one already dropped `--noEmit`, which is correct, and the
  program-mode one already has `--outDir`, also correct).
- **Safe?** A refactor that keeps the two flag lists verbatim is safe; the
  tests are the differential gate running both arms, which will catch any
  behavioral drift.

---

## Dead code — verified absent

- `defentry`/`asMain` host entry remnants: not present in the recovered
  transpiler; the live `host_entry` shape (`to_typescript.py:256-272`) emits
  `RT.mainExit(main(RT.args()))` and matches `to_python.py:181-183`'s shape.
  No leftover.
- `from boundary import ...` / `TargetMismatch` / `NotLowered` / `check_target`:
  not present. Plan W3 rework 1 was applied.
- `ASBoundary` class: not present.
- `string` error parameter (the fork's `ASResult<T, string>`): replaced by
  the six-case `IoError` union (`rt.ts:623-630`); no `RT.fail(message)`
  factory remains.
- Unused imports in `to_typescript.py`: `argparse`, `json`, `sys`, `Path`,
  `Tree`, `Token`, `closure`, `declared_path`, `imports`, `FORM_KW`,
  `parser`, `unions` — every one has at least one use site, verified.
- Unused `from to_typescript import mangle` in `differential.py:461`: the
  imported `mangle` is used at `:462` (`fn = mangle(task["entry"])`) to
  produce the entry's TS identifier; verified.

## Duplication — surveyed

- The TS ctor in `to_typescript.py:419-435` uses a `name = self.resolve(...)`
  lookup, where `resolve` falls back to `self.local.get(name, mangle(name))`.
  `self.qual()` at `:135` performs the qualified-name form. The pair
  duplicates `to_python.py:122-128` (`qual`) and `:166` (`resolve`); the
  duplication is structural and intended (the two backends have different
  keyword sets and runtime namespace shapes), not actionable.
- The `pattern()` lowering in `to_typescript.py:559-624` mirrors
  `to_python.py:341-407` arm for arm — six heads, one disjunct each. The
  bodies diverge (`conjs`, `slice` vs `len > 0`), and the surface area is
  bounded by the number of pattern constructors; refactoring to share would
  cost more than it saves.

## Reinvented stdlib — surveyed

- `rt.ts` `split` (`rt.ts:301-318`) cannot use `String.prototype.split`
  because of the UTF-16 vs code-point rule (the comment at `rt.ts:296-298`
  records it). Keep.
- `fmtF64` (`rt.ts:353-403`) cannot use `String(x)` because of the
  exponent-threshold divergence (the comment at `:341-349` records it).
  Keep.
- `eq` (`rt.ts:105-126`) cannot use `===` (handles reference vs value) or
  `JSON.stringify(a) === JSON.stringify(b)` (reorders NaN, bigint). Keep.
- `keyOf` (`rt.ts:88-100`) cannot use `JSON.stringify` for the same
  reasons. Keep.
- `to_python.py:267-271` (the Python transpiler's `module_prefix`) and
  `to_typescript.py:73-77` (the TS one) duplicate the segment-split logic.
  The bodies are identical except for the `mangle` function each calls; not
  worth a shared helper given two callers.

## Over-abstraction — none found

- `ASOption<T>`, `ASResult<T,E>`, `ASMap<K,V>`, `ASPair`, `ASThrown` —
  every class/type in `rt.ts` is consumed by either an emitted program or
  the differential harness. No interface with one implementer.
- `IoError` union with six tags and six `notFound()`-style constructors: the
  constructors are required by the prelude templates (`prelude.json:1012-
  1062`). No over-abstraction.
- `codeToIoError` table: a `switch` on six string codes; a plain switch
  already reads clear (`rt.ts:647-657`). No abstraction.

## Risks

- The **no-action** items (M1, m8, m9) are recorded so a later reviewer
  doesn't re-flag them; the cuts proposed are non-load-bearing.
- The **actionable** items (M2, m3, m4, m5, m10, m11) all change one file or
  span two adjacent files; no gate impact on their own, but the
  `differential.py` arms (m10, m11) need a clean rerun after refactor.
- The single highest-leverage cut is **M2** (drop `processRun`/`envGet`/
  `args()`) — three exports, ~30 lines, zero callers, drop trivially. After
  M2, the next is **m4** (`MAP_EMPTY` → `RT.mFrom([])`), which kills one
  export, one template value, and zero behavior change.

## Gates run

None — this is a review pass; the parent supplies the gate run. I verified
the implements' claims by reading the cited files end to end.

## Unverified

- I did not run `tsc`, the corpus gate, or the differential. The M-cuts are
  proposed on the basis of static reading; a fix pass should run
  `.venv/bin/python backend/check_corpus.py` and
  `.venv/bin/python backend/differential.py` to confirm no behavioral
  regression. (This is the contract: the reviewer proposes, the fixer
  verifies.)
