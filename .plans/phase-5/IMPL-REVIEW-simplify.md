# Phase 5 — IMPL-REVIEW-simplify

Lens: reuse, simplification, efficiency, dead state.

## Verdict

`approve-with-amendments`

## Findings

### High severity

- **H1 — `crates/agentscript-interp/src/fmt.rs` (entire file) is dead.** The
  module declares `pub fn case_of` (line 5) but has zero callers in the crate
  or in `backend/`. `main.rs:18` brings the module in with `mod fmt;`, but
  Rust's `unused` lint would have flagged it without the `mod` declaration.
  Replace: delete `crates/agentscript-interp/src/fmt.rs` and remove `mod fmt;`
  from `main.rs`. (No other reference exists.)

- **H2 — Root file parsed twice on every invocation.** `main.rs` calls
  `modules::checked_parse(&src, &source.display().to_string())` (line 50) and
  then `Loader::resolve(&source)` (line 60) which calls
  `Loader::parse_file(root_path)` (modules.rs:82) which re-reads the file and
  re-parses it (`std::fs::read_to_string` + `parse_source`). The result of the
  first parse and read is discarded; only the syntax-error side-effect matters.
  Replace: have `Loader::resolve` accept the already-read source bytes (or
  return a `Result<Program, String>` whose `Err` is the `checked_parse`
  diagnostic), and skip the second read+parse. This halves I/O for every
  run; the corpus is small but the interpreter is also wired into the
  differential arm that calls it four times per case file.

- **H3 — Prelude IoError cases are hardcoded in the CST builder.**
  `crates/agentscript-interp/src/cst.rs:341-350` injects IoError's six cases
  into `enum_cases` if absent, with a literal `&[(&str, &[&str])]` array. This
  duplicates the canonical source of truth (`prelude/prelude.json`) and
  duplicates what `value.rs`/`io.rs` already encode (`IoError::case()`).
  Worse, it can diverge silently if a new case is added. Replace: lift the
  IoError case list to a single `const` next to `IoError::case()` in
  `io.rs` (or into a `pub const PRELUDE_CASES: &[&str]` in `eval.rs`, which
  already has one at line 70 — collapse the two duplicates) and call that.

### Medium severity

- **M1 — `eval.rs::list_higher` has an identical-branch conditional.**
  `crates/agentscript-interp/src/eval.rs:911-919`:
  ```rust
  let f = {
      if name == "fold" {
          // (fold f init xs): f is args[0]
          args[0].clone()
      } else {
          args[0].clone()
      }
  };
  ```
  Both arms do `args[0].clone()`. Replace: `let f = args[0].clone();` and
  delete the comment.

- **M2 — `eval.rs::num_binop` has empty branches that exist only to host
  comments.** `crates/agentscript-interp/src/eval.rs:806-823`, the float
  divisor-zero block:
  ```rust
  if y == 0.0 {
      if name == "checked-div" || name == "checked-mod" {
          // …comment-only…
      } else {
          // …comment-only…
      }
  }
  ```
  Neither branch executes anything; the trailing `match name { … }` is what
  computes. The whole `if y == 0.0 { if … } else { … }` wrapper is dead
  structure. Replace: delete the empty `if/else` and let the `match`
  compute directly (the `checked-div`/`checked-mod` paths already special-case
  `y == 0.0` inside their own arms, lines 814-820).

- **M3 — `eval.rs::stable_sort_by` is a one-line wrapper around
  `slice::sort_by`.** `crates/agentscript-interp/src/eval.rs:1017-1022`:
  ```rust
  fn stable_sort_by<T: Clone>(&self, v: &mut [T], mut cmp: impl FnMut(&T, &T) -> Ordering) {
      v.sort_by(&mut cmp);
  }
  ```
  The comment on `list-sort` already notes Rust's `sort_by` is stable.
  Replace: delete the wrapper; call `v.sort_by(cmp)` at the two call sites
  (`list-sort` line 663 and `list-sort-by` line 956). The generic `T: Clone`
  bound was always a smell — `sort_by` doesn't need `Clone`.

