# Roadmap: AgentSlang as glue across ecosystems

Written 2026-10-14 from four surveys of this tree (targets, packaging, packages and interop, SQL).
Every "today" line below was checked by running the stage-0 host or reading the source; nothing
here is a claim about the future except the items themselves.

## Where things stand

| Area | Today | Verdict |
|---|---|---|
| Native code | `asl-target-llvm` lowers linked programs through `asl-ir` SSA; `asl build FILE` exists but needs `libaslrt.a`, which only the arm64-darwin seed can produce | real, darwin only |
| WebAssembly | the same backend for `wasm32-unknown-unknown`; aslang.dev ships `site.wasm` built this way (`web/tools/build.asl`) | real, script-driven |
| JavaScript / TypeScript | `asl-target-js` from SSA, byte-equal to the host on its fixtures, `.d.mts` checked by `tsc --strict` | real, new |
| HTML / CSS / SVG | `asl-html`: typed nodes, CSS rules, SVG, Markdown, and ASN converters; toolbelt `(:target :name svg|html|css|js|ts)` | real, new |
| C | `asl-target-c` lowers SSA but links one source plus the prelude, not imports | ~70% |
| Go, Python, Rust, Swift, sh, WAT, the old TS | syntax-level emitters of one module, some tests compare canned strings | prototypes |
| SQL | `asl-sql` renders text for sqlite/postgres/mysql/clickhouse; nothing executes it; identifiers, JSON paths and UPDATE/DELETE clauses are not escaped | unsafe prototype |
| Packages | local `:path` dependencies only; `:rev` checks an existing checkout; no lockfile, registry, git or npm fetching | missing |
| Foreign functions | libc calls are a fixed table inside the LLVM backend; no `extern` in the language; the JS target cannot import anything | missing |
| Packaging and release | `asl pack` needs a missing `audit.py` and `bin/asl`; no tarball, release, npm package or Linux seed exists | missing |

## Constraints in force

- **No language or host changes** while the stage-0 host is being replaced. Anything that needs
  new grammar, parser or `host/src` work waits for that: `extern` (item 4) and everything that
  rides on it (items 5, 6, the native and npm adapters in 17). Work now stays inside packages,
  targets and tools, on the language the host reads today.
- **No publishing.** The DOM bridge and any npm-shaped output are used inside this repository
  only; item 10 stops at producing a local package, nothing goes to the registry.

## Priorities

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
   `emitPyStandaloneCase`/`emitC11StandaloneCase`, `asl-ui/renderNative`, `asl-web/hydrate`.

### P1 — the language can reach other ecosystems (deferred: needs language changes)

4. **`extern` declarations** (grammar, parser, `asl-ir/lower.asl` `moduleExterns`, both backends):

   ```asl
   (extern chunk :from (:npm "lodash" :name "chunk") :sig [(List A) Int64] -> (List (List A)))
   (extern strlen :from (:c "strlen" :lib "c") :sig [CStr] -> Int64)
   (extern log :from (:wasm "env" "log") :sig [I32 I32] -> Unit)
   ```

   An extern becomes an `SsaExtern` with an origin. `asl-target-js` emits an `import` and marshals
   through its runtime (`Int` is `BigInt`); `asl-target-llvm` emits `declare` and passes `:lib` to
   the linker; wasm emits an import. An origin a target cannot serve is `ERR_CAPABILITY_ABSENT`, as
   today. Start with raw-typed signatures (`rawSig?` exists). This one feature unblocks npm from
   JS, C libraries and database drivers natively, wasm imports, and the DOM bridge in ASL.
5. **DOM bridge in ASL.** With externs over `document`, `fetch` and `WebAssembly`, rewrite
   `web/bridge/boot.js` in ASL, compile it with `asl-target-js`, and publish it (P2, item 10).
6. **Link test with C/Rust objects** into the wasm32 module through `wasmLink` — proves the C ABI
   on wasm once externs exist.

### P2 — build, package, publish

7. **`asl build FILE --target native|wasm|js|ts`** in `asl-cli/src/build.asl`, lifting
   `compileWasm!` out of `web/tools/build.asl` and calling `asl-target-js/compileWithTypes!`.
   One command from one source to a binary, a `.wasm`, or an ES module with declarations.
8. **Manifest and lockfile.** `manifest.asn` dependencies with `:path`, `:git … :tag`, `:npm`;
   `asl fetch` writes `asl.lock.asn` (git revision and tree hash, npm integrity) into a cache;
   the loader resolves only from the lock and cache, never the network. Make
   `asl-pack/src/packageAsl.asl` the one manifest parser.
9. **Linux.** A linux-x86_64 seed (`asl1` and the runtime seed) and the `tools/seed.asl` that `seed/seed.asn`
   names for `regen` and `check` but this tree does not have; the
   `verbs.c` `PATH_MAX` include (owned by the host work); layout-agnostic root discovery so a
   standalone clone works (`rules.asl`, `pack.asl`, `build.sh`, `distrib.asl`, the installer's
   `--render-rules`).
10. **npm-shaped output, local only.** Emit `package.json` (`exports`, `types`) around an
    `asl-target-js` module so an ASL library can be consumed from JS in this repository (a
    `file:` or workspace dependency). Publishing the DOM bridge or an `asl` wrapper package waits.
11. **Real releases.** `pack` rebuilt around artifacts (no python gates), per-triple tarballs
    with SHA256SUMS, a CI matrix, tags, and `install.sh` downloading a release before falling back
    to a source build.

### P3 — web development

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

### P4 — multi-language projects and data

17. **SQL that runs.** A typed query API over schemas (columns typed, literals always bound,
    identifiers only from the schema, `Result` with a `SqlError` enum), DML with parameters and
    dialect-gated `RETURNING`, row codecs derived from schemas, and execution adapters: `node:sqlite`,
    `pg`, `mysql2` from the JS target and `libsqlite3` natively, both through externs.
18. **A page bundler.** Embed `asl-target-js` output, `asl-html` CSS and assets into one
    document, so a project is ASL code producing HTML, CSS, JS and SQL from one build.
19. **Typed foreign blocks.** Check `asl-foreign` blocks against the types of interpolated
    values and run `js`/`py` blocks through `asl-proc` with typed arguments.

### P5 — more targets, fewer duplicates

20. **C from SSA as the default C target** (switch to `linkEntry!`, finish closures and ADTs,
    strings and GC in its runtime, a `cc` and run gate); retire `asl-codegen` c99 and the legacy
    `IrModule` path.
21. **Python from SSA** next (~750 lines with its runtime), then Go. Rust last.
22. **Retire** `asl-target-ts` (superseded by `asl-target-js`), `asl-target-wat` and
    `asl-compiler/src/wasm.asl` (the LLVM path ships wasm), and the duplicate Rust emitters. Restore
    or drop the missing parity corpus (`tests/acceptance/targetParity`).
