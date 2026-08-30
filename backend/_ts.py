#!/usr/bin/env python3
"""Shared TypeScript compilation for the backend gates.

One module spells the `tsc` flags and owns the invocation, so the corpus gate
and the differential harness cannot drift apart flag by flag. A flag changed at
one site and not the other is the silent-green failure the gates exist to catch.
"""
import subprocess
from pathlib import Path

ROOT = Path(__file__).parent.parent
TSC = ROOT / "node_modules" / ".bin" / "tsc"


def tsc_flags(*, no_emit: bool) -> list[str]:
    flags = ["--strict", "--target", "es2020", "--module", "commonjs",
             "--typeRoots", str(ROOT / "node_modules" / "@types"), "--types", "node"]
    if no_emit:
        flags.insert(0, "--noEmit")
    return flags


def compile_ts(
    inputs: list[Path],
    *,
    no_emit: bool = False,
    out_dir: Path | None = None,
) -> subprocess.CompletedProcess:
    """Compile the emitted TS sources with the frozen flag set."""
    cmd = [str(TSC), *tsc_flags(no_emit=no_emit), *(str(p) for p in inputs)]
    if out_dir is not None:
        cmd += ["--outDir", str(out_dir)]
    return subprocess.run(cmd, capture_output=True, text=True)
