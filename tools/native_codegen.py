"""Native AgentScript Rust Code Generator bridge (@pcp:d-8d4c).

Loads and runs the self-hosted Rust code generator (packages/asl-codegen)
compiled from pure AgentScript to Python, emitting standalone Rust programs.
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

from to_python import Transpiler  # noqa: E402
from modules import find  # noqa: E402

SRC_CODEGEN = ROOT / "packages" / "asl-codegen" / "src"
SRC_PARSER = ROOT / "packages" / "asl-parser" / "src"
SRC_CHECKER = ROOT / "packages" / "asl-checker" / "src"
EMIT_ASL = SRC_CODEGEN / "emit.asl"
RUNTIME = ROOT / "backend" / "runtime.py"

_NATIVE_CODEGEN_MODULE: dict[str, Any] | None = None


def get_native_codegen_module() -> dict[str, Any]:
    global _NATIVE_CODEGEN_MODULE
    if _NATIVE_CODEGEN_MODULE is not None:
        return _NATIVE_CODEGEN_MODULE

    emitted = Transpiler().transpile(
        EMIT_ASL.read_text(),
        path=EMIT_ASL,
        roots=[SRC_CODEGEN, SRC_PARSER, SRC_CHECKER]
    )
    with tempfile.TemporaryDirectory(dir="/tmp") as d:
        tmp = Path(d)
        (tmp / "runtime.py").write_text(RUNTIME.read_text())
        out = tmp / "native_cg.py"
        out.write_text(emitted)
        py_compile.compile(str(out), doraise=True)
        sys.path.insert(0, str(tmp))
        try:
            _NATIVE_CODEGEN_MODULE = runpy.run_path(str(out))
            return _NATIVE_CODEGEN_MODULE
        finally:
            sys.path.remove(str(tmp))


def native_emit_rust(
    src: str,
    *,
    path: Path | str | None = None,
    roots: list[Path | str] | None = None
) -> str:
    """Emits standalone Rust code for an AgentScript source using native asl-codegen."""
    mod = get_native_codegen_module()
    parse_fn = mod["ast__parse"]
    emit_fn = mod["emit_rust_program"]

    pres = parse_fn(src)
    if not (isinstance(pres, tuple) and len(pres) == 2 and pres[0] == "ok"):
        err = pres[1] if isinstance(pres, tuple) and len(pres) == 2 else pres
        raise RuntimeError(f"Native parse failed: {err}")
    root_forms = pres[1]

    # Resolve dependencies if path or roots are given
    dep_forms = []
    search_roots: list[Path] = []
    if path is not None:
        p = Path(path).resolve()
        search_roots.append(p.parent)
    if roots:
        search_roots.extend([Path(r).resolve() for r in roots])
    search_roots.append(ROOT / "grammar" / "corpus" / "modules")

    # Walk transitive imports if root has a module declaration
    if root_forms and isinstance(root_forms[0], tuple) and root_forms[0][0] == "top-module":
        root_mod = root_forms[0][1]
        imports_list = root_mod.get("imports", [])
        seen: set[str] = set()
        dep_order: list[Path] = []

        def walk_imports(pairs: list[Any]):
            for im in pairs:
                if isinstance(im, tuple) and len(im) >= 3 and im[0] == "pair":
                    target_path = im[1]
                elif isinstance(im, tuple) and len(im) == 2:
                    target_path = im[0]
                elif isinstance(im, dict):
                    target_path = im.get("first") or im.get("target")
                else:
                    continue
                if not target_path or target_path in seen:
                    continue
                seen.add(target_path)
                found = find(target_path, search_roots)
                if found is None:
                    continue
                dres = parse_fn(found.read_text())
                if dres[0] == "ok" and dres[1] and dres[1][0][0] == "top-module":
                    dmod = dres[1][0][1]
                    walk_imports(dmod.get("imports", []))
                    dep_order.append(found)

        walk_imports(imports_list)
        for dep_path in dep_order:
            dres = parse_fn(dep_path.read_text())
            if dres[0] == "ok" and dres[1]:
                dep_forms.append(dres[1][0])

    return emit_fn(root_forms, dep_forms)
