#!/usr/bin/env python3
"""Does the Nano projection actually save tokens?

The projection, and the "single-token hygiene" standard behind it, are justified
throughout the documentation by token savings. Nothing measured it. This does.

The answer, under `cl100k_base`, is **no**: shortening an identifier saves bytes
and not tokens, because a BPE vocabulary already encodes `defun`, `:export` and
`Float64` as cheaply as `df`, `:x` and `F64`. What does save tokens is removing
*structure* — quotes around keys, commas, braces, repeated field names — which is
what `bench/token_frames.py` measures and what the wire and data formats do.

Keeping the two measurements apart matters: one claim is true and one is not, and
they were being made in the same breath.

Measured 2026-09-03 over every fixture in `grammar/corpus/valid`: **3.58% fewer
bytes, 0.00% fewer tokens** — 15,931 either way. On one fixture in isolation,
`06-module` is 1537 bytes / 429 tokens verbose and 1422 bytes / 429 tokens Nano.

One caveat the figure carries: the transcoder does not yet convert type aliases,
so `Int64` -> `I64` is outside this measurement. Measured separately, each of
those pairs is also a tie — ` Int64` and ` I64` are both two tokens, ` String`
and ` Str` both one — so including them will not move the result.

  bench/token_projection.py            print the table
  bench/token_projection.py --check    fail if it no longer matches the lock
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCK = Path(__file__).with_name("token_projection.lock")
CORPUS = ROOT / "grammar" / "corpus" / "valid"
ENCODING = "cl100k_base"


def project(path: Path, target: str) -> str:
    """The fixture rendered into one projection, by the real transcoder."""
    proc = subprocess.run(
        [sys.executable, str(ROOT / "agentscript"), "transcode", str(path), "--to", target],
        capture_output=True, text=True, cwd=ROOT)
    if proc.returncode != 0:
        raise RuntimeError(f"{path.name} -> {target}: {proc.stderr.strip()[:200]}")
    return proc.stdout


def measure() -> dict:
    import tiktoken
    enc = tiktoken.get_encoding(ENCODING)
    rows, tv, tn, bv, bn = [], 0, 0, 0, 0
    for path in sorted(CORPUS.glob("*.agentscript")):
        verbose, nano = project(path, "verbose"), project(path, "nano")
        v, n = len(enc.encode(verbose)), len(enc.encode(nano))
        rows.append({"fixture": path.name, "verbose_tokens": v, "nano_tokens": n,
                     "verbose_bytes": len(verbose), "nano_bytes": len(nano)})
        tv += v; tn += n; bv += len(verbose); bn += len(nano)
    return {"encoding": ENCODING, "fixtures": len(rows),
            "verbose_tokens": tv, "nano_tokens": tn,
            "verbose_bytes": bv, "nano_bytes": bn,
            "token_saving_pct": round(100 * (1 - tn / tv), 2) if tv else 0.0,
            "byte_saving_pct": round(100 * (1 - bn / bv), 2) if bv else 0.0,
            "rows": rows}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    try:
        got = measure()
    except ImportError:
        print(f"tiktoken is not installed; cannot count with {ENCODING}", file=sys.stderr)
        return 2

    summary = {k: got[k] for k in got if k != "rows"}

    if args.write or not LOCK.exists():
        LOCK.write_text(json.dumps(got, indent=2) + "\n")
        print(f"wrote {LOCK}")
        return 0

    if args.check:
        want = json.loads(LOCK.read_text())
        if {k: want.get(k) for k in summary} != summary:
            print("projection token figures moved:", file=sys.stderr)
            print(f"  lock: {({k: want.get(k) for k in summary})}", file=sys.stderr)
            print(f"  now:  {summary}", file=sys.stderr)
            print("Re-run with --write in the commit that earns the change.", file=sys.stderr)
            return 1
        print(f"OK: {summary}")
        return 0

    print(f"{'fixture':<38}{'verbose':>9}{'nano':>7}{'delta':>7}")
    print("-" * 61)
    for r in got["rows"]:
        d = r["nano_tokens"] - r["verbose_tokens"]
        print(f"{r['fixture']:<38}{r['verbose_tokens']:>9}{r['nano_tokens']:>7}{d:>+7}")
    print("-" * 61)
    print(f"{'total':<38}{got['verbose_tokens']:>9}{got['nano_tokens']:>7}"
          f"{got['nano_tokens'] - got['verbose_tokens']:>+7}")
    print(f"\n{ENCODING}: Nano saves {got['byte_saving_pct']}% of bytes and "
          f"{got['token_saving_pct']}% of tokens across {got['fixtures']} fixtures.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
