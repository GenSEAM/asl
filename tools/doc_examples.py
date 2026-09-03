#!/usr/bin/env python3
"""Parse every AgentScript example embedded in the project's Markdown.

Documentation drifted away from the language repeatedly and silently, because a
fenced block is not compiled by anything: `web/public/llms.txt` taught
`(:export ...)`, `Ok`/`Err` and `zip-with`; `docs/BEST_PRACTICES.md` taught
`defextern`; `docs/COMPACT_SYNTAX.md` taught `(schema Point [x:Num y:Num])`.
None of it parses, and every gate was green.

A block is checked when it is fenced ```lisp or ```agentscript. A block that is
deliberately not valid — a sketch of a form the language does not have yet, or a
fragment shown to be wrong — opts out with a marker on the line before the
fence:

    <!-- not-agentscript: reason -->

The reason is mandatory: an opt-out with no stated cause is how a broken example
hides. Fragments are accepted too — a block that parses as a sequence of
top-level forms passes, and one that does not is retried as the body of a
throwaway declaration before it is called a failure, so a bare expression like
`(str "a" b)` need not be wrapped by hand.

  tools/doc_examples.py            report every block and its verdict
  tools/doc_examples.py --quiet    print only failures and the summary

It parses with the self-hosted parser (`packages/asl-parser`, via
`tools.native_parser`), the engine the language ships. The gate is about whether
a published example is a program, not about which parser decides that.
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from tools.native_parser import NativeParserError, native_render  # noqa: E402

FENCE = re.compile(r"^```(lisp|agentscript)\s*$(.*?)^```\s*$", re.M | re.S)
OPT_OUT = re.compile(r"<!--\s*not-agentscript:\s*(.+?)\s*-->\s*$", re.M)

SKIP_DIRS = {"node_modules", ".venv", ".git", "target", "dist", "archive",
             "__pycache__", ".tokensave", ".pytest_cache"}


def markdown_files() -> list[Path]:
    return sorted(p for p in ROOT.rglob("*.md")
                  if not SKIP_DIRS & set(p.relative_to(ROOT).parts))


def blocks(text: str):
    """(line number, source, opt-out reason or None) for each fenced block."""
    for m in FENCE.finditer(text):
        before = text[:m.start()]
        preceding = before.rsplit("\n", 2)[-2] if before.count("\n") >= 2 else ""
        reason = OPT_OUT.search(preceding)
        yield before.count("\n") + 1, m.group(2), reason.group(1) if reason else None


def parses(src: str) -> str | None:
    """None when the block is well-formed; otherwise the parser's complaint.

    A block is tried whole, then as a declaration body, because documentation
    quotes expressions as often as it quotes whole modules."""
    try:
        native_render(src)
        return None
    except NativeParserError as whole:
        wrapped = f'(defun agentscript-doc-example [] -> Unit\n{src}\n())'
        try:
            native_render(wrapped)
            return None
        except NativeParserError:
            return f"line {whole.line}:{whole.col}: {whole.message}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    failures, checked, skipped = [], 0, 0
    for path in markdown_files():
        rel = path.relative_to(ROOT)
        for line, src, reason in blocks(path.read_text(encoding="utf-8")):
            if reason is not None:
                skipped += 1
                if not args.quiet:
                    print(f"{rel}:{line}  skip  ({reason})")
                continue
            checked += 1
            problem = parses(src)
            if problem:
                failures.append(f"{rel}:{line}: {problem}")
            if not args.quiet:
                print(f"{rel}:{line}  {'ok' if not problem else 'FAIL'}")

    print()
    for f in failures:
        print("  " + f)
    print(f"\n{checked} block(s) checked, {skipped} opted out, {len(failures)} failure(s)")
    return len(failures)


if __name__ == "__main__":
    sys.exit(main())
