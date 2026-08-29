#!/usr/bin/env python3
"""Generate every artifact that restates the vocabulary, from prelude.json.

The vocabulary was duplicated across the specification tables, both grammars,
the highlight queries, the closure gate and (about to be) the backends. Six
copies of one list is six chances to disagree, and it is what made the language
hard to keep unambiguous: any clarification had to be applied six times.

This script owns the copies. Edit prelude.json, run this, commit the result.

  --check  exit non-zero if a generated artifact is stale (for CI)
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).parent
PRELUDE = json.loads((ROOT / "prelude.json").read_text())
SPEC = ROOT.parent / "AGENT_SPEC_CORE.md"
HANDBOOK = ROOT / "HANDBOOK.md"

SEC_ORDER = ["Arithmetic", "Comparison and logic", "String", "Numeric conversion",
             "List", "Map", "Option, Result, Pair", "I/O"]


def signature(b: dict) -> str:
    """`(name a b)` rendered from the declared type, so arity cannot drift."""
    lhs = b["type"].split("->")[0].strip()
    n = 0 if not lhs else len(lhs.split())
    names = ["a", "b", "c", "d"][:n]
    if "..." in b["type"]:
        return f"({b['name']} a b …)"
    return f"({b['name']}{''.join(' ' + x for x in names)})"


def spec_tables() -> str:
    out = []
    for i, sec in enumerate(SEC_ORDER, start=1):
        items = [b for b in PRELUDE["builtins"] if b["sec"] == sec]
        out.append(f"### 6.{i} {sec}\n")
        out.append("| Form | Type | Meaning |")
        out.append("|---|---|---|")
        for b in items:
            note = b["doc"]
            out.append(f"| `{signature(b)}` | `{b['type']}` | {note} |")
        out.append("")
    return "\n".join(out)


def handbook() -> str:
    p = PRELUDE
    sf = p["special_forms"]
    lines = [
        "# AgentS-Core — agent handbook",
        "",
        "**Generated from `prelude/prelude.json`. Do not edit.**",
        "",
        f"Language version {p['version']}. This is the complete vocabulary: if a name is not on "
        "this page, it does not exist. Write nothing else.",
        "",
        "## Shape",
        "",
        "```lisp",
        "(module my/mod                  ; every file is a module",
        '  :doc "One sentence."          ; required',
        "  :export [f Point]             ; NOTHING is public unless listed; a",
        "                                ;   PascalCase entry exports a type",
        "  :import [(other/mod :as o)])  ; o/name for a value, o/Type for a type",
        "",
        "(defschema Point                ; a record",
        '  (:field x Int64 "Doc."))      ; doc required on every field',
        "",
        "(defenum Shape                  ; a closed union",
        '  (:case circle [(r Float64)] "Doc.")',
        '  (:case point  []            "Doc."))',
        "",
        "(defun area [(s o/Shape)] -> Float64  ; an imported type in a signature;",
        '  :doc "Doc."                         ;   its cases are (o/circle r)',
        "  0.0)",
        "",
        "(defun {A} id [(x A)] -> A      ; {A} binds a type variable",
        '  :doc "Required when exported."',
        "  x)",
        "```",
        "",
        "## Rules that have no exceptions",
        "",
        "1. `if` takes exactly three parts — condition, then, else. There is no one-armed `if`.",
        "2. `cond` must end with `:else`. `match` must cover every case.",
        "3. Bindings never change. There is no assignment.",
        "4. Numbers never convert implicitly. Mixing `Int64` and `Float64` is an error.",
        "5. Lookups that can fail return `(Option T)`. They never throw.",
        "6. Read a record field with `(.-field r)`. Build one with `(Point :x 1 :y 2)`.",
        "7. A name is a type variable only if it appears in that declaration's `{ }`.",
        "",
        "## Handling failure",
        "",
        "```lisp",
        "(match (string-to-int64 s)      ; take apart an Option or Result",
        "  ((some n) n)",
        "  ((none)   0))",
        "",
        "(defun f [(s String)] -> (Result Int64 String)",
        '  :doc "try unwraps ok, or returns the err from f immediately."',
        '  (let [(n (try (option-to-result (string-to-int64 s) "bad")))]',
        "    (ok (* n 2))))",
        "```",
        "",
        "`try` is legal only inside a `defun` returning a `Result`. Prefer it over nested `match`.",
        "",
        "## Never write this",
        "",
        "| Wrong | Right |",
        "|---|---|",
        "| `(if c x)` | `(if c x y)` — else is required |",
        "| `(set! x 1)` | there is no assignment; bind a new name with `let` |",
        "| `(+ 1 2.0)` | `(+ 1 (float64-to-int64 2.0))` — no implicit conversion |",
        "| `(.x p)` | `(.-x p)` — the dash is part of field access |",
        "| `(defun f (x Int64) ...)` | `(defun f [(x Int64)] ...)` — parameters are a vector |",
        "| `(string->int64 s)` | `(string-to-int64 s)` — `->` is the return arrow only |",
        "| `(nth xs 0)` | `(list-get xs 0)` — only names on this page exist |",
        "",
        "## Forms",
        "",
        f"- Declarations: {', '.join('`' + x + '`' for x in sf['declarations'])}",
        f"- Expressions: {', '.join('`' + x + '`' for x in sf['expressions'])}",
        f"- Constructors: {', '.join('`' + x + '`' for x in sf['constructors'])}",
        f"- Patterns: {', '.join('`' + x + '`' for x in sf['patterns'])}, "
        "a literal, a name (binds), or `_`",
        "",
        "## Types",
        "",
        f"- Primitive: {', '.join('`' + x + '`' for x in p['types']['primitive'])}",
        f"- Constructed: {', '.join('`(' + x + ' …)`' for x in p['types']['constructed'])}",
        f"- `Int` means `Int64`.",
        "",
        "## Vocabulary",
        "",
        f"All {len(p['builtins'])} names. Nothing else exists.",
        "",
    ]
    for sec in SEC_ORDER:
        items = [b for b in p["builtins"] if b["sec"] == sec]
        lines += [f"### {sec}", "", "| Form | Type | Meaning |", "|---|---|---|"]
        for b in items:
            lines.append(f"| `{signature(b)}` | `{b['type']}` | {b['doc']} |")
        lines.append("")
    return "\n".join(lines)


def validate_templates() -> list[str]:
    """Every lowering template must format cleanly at its declared arity.

    Literal braces are the trap: a Python empty-dict lowering of `{}` is read as
    a format placeholder and fails at transpile time, far from its cause. Braces
    intended literally must be doubled in prelude.json.
    """
    bad = []
    for b in PRELUDE["builtins"]:
        lhs = b["type"].split("->")[0].strip()
        n = 0 if not lhs else len(lhs.split())
        for tgt in ("py", "js", "rs"):
            tpl = b.get(tgt)
            if tpl is None:
                bad.append(f"{b['name']}: no {tgt} lowering")
                continue
            try:
                if "{*}" not in tpl:
                    tpl.format(*[f"a{i}" for i in range(max(n, 4))])
            except Exception as exc:
                bad.append(f"{b['name']} [{tgt}] {tpl!r}: {exc}")
    return bad


def write(path: Path, content: str, check: bool) -> bool:
    """Returns True when stale."""
    old = path.read_text() if path.exists() else None
    if old == content:
        return False
    if check:
        print(f"STALE: {path}")
        return True
    path.write_text(content)
    print(f"wrote {path} ({len(content)}B)")
    return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    broken = validate_templates()
    if broken:
        print("BROKEN LOWERING TEMPLATES:")
        for b in broken:
            print("  " + b)
        return 1

    stale = write(HANDBOOK, handbook(), args.check)

    spec = SPEC.read_text()
    head, _, rest = spec.partition("## 6. Closed vocabulary")
    body_tail = rest.split("## 7. Worked example", 1)[1]
    intro = ("## 6. Closed vocabulary\n\n"
             "Every builtin, with its type. Nothing outside this table and §4-5 exists in Core.\n\n"
             "**Generated from `prelude/prelude.json`** — edit there, not here.\n\n")
    new_spec = head + intro + spec_tables() + "## 7. Worked example" + body_tail
    stale |= write(SPEC, new_spec, args.check)

    if args.check and stale:
        print("\nRun: .venv/bin/python prelude/generate.py")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
