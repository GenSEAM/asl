# Roadmap: AgentSlang as glue across ecosystems

Rewritten 2026-11-13. It replaces the list of 2026-10-14, which was written while a stage-0 C host
still ran the language; that host was deleted on 2026-10-13 and the compiler now compiles itself.
The roadmap is seven milestones, each with an acceptance check that can fail. The engineering items
of the earlier list are kept below under the milestone they serve or marked frozen.

## Where things stand

Rows dated 2026-11-13 were re-checked against the tree on that day. Rows dated 2026-10-14 are
carried from the earlier survey and were not re-checked.

| Area | Today | Verdict | Checked |
|---|---|---|---|
| Native code | `asl-target-llvm` lowers linked programs through `asl-ir` SSA; the compiler (`asl1`) is written in ASL and compiles itself; seeds are tracked for `arm64-apple-darwin`, `x86_64-unknown-linux-gnu` and `aarch64-unknown-linux-gnu` (`seed/seed.asn`) | real; gated on macOS only | 2026-11-13 |
| Linux | the two Linux seeds are cross-built on macOS; no fixpoint run (stage 2 equals stage 3) and no install run on Linux is recorded | seed present, not proven | 2026-11-13 |
| WebAssembly | the same backend for `wasm32-unknown-unknown`; aslang.dev ships `site.wasm` built this way (`web/tools/build.asl`) | real, script-driven | 2026-10-14 |
| JavaScript / TypeScript | `asl-target-js` from SSA, `.d.mts` checked by `tsc --strict`, on its fixtures | experimental | 2026-10-14 |
| HTML / CSS / SVG | `asl-html`: typed nodes, CSS rules, SVG, Markdown, and ASN converters | experimental | 2026-10-14 |
| Python, Go | `asl-target-py` and `asl-target-go` from the same SSA through the shared `asl-ir/blocks`, on their fixtures | prototypes | 2026-10-14 |
| C | `asl-target-c` emits C that is syntax-checked only; nothing links or runs it | frozen | 2026-11-13 |
| Rust, Swift, sh, WAT, the old TS | syntax-level emitters of one module, some tests compare canned strings | prototypes | 2026-10-14 |
| SQL | `asl-sql` renders text for sqlite/postgres/mysql/clickhouse; nothing executes it; identifiers, JSON paths and UPDATE/DELETE clauses are not escaped | unsafe prototype | 2026-10-14 |
| Packages | local `:path` dependencies only; `:rev` checks an existing checkout; no lockfile, registry, git or npm fetching | missing | 2026-10-14 |
| Foreign functions | libc calls are a fixed table inside the LLVM backend; no `extern` in the language; the JS target cannot import anything | missing | 2026-11-13 |
| Install | a plain clone of this repository does not build its CLI; the toolchain builds inside the development workspace | missing | 2026-11-13 |
| Releases | tags `v0.0.1` to `v0.0.8` exist; none has a full-suite run, a Linux fixpoint or a clean-machine install recorded for its commit; no tarball or npm package | snapshots, not releases | 2026-11-13 |

## Milestones

A milestone is done when its acceptance check has been run and recorded with the commit and date,
and the check was shown to fail first. Order is the order below unless a dependency says otherwise.

### 1. The thesis is measured

The founding claim, that models write ASL about as reliably and cheaply as a mainstream language,
has never been compared with one. [`EXPERIMENT.md`](EXPERIMENT.md) is the pre-registered protocol.

- **Acceptance:** a tracked runner under `bench/`, started from a clean checkout, reproduces one
  results table with the arms ASL raw, ASL healed, Python and TypeScript on the same tasks and
  models, and a dated row applies the decision rule of `EXPERIMENT.md` section 2.
- **Fails if:** swapping two arm labels does not turn the bench test red.
- **Depends on:** approval of the model spend.
- **If the rule is missed:** language surface work stops and effort moves to the harness and the
  toolbelt on existing Python and TypeScript repositories.
- **Frozen until it reports:** dialect and naming rewrites, new syntax.

### 2. Install works from a clean clone

- **Acceptance:** with an empty `HOME` on macOS and in a Linux container, `sh install.sh` against a
  local mirror exits 0 and `asl test` of a sample prints one passed test; the seed fixpoint is
  recorded on Linux for both committed Linux seeds, with the executed assertion counts of macOS.
- **Fails if:** the same run passes on the script as it is today, which would mean the check does
  not measure the defect.
- **Depends on:** a decision that Linux is a supported target.
- **Serves:** items 9 and 11 below.
- **Out of scope:** Windows (the installer refuses honestly), release downloads, a piped install
  from the network.

### 3. Downstream users are unblocked

Two production projects build on ASL and file requests against it.

