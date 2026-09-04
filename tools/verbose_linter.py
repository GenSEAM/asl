#!/usr/bin/env python3
"""AgentScript Standard Format Enforcer & Verbose Syntax Linter.

Verifies that no saved .asl source files contain verbose projection syntax.
All saved source code must be stored in the Standard format:
  `df`, `dfs`, `dfe`, `mt`, `:d`, `:x`, `:i`, `:a`, `:f`, `:c`,
  and standard type aliases `I64`, `I32`, `F64`, `Str`.

Verbose format (`defun`, `defschema`, `defenum`, `match`, `:doc`, `:export`,
`:import`, `Int64`, `String`, etc.) is reserved exclusively for ephemeral human
inspection via `asl view` and must never be committed to disk.
"""
import sys
import argparse
from pathlib import Path
from typing import List, Tuple

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "grammar"))
sys.path.insert(0, str(ROOT / "prelude"))

from transcoder import parse_text, _collect, _rewrites, _type_projector, transcode_text, NANO
from lark.exceptions import LarkError

HEAD_AND_OPT_REWRITES = {
    "defun": "df", "defschema": "dfs", "defenum": "dfe", "match": "mt",
    "def": "df", "schema": "dfs", "enum": "dfe",
    ":doc": ":d", ":export": ":x", ":import": ":i", ":as": ":a",
    ":field": ":f", ":case": ":c"
}


def span_to_line_col(text: str, pos: int) -> Tuple[int, int]:
    """Converts a 0-indexed byte offset into (1-indexed line, 1-indexed col)."""
    line = text.count("\n", 0, pos) + 1
    last_nl = text.rfind("\n", 0, pos)
    col = pos + 1 if last_nl == -1 else pos - last_nl
    return line, col


def check_file_for_verbose(path: Path, check_types: bool = True) -> List[Tuple[int, int, str, str, str]]:
    """Checks a file for verbose syntax occurrences.

    Returns list of tuples: (line, col, original_text, wanted_standard_text, severity).
    """
    try:
        content = path.read_text(encoding="utf-8")
    except Exception as e:
        return [(1, 1, str(e), "", "error")]

    try:
        tree = parse_text(content)
    except LarkError:
        # If the file does not parse, other syntax gates will report it
        return []

    edits: List[Tuple[int, int, str]] = []
    # 1. Check heads and options (always ERROR)
    _collect(tree, frozenset(), HEAD_AND_OPT_REWRITES, lambda name: name, edits)
    head_opt_spans = {start for start, _, _ in edits}

    violations = []
    for start, end, want in sorted(edits):
        orig = content[start:end]
        line, col = span_to_line_col(content, start)
        violations.append((line, col, orig, want, "error"))

    # 2. Check types if enabled
    if check_types:
        type_edits: List[Tuple[int, int, str]] = []
        _collect(tree, frozenset(), {}, _type_projector(NANO), type_edits)
        for start, end, want in sorted(type_edits):
            if start not in head_opt_spans:
                orig = content[start:end]
                line, col = span_to_line_col(content, start)
                violations.append((line, col, orig, want, "warning"))

    return violations


def lint_verbose(paths: List[Path], fix: bool = False, strict: bool = False) -> int:
    asl_files: List[Path] = []
    for p in paths:
        p = p.resolve()
        if p.is_file() and p.suffix == ".asl":
            asl_files.append(p)
        elif p.is_dir():
            asl_files.extend([f for f in p.rglob("*.asl") if not any(part.startswith(".") for part in f.parts)])

    if not asl_files:
        print("No .asl source files found to lint.")
        return 0

    total_errors = 0
    total_warnings = 0
    files_with_violations = 0

    print("=== AgentScript Standard Format (Non-Verbose) Linter ===")
    for f in sorted(asl_files):
        rel = f.relative_to(ROOT) if f.is_relative_to(ROOT) else f
        violations = check_file_for_verbose(f, check_types=True)
        if violations:
            errors = [v for v in violations if v[4] == "error"]
            warnings = [v for v in violations if v[4] == "warning"]

            if errors or (strict and warnings):
                files_with_violations += 1
                total_errors += len(errors) + (len(warnings) if strict else 0)
                status = "FAIL"
            else:
                total_warnings += len(warnings)
                status = "WARN"

            print(f"\n[{status}] {rel} ({len(violations)} verbose occurrence(s)):")
            for line, col, orig, want, sev in violations:
                sev_badge = "[ERROR]" if sev == "error" or strict else "[WARN]"
                print(f"  {sev_badge} {rel}:{line}:{col} '{orig}' -> must be standard '{want}'")

            if fix:
                try:
                    fixed_content = transcode_text(f.read_text(encoding="utf-8"), NANO, str(rel))
                    f.write_text(fixed_content, encoding="utf-8")
                    print(f"  ✓ Auto-fixed {rel} to Standard format.")
                except Exception as ex:
                    print(f"  ✗ Failed to auto-fix {rel}: {ex}")

    print("\n---------------------------------------------------------")
    if total_errors == 0:
        print(f"✓ PASS: All {len(asl_files)} file(s) use Standard format heads & options (0 blocking errors).")
        if total_warnings > 0 and not strict:
            print(f"  ({total_warnings} verbose type alias warnings detected; use --strict to enforce or --fix to normalize)")
        return 0
    else:
        print(f"✗ FAILED: {total_errors} blocking verbose syntax error(s) found in {files_with_violations} file(s).")
        return 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="AgentScript Verbose Format Linter")
    parser.add_argument("paths", nargs="*", type=Path, default=[ROOT / "packages"], help="Paths or directories to check")
    parser.add_argument("--fix", action="store_true", help="Auto-fix violations in place")
    parser.add_argument("--strict", action="store_true", help="Treat verbose type aliases as fatal errors")
    args = parser.parse_args()
    sys.exit(lint_verbose(args.paths, fix=args.fix, strict=args.strict))
