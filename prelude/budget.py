#!/usr/bin/env python3
"""Token-budget ratchet for the agent-facing vocabulary (D3).

`len(prelude/HANDBOOK.md)` characters is the number, locked in `prelude/budget.lock`
and ratcheted under D7's exact-match rule: `--check` fails on ANY difference from the
recorded figure, up or down, and `--write` records a new figure deliberately, in the
commit that earns it. The handbook is what goes into an agent's prompt and is
re-sent on every call, so its size dominates the cost of a run; a real tokenizer is
a dependency and a determinism question for a number whose only job is to regress
when the handbook grows (D3).
"""
import sys
from pathlib import Path

ROOT = Path(__file__).parent
HANDBOOK = ROOT / "HANDBOOK.md"
LOCK = ROOT / "budget.lock"


def measure() -> int:
    return len(HANDBOOK.read_text())


def main() -> int:
    write = "--write" in sys.argv[1:]
    chars = measure()

    if write:
        LOCK.write_text(f"{chars}\n")
        print(f"{chars} characters; wrote {LOCK}")
        return 0

    if not LOCK.exists():
        sys.stderr.write(f"budget: {LOCK} missing; run with --write to record\n")
        return 2

    recorded = int(LOCK.read_text().strip())
    print(f"{chars} characters (lock: {recorded})")
    if chars != recorded:
        sys.stderr.write(
            f"budget: handbook is {chars} chars but budget.lock records {recorded}; "
            f"exact-match (D7) — --write only in the commit that earns the figure\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