- **Acceptance:** every filed request is closed with a test or rejected with a reason; a closed
  request passes the reproduction it was filed with, which failed before the change.
- **Order:** checker soundness requests first.
- **Depends on:** milestone 4 for the media codec requests.
- **Out of scope:** writing codecs in ASL where an existing library can be bound.

### 4. Foreign functions (`extern`)

Without `extern` the language cannot be glue. Item 4 below is the design.

- **Acceptance:** a fixture declares `extern` and calls one libc and one libsqlite3 function
  natively on the LLVM target; an origin a target cannot serve is `ERR_CAPABILITY_ABSENT`; one
  downstream codec request closes through an `extern` binding.
- **Fails if:** the fixture test is not red on the base commit and red again on revert.
- **Depends on:** a decision that the no-foreign-code rule covers the toolchain's own bootstrap,
  not the libraries a program links.
- **Serves:** items 4 and 6, and the native adapters of item 17.
- **Out of scope:** npm and wasm import origins, package fetching and the lockfile (item 8), typed
  foreign blocks (item 19).

### 5. Release v0.1 with a receipt

- **Acceptance:** the tag `v0.1.0` carries a receipt for its exact commit: one full suite run
  (suites, executed assertions, every failure listed as known), the seed fixpoint on macOS and
  Linux, and a clean-machine install.
- **Fails if:** the release tool tags a commit that has no receipt, or a receipt of another commit.
- **Depends on:** milestone 2; a gate run short enough to finish (affected suites under 300
  seconds, a full sweep that ends in a verdict).
- **Serves:** item 11.
- **Out of scope:** new targets, a package registry.

### 6. Twenty-four hours of autonomous work

- **Acceptance:** the agent fleet runs 24 hours on its server with no lead action: at least 10
  merges, no ungraded commit on main, no dirty worktree left by a stopped unit, no unit lost, and
  loop-type stops under 30 percent of exits; measured from the journal and `git log`.
- **Fails if:** any bound is missed.
- **Depends on:** the agent passing five consecutive independently graded units without lead
  recovery.
- **Frozen until then:** new agent, gateway, conductor and remote features.

### 7. A human-readable code map

- **Acceptance:** one command writes a static page and its data rows from manifests, package
  cards, `git log` and gate times; on a fixed set of 12 questions about the system the map halves
  the median tokens read to a correct answer against the existing views.
- **Fails if:** a package under `packages/` is missing from the data rows, an edge has no manifest
  source, or the halving is missed (then the map changes, not the questions).
- **Out of scope:** live dashboards, a server.

## Frozen

Not worked until a milestone above closes or a decision reopens it:

- packages outside the core tier (parser, checker, IR, LLVM target, CLI, forms, intel, gates,
  gateway, agent) and the Python, Go, JS, C, shell and Swift targets (items 20 to 22);
- web development (items 12 to 16), SQL execution (item 17), the page bundler (item 18);
- Windows; publishing to any registry (item 10 stays local).

## Engineering items

Carried from 2026-10-14 with their numbers. Safety items 1 to 3 are not tied to a milestone and
stay first.

### P0 — safety and honesty (small, do first)

1. **SQL injection holes** (`asl-sql/src/core/sql.asl`, `ddl.asl`). Quote every identifier with
   the dialect quote and escaping, bind JSON paths, make arithmetic and aggregate names enums, and
   rename `rawSql` to an explicitly unsafe constructor. The manifest and the blog post
   "Cross-dialect SQL" claim injection safety; correct them until this lands.
2. **Dialect capability table.** Return `ERR_UNSUPPORTED` instead of emitting invalid SQL
   (ClickHouse `ON CONFLICT`, sqlite/clickhouse `FOR UPDATE`, `RETURNING` on SELECT or MySQL).
   Add `IS NULL`, `IN (list)` and golden SQL per dialect with negative injection tests.
3. **Mark or remove stubs that look real:** `asl-compiler/src/{elf,macho,wasi}.asl`,
   `tools/release.asl`, `asl target sh` (prints a fixed skeleton), the canned
   `emitC11StandaloneCase`, `asl-ui/renderNative`, `asl-web/hydrate`.

### P1 — the language can reach other ecosystems (milestone 4)

4. **`extern` declarations** (grammar, parser, `asl-ir/lower.asl` `moduleExterns`, both backends):

   ```asl
   (extern chunk :from (:npm "lodash" :name "chunk") :sig [(List A) Int64] -> (List (List A)))
   (extern strlen :from (:c "strlen" :lib "c") :sig [CStr] -> Int64)
   (extern log :from (:wasm "env" "log") :sig [I32 I32] -> Unit)
   ```

   An extern becomes an `SsaExtern` with an origin. `asl-target-llvm` emits `declare` and passes
   `:lib` to the linker; `asl-target-js` emits an `import` and marshals through its runtime (`Int`
   is `BigInt`); wasm emits an import. An origin a target cannot serve is `ERR_CAPABILITY_ABSENT`,
   as today. Start with raw-typed signatures (`rawSig?` exists) and the `:c` origin on the LLVM
   target; the `:npm` and `:wasm` origins follow.