- **M4 — `eval.rs::eval_logical` redundant ternary.** `crates/agentscript-interp/src/eval.rs:175-186`:
  the final expression is `Value::Bool(if is_and { result } else { result })`,
  i.e. `Value::Bool(result)` regardless. Replace: `Ok(Step::OK(Value::Bool(result)))`.
  The `result` variable's initial `is_and` value is also dead — `result` is
  assigned before it is read in both branches. Replace with `result = is_and`
  only if it simplifies; `let mut result = is_and;` is fine, just remove the
  dead final ternary.

- **M5 — `eval.rs` linear-scans unit defuns and cases on every ident
  lookup.** `eval_ident` (line 386), `resolve_local` (line 414),
  `resolve_in_unit` (line 425), `resolve_callable_in` (line 444), and the
  builtin-shadowed check in `eval` (line 313-318) each call
  `unit.defuns.iter().any(|d| d.name == name)` and
  `unit.enum_cases.iter().any(|(_, cl)| cl.contains(&name.to_string()))` —
  O(d) per ident, where d = total defuns in the current unit, plus
  O(e×c) for the case scan. The link phase (line 128) already iterates
  `units.iter().enumerate()` and could build a
  `defun_index: HashMap<String, usize>` and `case_index: HashMap<(String,String), usize>`
  per unit for O(1) lookups. Performance hazard for a tree-walker; corpus is
  small so flagging as medium. Replace: in `link()`, build the two maps per
  unit; replace `iter().any(...)` calls in the five methods with `self.defun_index.get(name)`
  / `self.case_index.get(&(unit, name))`. The builtin shadowing check (line 313)
  becomes a single `self.defun_index.get(name).is_none()`.

- **M6 — `eval.rs::call_defun` clones the entire `Defun` on every call.**
  `crates/agentscript-interp/src/eval.rs:484-501`: `let def = self.units.get(ti)
  .and_then(|u| u.defuns.iter().find(|d| d.name == name)).cloned().ok_or_else(...)?;`.
  The clone is to drop the borrow of `self.units`, but the only later use
  is `def.params.len()`, `def.params.iter().zip(args)`, and `def.body`
  (which is fed to `eval_seq`). Replace: take indices into the stored
  `Unit` (`self.units[ti]` keeps a `Vec<Defun>`); hold a borrow across the
  call by extracting `params` and `body` as `&[Param]` and `&[Expr]`
  references before mutating `self.env`/`self.cur`. Concretely: do
  `let u = &self.units[ti]; let d = u.defuns.iter().find(|d| d.name == name)...`
  and reborrow. The clone of `params`/`body` is then a slice clone, not
  a full AST clone. Same for `Callable::Lambda` application (line 462):
  `lam.captured` is `Vec<BTreeMap<String, Value>>` cloned every invocation.

- **M7 — `eval.rs::resolve_call` / `resolve_callable_in` duplicate
  `eval_ident` / `eval_qualified`.** `resolve_call` (line 410) and
  `resolve_in_unit` (line 425) reimplement the lookup logic of `eval_ident`
  and `eval_qualified` purely to avoid the `Step` wrapping. Replace: factor
  `eval_ident` and `eval_qualified` into helpers returning
  `Result<Value, Err>` (not `Result<Step, Err>`); have `resolve_call` call
  them and then `value_to_callable` on the result. This deletes
  `resolve_call`/`resolve_callable_in` entirely.

### Low severity

- **L1 — `crates/agentscript-interp/src/num.rs::checked_quot` is a one-line
  rename.** `num.rs:23` is just `a.checked_div(b)`. Used once. Replace: inline
  at line 88 (`let q = a.checked_div(b)?;`) and delete `checked_quot`.

