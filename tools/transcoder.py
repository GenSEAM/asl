#!/usr/bin/env python3
"""Bidirectional AST Transcoder: Nano <-> Verbose Projections (@pcp:d-1eed, @pcp:r-8d8e)."""

import sys
import re
from pathlib import Path


def to_ultra_nano(text: str) -> str:
    """Compacts ASL code into Ultra-Nano format for agent token savings."""
    res = text
    # Structural keywords
    res = re.sub(r'\(defschema\b', '(dfs', res)
    res = re.sub(r'\(defenum\b', '(dfe', res)
    res = re.sub(r'\(defun\b', '(df', res)
    res = re.sub(r'\(match\b', '(mt', res)
    # Options & attributes
    res = re.sub(r'\(:field\b', '(:f', res)
    res = re.sub(r'\(:case\b', '(:c', res)
    res = re.sub(r':doc\b', ':d', res)
    res = re.sub(r':export\b', ':x', res)
    res = re.sub(r':import\b', ':i', res)
    res = re.sub(r':as\b', ':a', res)
    return res


def to_verbose(text: str) -> str:
    """Expands Ultra-Nano ASL code into fully self-describing Verbose format for humans."""
    res = text
    res = re.sub(r'\(dfs\b', '(defschema', res)
    res = re.sub(r'\(dfe\b', '(defenum', res)
    res = re.sub(r'\(df\b', '(defun', res)
    res = re.sub(r'\(mt\b', '(match', res)
    res = re.sub(r'\(:f\b', '(:field', res)
    res = re.sub(r'\(:c\b', '(:case', res)
    res = re.sub(r':d\b', ':doc', res)
    res = re.sub(r':x\b', ':export', res)
    res = re.sub(r':i\b', ':import', res)
    res = re.sub(r':a\b', ':as', res)
    return res


def transcode_file(path: Path, target_dialect: str = "nano", in_place: bool = False) -> str:
    """Transcodes a file between nano and verbose projections."""
    content = path.read_text(encoding="utf-8")
    if target_dialect in ("nano", "ultra-nano", "compact"):
        out = to_ultra_nano(content)
    else:
        out = to_verbose(content)

    if in_place:
        path.write_text(out, encoding="utf-8")
    return out


def run_transcode_cli(args) -> int:
    path = Path(args.file)
    if not path.exists():
        print(f"Error: file {path} not found", file=sys.stderr)
        return 1

    target = "verbose" if getattr(args, "verbose", False) else "nano"
    in_place = getattr(args, "in_place", False)
    result = transcode_file(path, target_dialect=target, in_place=in_place)

    if not in_place:
        print(result)
    else:
        print(f"✓ Transcoded {path.name} to {target.upper()} in-place.")
    return 0


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="ASL Dual-Projection Transcoder")
    parser.add_argument("file", help="path to ASL file")
    parser.add_argument("--to", dest="target", choices=["nano", "verbose"], default="nano")
    parser.add_argument("-i", "--in-place", action="store_true", help="modify file in place")
    args = parser.parse_args()
    args.verbose = (args.target == "verbose")
    sys.exit(run_transcode_cli(args))