5. **DOM bridge in ASL.** With externs over `document`, `fetch` and `WebAssembly`, rewrite
   `web/bridge/boot.js` in ASL and compile it with `asl-target-js`.
6. **Link test with C/Rust objects** into the wasm32 module through `wasmLink` — proves the C ABI
   on wasm once externs exist.

### P2 — build, package, publish (milestones 2 and 5)

7. **`asl build FILE --target native|wasm|js|ts`** in `asl-cli/src/build.asl`, lifting
   `compileWasm!` out of `web/tools/build.asl` and calling `asl-target-js/compileWithTypes!`.
   One command from one source to a binary, a `.wasm`, or an ES module with declarations.
8. **Manifest and lockfile.** `manifest.asn` dependencies with `:path`, `:git … :tag`, `:npm`;
   `asl fetch` writes `asl.lock.asn` (git revision and tree hash, npm integrity) into a cache;
   the loader resolves only from the lock and cache, never the network. Make
   `asl-pack/src/packageAsl.asl` the one manifest parser.
9. **Linux.** Seeds for `x86_64-unknown-linux-gnu` and `aarch64-unknown-linux-gnu` are committed.
   Missing: a recorded fixpoint run on Linux for each seed commit, an install run in a clean Linux
   container, and layout-agnostic root discovery so a standalone clone works (`rules.asl`,
   `pack.asl`, `build.sh`, `distrib.asl`, the installer's `--render-rules`).
10. **npm-shaped output, local only.** Emit `package.json` (`exports`, `types`) around an
    `asl-target-js` module so an ASL library can be consumed from JS in this repository (a
    `file:` or workspace dependency). Publishing the DOM bridge or an `asl` wrapper package waits.
11. **Real releases.** A receipt per tag (full suite run, fixpoint per triple, clean install),
    per-triple tarballs with SHA256SUMS, and `install.sh` downloading a release before falling
    back to a source build.

### P3 — web development (frozen)

12. **One node model.** Keep `asl-html`; move `asl-web` (SSR, hydration) onto it; retire
    `asl-ui/renderWeb`, `asl-vdom/{html,asnSvg,emitJsx}` and the HTML/SVG/CSS emitters in
    `asl-transpile` (fold its CSS cascade into `asl-html`).
13. **Hydration** that adopts the prerendered DOM (today `hydrateVNodeTree` returns its input).
14. **Dev server with live reload** over `asl-web/sse`, and **SSR on request** through `asl-http`
    with chunked `asl-html` output.
15. **Routing** (a route table at build, `pushState` in the update loop) and **typed forms**
    (schema to HTML plus server-side validation).
16. **JS as the default client target** for the site, so a web build needs no LLVM toolchain;
    keep wasm where speed matters.

### P4 — multi-language projects and data (frozen, except the native adapter of item 17)

17. **SQL that runs.** A typed query API over schemas (columns typed, literals always bound,
    identifiers only from the schema, `Result` with a `SqlError` enum), DML with parameters and
    dialect-gated `RETURNING`, row codecs derived from schemas, and execution adapters: `node:sqlite`,
    `pg`, `mysql2` from the JS target and `libsqlite3` natively, both through externs.
18. **A page bundler.** Embed `asl-target-js` output, `asl-html` CSS and assets into one
    document, so a project is ASL code producing HTML, CSS, JS and SQL from one build.
19. **Typed foreign blocks.** Check `asl-foreign` blocks against the types of interpolated
    values and run `js`/`py` blocks through `asl-proc` with typed arguments.

### P5 — more targets, fewer duplicates (frozen)

20. **C from SSA as the default C target** (switch to `linkEntry!`, finish closures and ADTs,
    strings and GC in its runtime, a `cc` and run gate); retire `asl-codegen` c99 and the legacy
    `IrModule` path.
21. **Kotlin and Swift from SSA** on the `asl-ir/blocks` shape Python and Go use (both done); a shell target only
    for a subset (strings, ints, processes, printing) that refuses the rest. Retire Rust: shared GC values
    become `Rc<RefCell<…>>` there, slower than the native LLVM build and without Rust's guarantees.
22. **Retire** `asl-target-ts` (superseded by `asl-target-js`), `asl-target-wat` and
    `asl-compiler/src/wasm.asl` (the LLVM path ships wasm), and the duplicate Rust emitters. Restore
    or drop the missing parity corpus (`tests/acceptance/targetParity`).
