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


def params(type_str: str) -> list[str]:
    """The declared parameter types, split at nesting depth zero.

    Both splits have to respect depth or higher-order and constructed types are
    miscounted: a naive `split("->")` cuts inside `(fn [A] -> B)`, and a naive
    `split()` reads `(Map K V)` as three parameters. That miscount is not
    cosmetic — it is what the handbook shows an agent as the call shape.
    """
    depth, arrow = 0, -1
    for i, ch in enumerate(type_str):
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        elif ch == "-" and depth == 0 and type_str[i:i + 2] == "->":
            arrow = i
    lhs = (type_str if arrow < 0 else type_str[:arrow]).strip()
    if not lhs:
        return []
    out, cur, depth = [], "", 0
    for ch in lhs:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == " " and depth == 0:
            if cur.strip():
                out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


ARG_NAMES = ["a", "b", "c", "d", "e"]


def signature(b: dict) -> str:
    """`(name a b)` rendered from the declared type, so arity cannot drift."""
    if "..." in b["type"]:
        return f"({b['name']} a b …)"
    n = len(params(b["type"]))
    assert n <= len(ARG_NAMES), f"{b['name']}: arity {n} exceeds argument names"
    return f"({b['name']}{''.join(' ' + x for x in ARG_NAMES[:n])})"


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
        "# AgentScript Core — agent handbook",
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
        "  :export [f]                   ; NOTHING is public unless listed",
        "  :import [(other/mod :as o)])  ; members reached as o/name",
        "",
        "(defschema Point                ; a record",
        '  (:field x Int64 "Doc."))      ; doc required on every field',
        "",
        "(defenum Shape                  ; a closed union",
        '  (:case circle [(r Float64)] "Doc.")',
        '  (:case point  []            "Doc."))',
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
        "8. Anything that touches the outside returns a `Result`, and its caller declares "
        "the effects it reaches — transitively, so a wrapper declares them too.",
        "9. Every foreign call is fallible. A `defextern` returning `T` is called as "
        "`(Result T String)` — there is no form that yields a bare host value.",
        "",
        "## Handling failure",
        "",
        "```lisp",
        "(defun or-zero [(s String)] -> Int64",
        '  :doc "match takes an Option or a Result apart."',
        "  (match (string-to-int64 s)",
        "    ((some n) n)",
        "    ((none)   0)))",
        "",
        "(defun f [(s String)] -> (Result Int64 String)",
        '  :doc "try unwraps ok, or returns the err from f immediately."',
        '  (let [(n (try (option-to-result (string-to-int64 s) "bad")))]',
        "    (ok (* n 2))))",
        "```",
        "",
        "`try` is legal only inside a `defun` returning a `Result`. Prefer it over nested `match`.",
        "",
        "## Using another module",
        "",
        "Only `:export`ed names are reachable, and only through the alias.",
        "",
        "```lisp",
        "(module report/render",
        '  :doc "Render a tally line."',
        "  :export [line]",
        "  :import [(text/casing :as c)])",
        "",
        "(defun line [(w String)] -> String",
        '  :doc "Shout one word."',
        "  (c/shout w))                  ; alias/name, never the module path",
        "```",
        "",
        "## Talking to the outside",
        "",
        "`defentry` is the program's single entry point. Reading, writing and running "
        "programs are all fallible, so `try` does the unwrapping.",
        "",
        "```lisp",
        "(defun first-line [(path String)] -> (Result String String)",
        '  :doc "First line of a file."',
        "  :effects [fs]",
        '  (let [(text (try (file-read path)))]',
        '    (match (list-head (string-split text "\\n"))',
        "      ((some l) (ok l))",
        '      ((none)   (err "empty file")))))',
        "",
        "(defentry [(argv (List String))] -> (Result Unit String)",
        '  :doc "Print the commit, then the first line of the file named by argv."',
        "  :effects [console fs proc]",
        '  (let [(head (try (process-run "git" (list "rev-parse" "HEAD") "")))',
        '        (line (try (first-line (option-or (list-head argv) ""))))]',
        "    (try (print (.-stdout head)))   ; argv is a list — never a shell string",
        "    (println line)))",
        "```",
        "",
        "## Using a host library",
        "",
        "`:extern` names the host package, `defextern` declares one of its functions, "
        "and `defopaque` names a host type this language only passes along. **Every "
        "foreign call returns a `Result`** — the declared type is the success type.",
        "",
        "```lisp",
        "(module data/frames",
        '  :doc "Typed total boundary over the host dataframe library."',
        "  :export [row-count]",
        '  :extern [(py "polars" :as pl)])',
        "",
        "(defopaque DataFrame",
        '  :doc "A host value this language passes but cannot inspect.")',
        "",
        "(defextern pl/read-csv [(path String)] -> DataFrame",
        '  :doc "Read a CSV into a dataframe."',
        "  :target :py",
        '  :symbol "read_csv")        ; the host spelling, which kebab-case cannot reach',
        "",
        "(defextern pl/height [(df DataFrame)] -> Int64",
        '  :doc "Row count of a dataframe."',
        "  :target :py)",
        "",
        "(defun row-count [(path String)] -> (Result Int64 String)",
        '  :doc "Rows in a CSV, or the host failure as a value."',
        "  (let [(df (try (pl/read-csv path)))]",
        "    (ok (try (pl/height df)))))",
        "```",
        "",
        "A module with any `defextern` belongs to that one ecosystem: it is not portable, "
        "and a transpiler for another target refuses it by name.",
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
        "| `(string-length (file-read p))` | `(string-length (try (file-read p)))` — "
        "every outside call is a `Result` |",
        '| `(process-run "git rev-parse HEAD" ...)` | '
        '`(process-run "git" (list "rev-parse" "HEAD") "")` — argv is a list |',
        "| a `defun` calling `println` with no `:effects` | `:effects [console]` — "
        "name the effect you reach |",
        "| `:effects [io]` | `io` is not an effect; it is `console`, `stdin`, `fs`, "
        "`env` or `proc` |",
        "| `(defextern f [(x Int64)] -> Int64 :doc \"…\")` | add `:target` — a foreign "
        "declaration names its ecosystem |",
        "",
        "## Forms",
        "",
        f"- Declarations: {', '.join('`' + x + '`' for x in sf['declarations'])}",
        f"- Expressions: {', '.join('`' + x + '`' for x in sf['expressions'])}",
        f"- Constructors: {', '.join('`' + x + '`' for x in sf['constructors'])}",
        f"- Patterns: {', '.join('`' + x + '`' for x in sf['patterns'])}, "
        "a literal, a name (binds), or `_`",
        f"- Effects: {', '.join('`' + x + '`' for x in p['effects'])} — the only names "
        "`:effects` accepts. Declare what you reach and nothing more: a target "
        "that cannot provide an effect refuses the module before it is built "
        "(a browser has `console` only).",
        "",
        "## Types",
        "",
        f"- Primitive: {', '.join('`' + x + '`' for x in p['types']['primitive'])}",
        f"- Constructed: {', '.join('`(' + x + ' …)`' for x in p['types']['constructed'])}",
        f"- `Int` means `Int64`.",
        "- Built-in records, read with `.-field`: "
        + "; ".join(f"`{n}` (" + ", ".join(f"`.-{f[0]}`" for f in fs) + ")"
                    for n, fs in p["types"]["records"].items())
        + ".",
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


