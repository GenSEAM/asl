# ASL Syntax & Projections

The language rules live in one place: the `language` topic of `asl/grammar/tools.asn`, printed by `asl '(:help :topic language)'` and rendered into [`llms.txt`](../llms.txt). This page is orientation on short spellings; where the two differ, the topic wins and this page is the bug.

ASL has one saved form, the compact one. A verbose projection (`defun`, `defschema`, `defenum`, `df`, `dfs`, `dfe`) is not a saved form: the stage-0 host rejects `(defun ...)`, `(defschema ...)`, `(df ...)` and `(dfs ...)` with ERR_UNSUPPORTED_TOPLEVEL and `dfe` with ERR_UNKNOWN_SYMBOL (`asl/host/out/asl-host check`, 2026-10-14). No tool renders a verbose view today; such a view is a target.

## The spellings the host accepts

| Spelling | Longer form also accepted | Significant in |
|---|---|---|
| `fn name a: T -> R` (bare line) | none | declaration |
| `(schema Name (:f field Type "doc") ...)` | `:field` for `:f` | declaration |
| `enum Name (case a: T) ...` or `(enum Name (:c case [params] "doc") ...)` | none | declaration |
| `mt` | `match` | expression head |
| `:x` | none (`:export` does not export) | module header |
| `:i`, `:a` | none | module header, import spec |

Canonical type names are `Int64`, `Float64`, `String`, `Bool`, `(List T)`; the host also reads `I64`, `F64`, `Str`, `Int` and `Float` as the same types (`host/src/types.c`). It checks argument and return types it knows (ERR_TYPE_MISMATCH), but an unknown type name is not reported: a function typed `Zzzq -> Zzzq` passes `asl-host check` and runs (2026-10-14).

`:d` docstrings are retired: the reader rejects them with ERR_READ_DOC. A doc is a `(:doc :symbol "path#name" :text "...")` row in the package's `doc.asn`.

## The rule that matters

**A short spelling counts only in the position named above.** Everywhere else it is an ordinary atom. A record whose field is called `x` is built with `(Point :x 1.5 :y 2.0)`, and that key means a field, not an export list.

So a tool that converts spellings has to work on the parse tree, not on text. A regex that rewrites `:x` wherever it appears turns that record into `(Point :export 1.5 ...)`, which is a different program.

## Example

```asl
(module math/vector
  :x [Point dot normSquared runTests])

(schema Point
  (:f x Float64)
  (:f y Float64))

fn dot a: (List Float64) b: (List Float64) -> Float64
  (listSum (map (fn [p] (mt p ((pair u v) (* u v)))) (zip a b)))

fn normSquared v: (List Float64) -> Float64
  (dot v v)

fn runTests -> Bool
  (do (assert (= (dot (list 1.0 2.0) (list 3.0 4.0)) 11.0) "dot") (assert (= (normSquared (list 3.0 4.0)) 25.0) "norm") (assert (= (Point :x 1.5 :y 2.0).x 1.5) "x is a field here") true)
```

`zip` yields `(pair a b)` values, taken apart with `mt`. A record field reads as `p.x`, or `(expr).x` on an expression; the older `(.-x p)` is rejected with ERR_READ_FIELD. There is no `list-zip-with` or `listZipWith`, because neither is in the vocabulary. The stage-0 host binds exactly the builtins defined in `host/src` and the public fns of `prelude/prelude.asl`, and `host/out/asl-host check` rejects any other name with ERR_UNKNOWN_SYMBOL. This example passes `asl-host test` (3 assertions, 2026-10-14).
