"""Self-hosted (pure-ASL) parser entry point for the CLI and benchmark.

The asl-parser package's ``reader_test.asl`` driver exports ``render-all`` —
parse then render-node, joined by newlines — which is the parser's only
observable output. ``run_asl``'s one-time transpile/py_compile/runpy cost lives
in the module-level singleton below so benchmark timing can exclude it.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HARNESS_DIR = ROOT / "packages" / "asl-parser" / "tests"

sys.path.insert(0, str(HARNESS_DIR))

from harness import run_asl  # noqa: E402

_ns = None


class NativeParserError(Exception):
    """A parse failure surfaced by the self-hosted parser runtime."""


def _driver() -> dict:
    global _ns
    if _ns is None:
        _ns = run_asl(HARNESS_DIR / "reader_test.asl")
    return _ns


def native_render(src: str) -> str:
    """Parse ``src`` with the self-hosted parser and render its verbose forms."""
    try:
        out = _driver()["render_all"](src)
    except Exception as exc:
        raise NativeParserError(str(exc)) from exc
    if not isinstance(out, str):
        raise NativeParserError(f"render_all returned {type(out).__name__}, expected str")
    return out