def validate_prelude() -> list[str]:
    """Everything about prelude.json that must hold before anything is generated.

    Two classes of defect, both of which surface far from their cause otherwise.
    A lowering template must format cleanly at its declared arity — literal
    braces are the trap, since a Python empty-dict lowering of `{}` is read as a
    placeholder and fails at transpile time. And an effect name must be one the
    top-level `effects` list declares, or it reaches the checker as a rule about
    an effect that does not exist.
    """
    bad = []
    declared_effects = set(PRELUDE["effects"])
    for b in PRELUDE["builtins"]:
        # An effect name no declaration list mentions is a typo that would reach
        # the checker as a rule about an effect that does not exist.
        for eff in b.get("effects", ()):
            if eff not in declared_effects:
                bad.append(f"{b['name']}: undeclared effect {eff!r}")
        n = len(params(b["type"]))
        for tgt in ("py", "ts", "rs", "sw"):
            tpl = b.get(tgt)
            if tpl is None:
                bad.append(f"{b['name']}: no {tgt} lowering")
                continue
            try:
                if "{*}" not in tpl:
                    tpl.format(*[f"a{i}" for i in range(n)])
            except Exception as exc:
                bad.append(f"{b['name']} [{tgt}] {tpl!r}: {exc}")
    return bad


# The handbook is resent on every model call, so its size is the running cost of
# a whole measurement run. Gated in bytes rather than tokens because bytes need
# no tokenizer and cannot drift with one: 14,995 B measured at 4,531 tokens on
# 2026-08-21, so the ceiling below is about 5,300 tokens. Raise it deliberately,
# with a re-measurement, or not at all.
HANDBOOK_MAX_BYTES = 17_500


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

    broken = validate_prelude()
    if broken:
        print("PRELUDE DEFECTS:")
        for b in broken:
            print("  " + b)
        return 1

    hb = handbook()
    if len(hb.encode()) > HANDBOOK_MAX_BYTES:
        print(f"HANDBOOK TOO LARGE: {len(hb.encode())}B exceeds "
              f"{HANDBOOK_MAX_BYTES}B. It is resent on every call; either cut it "
              f"or raise the ceiling with a fresh token measurement.")
        return 1
    stale = write(HANDBOOK, hb, args.check)

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
