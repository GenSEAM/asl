#!/usr/bin/env python3
"""Token counts for the wire-format comparison README.md shows.

The figures on the front page were asserted, not counted: it claimed 42 / 25 /
11 / 9 where `cl100k_base` gives 51 / 34 / 26 / 18. The saving was real and the
numbers were not, which is the failure mode DESIGN.md §5 exists to stop — every
number on a public surface must come from a command someone can re-run.

  bench/token_frames.py            print the table
  bench/token_frames.py --check    fail if it no longer matches the lock
"""
import argparse
import json
import sys
from pathlib import Path

LOCK = Path(__file__).with_name("token_frames.lock")
ENCODING = "cl100k_base"

# The same command expressed four ways. Kept here rather than read out of the
# README so the payloads are one artifact and the prose quotes them.
FRAMES = {
    "json": '{\n  "action": "execute_command",\n  "payload": {\n'
            '    "binary": "git",\n    "arguments": ["status", "--short"],\n'
            '    "working_dir": "/app",\n    "timeout_ms": 5000\n  }\n}',
    "toon": "action: execute_command\npayload: [binary, working_dir, timeout_ms]\n"
            "  git, /app, 5000\narguments: [status, --short]",
    "nano-keyed": '(! cmd :bin "git" :args ["status" "--short"] :cwd "/app" :timeout-ms 5000)',
    "nano-positional": '(! cmd "git" ["status" "--short"] "/app" 5000)',
}


def counts() -> dict[str, int]:
    import tiktoken
    enc = tiktoken.get_encoding(ENCODING)
    return {name: len(enc.encode(text)) for name, text in FRAMES.items()}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    try:
        got = counts()
    except ImportError:
        print(f"tiktoken is not installed; cannot count with {ENCODING}", file=sys.stderr)
        return 2

    record = {"encoding": ENCODING, "counts": got,
              "saving_vs_json": round(1 - got["nano-positional"] / got["json"], 4)}

    if args.write or not LOCK.exists():
        LOCK.write_text(json.dumps(record, indent=2) + "\n")
        print(f"wrote {LOCK}")
        return 0

    want = json.loads(LOCK.read_text())
    if args.check:
        if want != record:
            print("token counts moved:", file=sys.stderr)
            print(f"  lock: {want}", file=sys.stderr)
            print(f"  now:  {record}", file=sys.stderr)
            print("Re-run with --write in the commit that earns the change.", file=sys.stderr)
            return 1
        print(f"OK: {record['counts']} ({ENCODING})")
        return 0

    width = max(len(k) for k in got)
    for name, n in got.items():
        print(f"{name.ljust(width)}  {n:3d}")
    print(f"\n{ENCODING}; positional Nano is "
          f"{record['saving_vs_json'] * 100:.1f}% smaller than the JSON frame.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
