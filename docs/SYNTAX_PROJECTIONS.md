# ASL Syntax & Projections (ASL Standard vs ASL Verbose)

**Normative text lives in [`AGENT_SPEC_CORE.md`](../AGENT_SPEC_CORE.md) §2.1**, which is generated
from `prelude/prelude.json`. This page is orientation; where the two differ, the specification wins
and this page is the bug.

AgentScript (ASL) is compact by default. The concise syntax (`df`, `dfs`, `dfe`, `mt`, `Str`, `I64`, `F64`)
is simply **AgentScript (ASL)** — what the toolchain writes to disk, puts on the wire, and generates
into agent-facing artifacts.

**ASL Verbose** is an alternate projection intended exclusively for human inspection and debugging.
The tool `asl view` displays a module in its verbose spelling on screen without touching the file,
and `asl transcode --to verbose` converts it when debugging. Both grammars produce the exact same AST
from either spelling.

**What it buys, measured.** Fewer bytes, and not fewer tokens. Across every fixture in
`grammar/corpus/valid`, under `cl100k_base`: 58,175 bytes against 56,091, a 3.6% saving, and
15,931 tokens against 15,931 — no saving at all. A BPE vocabulary already encodes the long form
cheaply, so `(defun` and `(df` are one token each and ` :export` and ` :x` are two each.
`bench/token_projection.py` is the measurement.

Do not confuse this with the wire and data formats, where the saving is real and large: removing
*structure* — quotes around keys, commas, braces, field names repeated on every row — takes a
command frame from 51 tokens to 18, which `bench/token_frames.py` measures. Structural compaction
works. Abbreviating identifiers does not.

## The spellings

| ASL (Standard) | ASL Verbose | Significant in |
|---|---|---|
| `df` | `defun` | declaration head |
| `dfs` | `defschema` | declaration head |
| `dfe` | `defenum` | declaration head |
| `mt` | `match` | expression head |
| `:d` | `:doc` | module header, `defun` |
| `:x` | `:export` | module header |
| `:i` | `:import` | module header |
| `:a` | `:as` | import spec |
| `:f` | `:field` | `defschema` field |
| `:c` | `:case` | `defenum` case |

`def`, `schema` and `enum` are also accepted for the three declaration heads, as a compatibility
surface carrying no meaning of its own.

Types: `I64` is `Int64`, `I32` is `Int32`, `F64` is `Float64`, `Str` is `String`. `Int`, `Num` and
`Float` are older aliases and still resolve. `F32` is a **reserved width name** — Core has no
32-bit float, so it resolves to `Float64` and carries none of a narrower type's behaviour. It
exists so that source written against a host that does have the width parses today.

## The rule that matters

**A short spelling counts only in the position named above.** Everywhere else it is an ordinary
atom. A record whose field is called `x` is built with `(P :x 1)` and that key means a field, not
an export list.

This is why the toolchain converts projections through the parse tree rather than by substituting
text. A regex that rewrites `:x` wherever it appears turns that record into `(P :export 1)`, which
is a different program.

## Example

```lisp
(module math/vector
  :d "Dot product and Euclidean norm over coordinate lists."
  :x [Point dot norm-squared])

(dfs Point
  (:f x F64 "Horizontal coordinate")
  (:f y F64 "Vertical coordinate"))

(df dot [(a (List F64)) (b (List F64))] -> F64
  :d "Sum of the pairwise products of two coordinate lists."
  (list-sum (map (fn [p] (* (.-first p) (.-second p))) (zip a b))))

(df norm-squared [(v (List F64))] -> F64
  :d "The squared Euclidean norm, which needs no square root."
  (dot v v))
```

Note what the example does **not** do: there is no `sqrt` and no `list-zip-with`, because neither
is in the vocabulary. `prelude/HANDBOOK.md` is the complete list, and
`.venv/bin/python grammar/closure_audit.py` fails on any example that reaches outside it.