- **L2 — `crates/agentscript-interp/src/eval.rs::int` helper is a one-line
  wrapper.** `eval.rs:1179-1181`:
  ```rust
  fn int(v: i64, w: NumericWidth) -> Value { Value::int(v, w) }
  ```
  Used only in `eval.rs`. Replace: delete and call `Value::int(v, w)` directly
  at the ~10 call sites; the module already imports `Value` and
  `NumericWidth`.

- **L3 — `crates/agentscript-interp/src/value.rs::MapKey::Other` is
  unreachable.** `value.rs:71` declares `Other` "never a legal key" and the
  discriminant `cmp` (line 87) handles it with `Ordering::Equal`/`Equal` —
  but `MapKey::from_value` returns `None` for any unorderable value, so
  `Other` can never be constructed. The `discriminant` helper (line 92)
  and the `(MapKey::Other, MapKey::Other)` arm exist for nothing. Replace:
  delete `MapKey::Other`, the `Other` discriminant arm, the discriminant
  helper, and the comment.

- **L4 — `crates/agentscript-interp/src/eval.rs::eval_logical`'s
  short-circuit has a redundant assignment.** `eval.rs:175-186`: after the
  loop, `result = true` was set only inside `is_and`; the `or` branch
  leaves `result` at its initial `is_and = false` value, but the loop
  always assigns in both branches (`if is_and { ... result = true; } else
  { if b { return ... } }`). The initial value is genuinely dead. Replace:
  `let mut result = false;` for `or` and `let mut result = true;` for `and`,
  or just `Ok(Step::OK(Value::Bool(is_and || /*...*/)))` if restructured.

- **L5 — `crates/agentscript-interp/src/modules.rs::parse_file` returns a
  `Tree` it never uses.** `modules.rs:82-85`:
  ```rust
  let tree = parse_source(&src).ok_or_else(...)?;
  Ok((tree, src))
  ```
  `tree` is only used inside `resolve` to call `build_unit_from(&tree,
  src.as_bytes())` (line 65), which extracts `tree.root_node()` immediately.
  `src` is also only consumed as `src.as_bytes()`. Replace: have
  `parse_file` return `Result<Unit, String>` directly, dropping the
  intermediate `Tree` allocation. Used at most once per import.

- **L6 — `crates/agentscript-interp/src/cst.rs::find_error` walks the whole
  tree after `parse_source` returned a tree.** `modules.rs:97` (the
  `checked_parse` body) calls `cst::find_error` (cst.rs:23) on the root,
  which recurses into all children. This is a `Tree` lifetime problem
  (the tree-sitter `Tree` is dropped after the call), but a tree-sitter
  `Node` carries its own arena handle — `parse_source` could return the
  tree and `find_error` could be called before the tree is dropped. The
  current shape is fine; flagging only because `main.rs` then re-parses
  (H2 above) which means this walk runs and is thrown away.

- **L7 — `crates/agentscript-interp/src/cst.rs:212` walks `node.child(i)`
  by raw index to skip parens in `constructor_call`.** The `children()`
  helper on `Builder` already skips unnamed children, but the
  `constructor_call` head is itself an anonymous keyword and would be
  dropped, so the raw index loop is needed. Minor — flag as a known
  workaround. A grammar tweak making the head a named token would let
  `children()` do the work.

- **L8 — `crates/agentscript-interp/src/eval.rs::apply_closure` and
  `apply_closure_bin` are the same function with different arity.** Each
  is two lines, each clones the `Callable`. Replace: a single
  `apply_closure_n(func, args: Vec<Value>)`; delete both. (Already
  eliminated by M7 if `resolve_call` is folded away.)

- **L9 — `crates/agentscript-interp/src/eval.rs::Step::into_ok` discards
  the `Ret` vs `OK` distinction.** `eval.rs:53-58`:
  ```rust
  fn into_ok(self) -> Result<Value, Err> {
      match self {
          Step::OK(v) => Ok(v),
          Step::Ret(v) => Ok(v),
      }
  }
  ```
  Both arms do `Ok(v)`. Replace: `Ok(v)` for both arms, or just `Ok(match self
  { Step::OK(v) | Step::Ret(v) => v })`. The function is fine but the
  `match` is a code smell. (Real return-vs-ok distinction happens in
  `apply`/`call_defun` body, not here.)

