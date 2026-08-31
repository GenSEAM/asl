#!/usr/bin/env python3
"""Span coverage over the interpreter's failable `Expr` variants (D4).

The regressible number is variants-with-span / failable variants, computed from
`ast.rs`. Four `Expr` variants (`Float`, `Str`, `Bool`, `Unit`) can never reach a
runtime `Err` site, so they carry no span and are excluded; the failable denominator
is 13. Coverage of the *value* of a span (that its error path prints a real,
non-zero location) is enforced by the functional test `tools/tests/test_interp_diag.py`,
not by this fraction.

The lock is exact-match (D7): `--check` fails on ANY difference — up or down — and
`--write` records a new figure deliberately, in the commit that earns it.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
AST = ROOT / "crates" / "agentscript-interp" / "src" / "ast.rs"
LOCK = ROOT / "crates" / "agentscript-interp" / "span.lock"

# The 4 variants that cannot reach an Err site, each with its reason (D4).
EXCLUDED = {
    "Float": "a plain f64 evaluation never errors",
    "Str": "a string literal evaluation never errors",
    "Bool": "a bool literal evaluation never errors",
    "Unit": "the unit literal evaluation never errors",
}

# The 13 failable variants. `Int` carries its span on the IntLit payload.
FAILABLE = [
    "Ident", "Qualified", "Call", "FieldAccess", "If", "Cond", "Match", "Try",
    "Ctor", "Record", "Let", "Int", "Fn",
]


def _carrying_from(text: str) -> list[str]:
    """Failable `Expr` variant names whose declaration carries a `span` field."""
    # The Expr enum: capture each `Name { ... }` block and its fields.
    expr_start = text.index("pub enum Expr")
    expr_block = text[expr_start:]

    carrying = []

    # Match `        Name { ... }` struct variants inside the Expr enum.
    # The enum's variants are indented 4 spaces; struct bodies 8.
    # Split the enum into its top-level variant entries.
    variant_re = re.compile(r"^\s{4}(\w+)\s*(\{|\()", re.M)
    for m in variant_re.finditer(expr_block):
        name, brace = m.group(1), m.group(2)
        if name in EXCLUDED:
            continue
        seg = expr_block[m.end():]
        if brace == "{":
            # find the closing brace at depth 1
            depth = 1
            i = 0
            while depth and i < len(seg):
                if seg[i] == "{":
                    depth += 1
                elif seg[i] == "}":
                    depth -= 1
                i += 1
            body = seg[:i]
            if re.search(r"\bspan\s*:", body):
                carrying.append(name)
        else:
            # tuple variant; `Int(IntLit)` is handled via its payload struct
            if name == "Int":
                if "IntLit" in seg.split(")", 1)[0] and _intlit_has_span(text):
                    carrying.append(name)
    return carrying


def _intlit_has_span(text: str) -> bool:
    m = re.search(r"pub struct IntLit \{", text)
    if not m:
        return False
    seg = text[m.end():]
    depth = 1
    i = 0
    while depth and i < len(seg):
        if seg[i] == "{":
            depth += 1
        elif seg[i] == "}":
            depth -= 1
        i += 1
    return bool(re.search(r"\bspan\s*:", seg[:i]))


def measure() -> tuple[int, list[str]]:
    carrying = _carrying_from(AST.read_text())
    covered = [v for v in FAILABLE if v in carrying]
    return len(covered), covered


def main() -> int:
    write = "--write" in sys.argv[1:]
    covered, names = measure()
    payload = {
        "denominator": len(FAILABLE),
        "covered": covered,
        "excluded": EXCLUDED,
        "covered_variants": names,
    }
    if write:
        LOCK.write_text(json.dumps(payload, indent=1) + "\n")
        print(f"wrote {LOCK}: {covered}/{len(FAILABLE)} failable variants carry a span")
        return 0

    if not LOCK.exists():
        sys.stderr.write(f"span_coverage: {LOCK} missing; run with --write to record\n")
        return 2

    recorded = json.loads(LOCK.read_text())
    if recorded.get("covered") != covered or recorded.get("denominator") != len(FAILABLE):
        sys.stderr.write(
            f"span_coverage: measured {covered}/{len(FAILABLE)} but lock records "
            f"{recorded.get('covered')}/{recorded.get('denominator')} ({LOCK}); "
            f"exact-match (D7) — --write only in the commit that earns the figure\n")
        return 1
    print(f"{covered}/{len(FAILABLE)} failable variants carry a span")
    return 0


if __name__ == "__main__":
    sys.exit(main())
