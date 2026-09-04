"""Native AgentScript Semantic Checker bridge (@pcp:d-8d4c).

Loads and runs the self-hosted semantic type checker (packages/asl-checker)
compiled from pure AgentScript to Python, adapting diagnostics to match
the reference checker.resolve.Diagnostic format.
"""
from __future__ import annotations

import py_compile
import runpy
import sys
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))
sys.path.insert(0, str(ROOT / "grammar"))
sys.path.insert(0, str(ROOT / "checker"))

from to_python import Transpiler  # noqa: E402
from resolve import Diagnostic  # noqa: E402

SRC_CHECKER = ROOT / "packages" / "asl-checker" / "src"
SRC_PARSER = ROOT / "packages" / "asl-parser" / "src"
CHECK_ASL = SRC_CHECKER / "check.asl"
RUNTIME = ROOT / "backend" / "runtime.py"

_NATIVE_MODULE: dict[str, Any] | None = None


def _get_native_module() -> dict[str, Any]:
    global _NATIVE_MODULE
    if _NATIVE_MODULE is not None:
        return _NATIVE_MODULE

    emitted = Transpiler().transpile(
        CHECK_ASL.read_text(),
        path=CHECK_ASL,
        roots=[SRC_CHECKER, SRC_PARSER]
    )
    with tempfile.TemporaryDirectory(dir="/tmp") as d:
        tmp = Path(d)
        (tmp / "runtime.py").write_text(RUNTIME.read_text())
        out = tmp / "native_cand.py"
        out.write_text(emitted)
        py_compile.compile(str(out), doraise=True)
        sys.path.insert(0, str(tmp))
        try:
            _NATIVE_MODULE = runpy.run_path(str(out))
            return _NATIVE_MODULE
        finally:
            sys.path.remove(str(tmp))


def _adapt_diags(raw_diags: list[Any]) -> list[Diagnostic]:
    out: list[Diagnostic] = []
    for d in raw_diags:
        if isinstance(d, Diagnostic):
            out.append(d)
        elif isinstance(d, dict):
            out.append(Diagnostic(
                code=str(d.get("code", "unknown")),
                message=str(d.get("message", "")),
                line=int(d.get("line", 1)),
                col=int(d.get("col", 1)),
                path=str(d.get("path", "")),
            ))
        elif isinstance(d, tuple) and len(d) >= 2:
            # Fallback for tuple representation
            out.append(Diagnostic(
                code=str(d[0]),
                message=str(d[1]),
                line=1,
                col=1,
                path="",
            ))
    return out


def native_check_source(src: str, path: str = "<source>", roots: list[Path] | None = None) -> list[Diagnostic]:
    """Check an AgentScript source string using the self-hosted semantic checker."""
    mod = _get_native_module()
    check_fn = mod.get("check__check_source") or mod.get("check_source")
    if not check_fn:
        raise RuntimeError("native check_source not found in compiled checker candidate")
    raw = check_fn(src, {}, path)
    return _adapt_diags(raw)


def native_check_file(path: Path | str, roots: list[Path] | None = None) -> list[Diagnostic]:
    """Check an AgentScript source file using the self-hosted semantic checker."""
    p = Path(path).resolve()
    mod = _get_native_module()
    check_file_fn = mod.get("check__check_file_mut") or mod.get("check_file_mut")
    if not check_file_fn:
        raise RuntimeError("native check_file! not found in compiled checker candidate")
    search_roots = [str(r.resolve() if isinstance(r, Path) else r) for r in (roots or [])]
    res = check_file_fn(str(p), search_roots)
    if isinstance(res, tuple) and len(res) == 2:
        tag, val = res
        if tag == "ok" and isinstance(val, list):
            return _adapt_diags(val)
        if tag == "err":
            return [Diagnostic(code="io", message=str(val), line=1, col=1, path=str(p))]
    return _adapt_diags(res if isinstance(res, list) else [])