- **L10 — `crates/agentscript-interp/src/eval.rs::eval` `Let` always pushes
  a frame even for a single binding.** The `let*` semantics require it,
  but the current shape also pushes a frame for `let` (not `let*`)? The
  grammar doesn't distinguish them in the AST (`Expr::Let` carries
  `Vec<(name, expr)>`). Looking at `cst.rs:152-163`, the parser emits
  `let_form` with multiple bindings; this is `let*`. Frame-per-let is
  required for sequential semantics. No change needed — noting only.

## Performance hazards that matter for a tree-walker

The list-extreme/min/max hot path (`eval.rs::list_extreme`, `min`, `max`)
clones the larger candidate on each comparison
(`args[1].clone()` / `args[0].clone()`). For a 10k-element list this is
O(n) clones of potentially-large Values. Same for `list-sort` (`xs.clone()`
line 663 — the whole list is cloned just to take ownership; the slice
already is owned). Defer to a future phase if profiling justifies.

`cons_pattern` match (`eval.rs:1147-1151`) recurses with
`xs[1..].to_vec()` on every step — every cons cell allocates a new Vec.
This is O(n²) in the length of the matched spine. The corpus only matches
small lists, but it's a real hazard; a VecDeque that drains front-to-back,
or returning the tail as a `&[Value]` for read-only pattern matching,
would fix it. Flag only — defer.

## Deliberate complexity inspected and kept

- **`Tree` ownership in `cst.rs::Builder<'src>` (line 50)** — borrowing the
  source bytes is the cleanest way to call `utf8_text`; cloning all strings
  eagerly at build time would push the AST size up by ~3x. The owned AST
  (`ast.rs`) is built once per file and lives for the program's life.
- **`Callable` carries `unit: usize` instead of `&'a Unit`** (value.rs:14) —
  the `Interp` struct owns the cloned `Vec<Unit>`, so this avoids a
  lifetime parameter on `Callable`. Reasonable.
- **`tag_order: HashMap<String, usize>` (eval.rs:108)** — at link time the
  interpreter enumerates every case name across every unit into a single
  map. The alternative (per-unit `BTreeMap<String, usize>`) would force the
  comparator to know which unit it was in during comparison. Single map is
  cheaper.
- **`HashMap<String, String>` for aliases and `mod_index`
  (eval.rs:106-107)** — module paths are strings and lookups are by string.
  No reason to depart from `HashMap` here.
- **`fn text(&self, node: Node) -> String`** in `cst.rs:54` — clones all
  node text on read. Every alternative (`Cow`, interning) requires extra
  state; the corpus is small.
- **`Step` enum with `OK` / `Ret` variants** — `try` semantics need a
  third "return from enclosing defun" exit code distinct from a normal
  value. The two-variant enum is the minimal shape that supports it
  without a separate signal-passing protocol. Kept.

## Cross-class enumeration (per the lens)

The biggest "class" — duplicated lookup work in the evaluator — appears in
**five** call sites (eval_ident, resolve_local, resolve_in_unit,
resolve_callable_in, builtin-shadowing check), all of which linearly scan
`unit.defuns` and `unit.enum_cases`. **M5** names one fix that removes
all five.

The "empty branches / wrappers" class appears at **four** sites
(`list_higher` if/else with identical arms M1, `num_binop` if/else
with comment-only arms M2, `stable_sort_by` M3, `eval_logical` final
ternary M4). All are pure simplification wins.

The "two functions doing the same thing" class appears at **three** sites
(`Step::into_ok` L9, `apply_closure`/`apply_closure_bin` L8,
`resolve_call`/`eval_ident` M7). M7 is the meaningful one because it
also fixes the dispatch shape.
