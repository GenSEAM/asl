# Draft Log

This log registers newly minted requirements (@pcp:r), engineering caveats (@pcp:c), and deferred tasks (@pcp:l).

## 2026-08-29 — Phase 2 (vocabulary coverage)

Caveats minted: `c-6b02` (exercised never meant the lowering works), `c-1f7d` (a second arity
source in the generator), `c-3ef8` (`list-sort` over NaN is unspecified), `c-0d5b` (four
cross-backend divergences only reachable once the never-executed builtins ran), `c-8f6c` (a match
on a bare binding moves out of it).

Deferred: nothing new. `l-3434` moves to Resolved at 107/107 executed, with what is still unproven
recorded in `prelude/coverage.lock` rather than in prose. The JS `min`/`max` templates are
known-wrong under `d-e5a1` and are left for Phase 4, which is the first phase with a runtime that
could check the change.

## 2026-08-29 — Phase 2 cleanup (literals, ordering, drift)

Decisions minted: `d-7a15` — a leading `-` belongs to the digits it touches and is the subtraction
operator when separated (`-1` is one token, `- 1` is two), because both are legal parses of the
same characters and the Lark grammar is the constrained-decoding surface; `d-2ba6` — an integer
literal outside the width its context requires is a static error rather than a run-time overflow,
which one host could not have noticed at all; `d-6c04` — a declaration reaching a `Float64` derives
`PartialOrd` but not `Eq, Ord`, so §3.2's order is expressible for it, while one reaching `IoError`
derives none of the four.

Caveats minted: `c-3d71` — a Rust integer literal with nothing constraining it falls back to `i32`,
so a lowering template that inlines an `Int64` argument without a typed call fails on any literal
outside `i32`; both such templates now route through `rt`. `c-e820` — `backend/t/smoke.py` is
listed in `.gitignore` while `backend/t/test_smoke.py` imports it, so a clean checkout cannot run
that module until the file is regenerated.

Deferred: `l-4d92` — every operation at `Int32` ignores the width because the Python lowering
table is keyed on the builtin name alone; `l-9e13` — `:field :default` is type-checked and
lowered by neither backend; `l-5c47` —
`list-sort` over a user union, a `Result`, a record or a `Map` orders by different things on each
backend, or only one can order at all. All three are recorded with measurements in ROADMAP §6 and the
first two wait on the same type-aware-emitter phase.

## 2026-08-30 — Phase 2 fix wave (portability blockers and gate integrity)

Decisions minted: `d-6e1f` — ordering over `Float64` is a total order: a NaN-holding value sorts
after every value that does not and ties with other NaN-holding values, implemented as `nan_last`
(Rust) and `order_key` (Python) and shared by `list-sort`/`list-min`/`list-max`/`min`/`max`
(supersedes `c-3ef8`); `d-8b3c` — numeric edges are fixed: `/` and `mod` trap at `MIN / -1`,
`checked-div`/`checked-mod` return `none`, and `float64-to-int64` returns `none` out of range, on
both backends.

Updates folded: `d-2c8f` — `map-key-order` raised from the syntactic pass to the type layer, so an
inferred `Float64` map key is rejected too; `d-7c21` and `d-a70b` — the coverage gate's conditions
were hardened (PCP-id guard on `unexecuted`, `--allow-regression` on `--write`, `unproven` expiry,
exact `N`-domain rule, `narrowed` as a label list, and the `Int32`-never-executed limit recorded in
`coverage.lock`'s `note`).

Deferred: nothing new.

## 2026-08-30 — Phase 3 (rename AgentS → AgentScript)

Decisions minted: `d-9c1f` — the language, file extension, reserved prefix, runtime alias and
tracer env vars move to AgentScript in one atomic change; `AGENT_SPEC.md`/`SPEC_REVIEW.md`,
`.plans/**`, the `asex` repo dir and `ASEX_GATEWAY_KEY` are frozen external/historical contracts.

Caveats minted: none. Deferred: none. The rename is mechanically complete and gated (161 tests,
107/107 executed, 0 differential disagreements).

## 2026-08-30 — Phase 4 (WebAssembly target v1)

Decisions minted: `d-3c5f` — the Wasm arm is the Rust backend compiled to `wasm32-wasip1` under
`node:wasi`, attached as a third program-mode arm of the differential gate (stdout/stderr/exit
compared against Python, native Rust and the declared values).

Caveats minted: `c-7b9e` — a host-errno mapping is not portable. The Wasm arm exposed that `rt.rs`
read `raw_os_error()` as Unix errno while WASI numbers the same condition differently (2 is `ACCES`,
not `ENOENT`), so the mode-000 file mapped to `not-found` on Wasm and `permission-denied` natively.
`io_err` now maps from `ErrorKind`.

Deferred: nothing new. Function-mode Wasm interop (`i64` as `BigInt`) is not attached (d-3c5f).
