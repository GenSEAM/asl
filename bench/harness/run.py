#!/usr/bin/env python3
"""Measurement harness: model -> AgentS -> Python -> tests -> score.

The spend cap is enforced here rather than intended: the run aborts when the cap
is reached, instead of reporting an overrun afterwards (EXPERIMENT.md 2026-08-20-c).

Failures are classified, not merely counted. Which stage a sample dies at is the
measurement — a parse failure and a wrong answer say opposite things about the
language, and collapsing them into one pass rate discards exactly the signal
this experiment exists to collect.

  --dry-run  use canned responses; exercises the whole path with no network and
             no credentials, so the harness can be verified before it is trusted.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import urllib.request
from dataclasses import dataclass, field, asdict
from pathlib import Path

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "backend"))

HANDBOOK = (ROOT / "prelude" / "HANDBOOK.md").read_text()

STAGES = ["extract", "parse", "transpile", "execute", "correct"]


@dataclass
class Sample:
    task: str
    index: int
    stage_reached: str = "extract"
    passed: bool = False
    detail: str = ""
    in_tokens: int = 0
    out_tokens: int = 0
    code: str = ""


@dataclass
class Budget:
    cap: float
    per_in: float
    per_out: float
    spent: float = 0.0

    def add(self, i: int, o: int) -> None:
        self.spent += (i * self.per_in + o * self.per_out) / 1_000_000

    @property
    def exhausted(self) -> bool:
        return self.spent >= self.cap


def system_prompt() -> str:
    return (
        "You write AgentS-Core, a small typed Lisp. The complete language reference follows. "
        "Use ONLY names defined in it — nothing else exists.\n\n"
        f"{HANDBOOK}\n\n"
        "Reply with ONE ```lisp fenced block containing a complete module and nothing else. "
        "No explanation before or after."
    )


def call_model(cfg: dict, prompt: str) -> tuple[str, int, int]:
    key = os.environ.get(cfg["api_key_env"])
    if not key:
        raise SystemExit(
            f"${cfg['api_key_env']} is not set. Export the gateway key; it is never read "
            f"from a file in this repository."
        )
    body = json.dumps({
        "model": cfg["model"],
        "messages": [{"role": "system", "content": system_prompt()},
                     {"role": "user", "content": prompt}],
        "temperature": cfg["temperature"],
        "max_tokens": cfg["max_tokens"],
    }).encode()
    req = urllib.request.Request(
        cfg["endpoint"], data=body,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = json.loads(r.read())
    usage = data.get("usage", {})
    return (data["choices"][0]["message"]["content"],
            usage.get("prompt_tokens", 0), usage.get("completion_tokens", 0))


def extract(reply: str) -> str | None:
    """Pull the single fenced block. A reply with prose and no fence is a miss."""
    if "```" not in reply:
        return reply.strip() if reply.strip().startswith("(") else None
    part = reply.split("```", 2)[1]
    if part.startswith("lisp"):
        part = part[4:]
    return part.strip() or None


def evaluate(code: str, task: dict, s: Sample) -> Sample:
    from to_python import Transpiler

    s.stage_reached = "parse"
    try:
        py = Transpiler().transpile(code)
    except Exception as exc:                      # parse and lowering share a call
        s.detail = f"{type(exc).__name__}: {exc}"[:160]
        return s

    s.stage_reached = "transpile"
    with tempfile.TemporaryDirectory() as d:
        mod = Path(d) / "cand.py"
        mod.write_text(py)
        harness = Path(d) / "check.py"
        harness.write_text(
            "import sys, json\n"
            f"sys.path[:0] = [{str(ROOT / 'backend')!r}, {d!r}]\n"
            "import cand\n"
            f"cases = json.loads({json.dumps(json.dumps(task['cases']))})\n"
            f"fn = getattr(cand, {task['entry'].replace('-', '_')!r})\n"
            "bad = []\n"
            "for inp, want in cases:\n"
            "    got = fn(inp)\n"
            "    if got != want: bad.append((inp, got, want))\n"
            "print(json.dumps({'bad': bad[:3], 'n': len(bad)}))\n"
        )
        r = subprocess.run([sys.executable, str(harness)], capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            s.detail = (r.stderr.strip().splitlines() or ["?"])[-1][:160]
            return s
        s.stage_reached = "execute"
        out = json.loads(r.stdout.strip().splitlines()[-1])
        if out["n"] == 0:
            s.stage_reached, s.passed = "correct", True
        else:
            s.detail = f"{out['n']} case(s) wrong, e.g. {out['bad'][:1]}"[:160]
    return s


CANNED = (ROOT / "bench" / "algo" / "variants" / "tight.agents")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=str(Path(__file__).parent / "config.json"))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--tasks", default=str(ROOT / "bench" / "tasks"))
    args = ap.parse_args()

    if args.dry_run:
        cfg = {"samples_per_task": 2, "spend_cap_usd": 0.20,
               "price_per_1m_input": 0.15, "price_per_1m_output": 0.60,
               "model": "dry-run", "endpoint": "-", "api_key_env": "-",
               "temperature": 0.2, "max_tokens": 1200}
    else:
        p = Path(args.config)
        if not p.exists():
            raise SystemExit(f"no config at {p}; copy config.example.json and fill it in")
        cfg = json.loads(p.read_text())

    budget = Budget(cfg["spend_cap_usd"], cfg["price_per_1m_input"], cfg["price_per_1m_output"])
    tasks = [json.loads(p.read_text()) for p in sorted(Path(args.tasks).glob("*.json"))]
    samples: list[Sample] = []
    aborted = False

    for task in tasks:
        for i in range(cfg["samples_per_task"]):
            if budget.exhausted:
                aborted = True
                break
            s = Sample(task=task["id"], index=i)
            if args.dry_run:
                # Sample 0 is a known-good module; sample 1 is malformed, so the
                # failure path is exercised too rather than assumed to work.
                reply = (f"```lisp\n{CANNED.read_text()}\n```" if i == 0
                         else "```lisp\n(defun broken [ -> Int64 1)\n```")
                nin, nout = len(system_prompt()) // 4, 200
            else:
                reply, nin, nout = call_model(cfg, task["prompt"])
            budget.add(nin, nout)
            s.in_tokens, s.out_tokens = nin, nout
            code = extract(reply)
            if code is None:
                s.detail = "no code block in reply"
            else:
                s.code = code
                evaluate(code, task, s)
            samples.append(s)
            print(f"  {task['id']}#{i}  {s.stage_reached:<10} "
                  f"{'PASS' if s.passed else 'fail'}  ${budget.spent:.4f}"
                  + (f"  {s.detail}" if s.detail else ""))
        if aborted:
            break

    n = len(samples)
    ok = sum(1 for s in samples if s.passed)
    print(f"\npass@1 {ok}/{n} = {ok/n:.0%}" if n else "\nno samples")
    print("stage reached:", {st: sum(1 for s in samples if s.stage_reached == st) for st in STAGES})
    print(f"spent ${budget.spent:.4f} of ${budget.cap:.2f}"
          + ("  [ABORTED ON CAP]" if aborted else ""))

    out = ROOT / "results" / ("dry-run.json" if args.dry_run else "run.json")
    out.write_text(json.dumps(
        {"model": cfg["model"], "spent_usd": round(budget.spent, 6), "aborted": aborted,
         "samples": [asdict(s) for s in samples]}, indent=1))
    print(f"wrote {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
