#!/usr/bin/env python3
"""Replay every declared program case against the reference interpreter alone.

I7 edition: builds the interpreter binary from the workspace, then for each of
backend/differential.py's program_cases() seeds the case's files/stdin/argv in a
fresh directory and asserts the case's declared stdout/stderr/exit against the
interpreter. I8 rewrites the build step to differential.build_interpreter so the
replay and the differential arm share one build path.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
for sub in ("backend", "grammar", "prelude", "checker"):
    sys.path.insert(0, str(ROOT / sub))
from differential import program_cases, build_interpreter  # noqa: E402

def build_interpreter_bin() -> None:
    # I8: build through differential's build_interpreter so the replay and the
    # differential arm share one build path (no local re-derivation).
    build_interpreter(Path("grammar") / "corpus" / "valid" / "01-basics.agentscript",
                      ROOT / "target")


def run_case(src: Path, case: dict) -> bool:
    argv = case.get("argv", [])
    files = case.get("files", {})
    stdin = case.get("stdin", "")
    want = (case["stdout"], case["stderr"], case["exit"])
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)
        for fname, (content, mode) in files.items():
            target = d / fname
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
            target.chmod(mode)
        cmd = build_interpreter(src.resolve(), d)
        r = subprocess.run(cmd + argv, cwd=d, input=stdin, capture_output=True, text=True)
    got = (r.stdout, r.stderr, r.returncode)
    ok = got == want
    if not ok:
        print(f"FAIL {src.name} {argv}:\n  want {want}\n  got  {got}")
    return ok


def main() -> int:
    build_interpreter_bin()
    bad = 0
    total = 0
    for src, group in program_cases():
        for case in group:
            total += 1
            if not run_case(src, case):
                bad += 1
    print(f"replay.py: {total - bad}/{total} program cases agree (interp)")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
