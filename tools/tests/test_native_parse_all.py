"""Phase-gate test: every real package ``.asl`` source parses through the
self-hosted parser.

The self-hosted lexer used to recurse once per character, which overflowed
CPython's recursion limit on real files (the 20-file red list was recorded in
``.plans/phase-4-scalability/``). It now scans iteratively, and since Phase 6 so
do the reader and the renderer, so every file must render non-empty verbose
output whatever its size or nesting depth.

This asserts only that the parser accepts the sources.
``tools/tests/test_native_parity.py`` is what checks the render against the
reference grammar, and what checks the sources the parser must *reject*.
"""

from pathlib import Path

import pytest

from tools.native_parser import native_render

ROOT = Path(__file__).resolve().parent.parent.parent


def _package_files():
    # A wrong ROOT must be diagnosed, not reported as "no files found".
    assert (ROOT / "packages").is_dir(), (
        f"ROOT resolved to {ROOT}; expected the repo root with a packages/ directory"
    )
    return sorted((ROOT / "packages").rglob("*.asl"))


ASL_FILES = _package_files()


def test_packages_walk_finds_sources():
    """Guards the parametrize: a broken glob must fail loudly, not report green."""
    assert len(ASL_FILES) > 0, "no .asl files found under packages/"


@pytest.mark.parametrize(
    "path",
    [pytest.param(p, id=str(p.relative_to(ROOT))) for p in ASL_FILES],
)
def test_native_render_all_files(path):
    rel = path.relative_to(ROOT)
    try:
        out = native_render(path.read_text())
    except Exception as exc:
        pytest.fail(f"native_render failed for {rel}: {exc}")
    assert isinstance(out, str), f"render_all returned {type(out).__name__} for {rel}"
    assert out.strip(), f"render_all returned empty output for {rel}"
