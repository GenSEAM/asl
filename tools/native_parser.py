"""Self-hosted (pure-ASL) parser entry point for the CLI and benchmark.

The asl-parser package's ``reader_test.asl`` driver exports ``render-all`` —
parse then render-node, joined by newlines — which is the parser's only
observable output. It returns an AgentScript ``(Result String ParseError)``,
which the Python backend lowers to a tagged tuple, so a rejected source reaches
callers as ``NativeParserError`` carrying the offending line and column rather
than as an exception from deep inside the runtime. ``run_asl``'s one-time
transpile/py_compile/runpy cost lives in the module-level singleton below so
benchmark timing can exclude it.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HARNESS_DIR = ROOT / "packages" / "asl-parser" / "tests"

sys.path.insert(0, str(HARNESS_DIR))

from harness import run_asl  # noqa: E402

_ns = None


class NativeParserError(Exception):
    """A parse failure surfaced by the self-hosted parser runtime.

    `line` and `col` come from the offending token, so a caller can place the
    diagnostic where the source went wrong instead of at 1:1.
    """

    def __init__(self, message: str, line: int = 1, col: int = 1):
        super().__init__(message)
        self.message = message
        self.line = line
        self.col = col


def _driver() -> dict:
    global _ns
    if _ns is None:
        _ns = run_asl(HARNESS_DIR / "reader_test.asl")
    return _ns


def _unwrap(res) -> str:
    """The ``ok`` payload of the driver's Result, or the diagnostic it carries."""
    if not (isinstance(res, tuple) and res):
        raise NativeParserError(
            f"render-all returned {type(res).__name__}, expected a Result")
    if res[0] == "err":
        e = res[1]
        raise NativeParserError(e["msg"], e["line"], e["col"])
    if res[0] != "ok":
        raise NativeParserError(f"render-all returned an unexpected tag {res[0]!r}")
    out = res[1]
    if not isinstance(out, str):
        raise NativeParserError(
            f"render-all returned {type(out).__name__}, expected str")
    return out


def native_render(src: str) -> str:
    """Parse ``src`` with the self-hosted parser and render its verbose forms."""
    try:
        res = _driver()["render_all"](src)
    except NativeParserError:
        raise
    except Exception as exc:
        raise NativeParserError(str(exc)) from exc
    return _unwrap(res)
