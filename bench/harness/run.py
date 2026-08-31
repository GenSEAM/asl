#!/usr/bin/env python3
"""Measurement harness: model -> AgentScript -> Python -> tests -> score.

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
from dataclasses import dataclass, asdict
from pathlib import Path

ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT / "backend"))
sys.path.insert(0, str(ROOT / "grammar"))
sys.path.insert(0, str(ROOT / "checker"))

from differential import build_python, build_rust, build_interpreter, build_typescript, build_go

HANDBOOK = (ROOT / "prelude" / "HANDBOOK.md").read_text()
DEFAULT_ROOTS = [ROOT / "grammar" / "corpus" / "modules"]

# `check` sits between parsing and lowering because a semantically rejected
# program and a program that does not parse say different things about the
# language, and collapsing them would discard the signal the stage list exists
# for (EXPERIMENT.md amendment 2026-08-29-a).
STAGES = ["extract", "parse", "check", "transpile", "execute", "correct"]




def run_target(
    cmd: list[str],
    cwd: Path,
    stdin: str = "",
    files: dict | None = None,
    timeout: float = 30.0,
) -> tuple[int, str, str]:
    """Execute command in isolated cwd with stdin and input files."""
    if files is None:
        files = {}
    try:
        for fname, val in files.items():
            if isinstance(val, (list, tuple)):
                content, mode = val[0], val[1]
            else:
                content, mode = val, 0o644
            target = cwd / fname
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
            target.chmod(mode)

        r = subprocess.run(
            cmd,
            cwd=cwd,
            input=stdin,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired as exc:
        out = exc.stdout if isinstance(exc.stdout, str) else (exc.stdout.decode() if exc.stdout else "")
        err = exc.stderr if isinstance(exc.stderr, str) else (exc.stderr.decode() if exc.stderr else "")
        return -1, out, err or "timeout: exceeded 30s limit"
    finally:
        for root, dirs, fnames in os.walk(cwd):
            for fname in fnames:
                try:
                    os.chmod(os.path.join(root, fname), 0o644)
                except Exception:
                    pass
            for dname in dirs:
                try:
                    os.chmod(os.path.join(root, dname), 0o755)
                except Exception:
                    pass



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
        "You write AgentScript, a small typed Lisp. The complete language reference follows. "
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


TARGET_BUILDERS = {
    "python": build_python,
    "rust": build_rust,
    "interp": build_interpreter,
    "interpreter": build_interpreter,
    "ts": build_typescript,
    "typescript": build_typescript,
    "go": build_go,
}


def is_whole_program_task(task: dict) -> bool:
    return "entry" not in task


def evaluate(
    code: str,
    task: dict,
    s: Sample,
    target: str = "python",
    roots: list[Path] | None = None,
) -> Sample:
    from parse import parse_text
    from resolve import check_file

    if roots is None:
        roots = DEFAULT_ROOTS

    tgt = target.lower()
    if tgt not in TARGET_BUILDERS:
        s.stage_reached = "extract"
        s.detail = f"unknown target {target}"
        return s

    s.stage_reached = "parse"
    try:
        parse_text(code)
    except Exception as exc:
        s.detail = f"{type(exc).__name__}: {exc}"[:160]
        return s

    s.stage_reached = "check"
    with tempfile.TemporaryDirectory() as d:
        d_path = Path(d)
        src = d_path / "candidate.agentscript"
        src.write_text(code)
        diags = check_file(src, roots)
        if diags:
            s.detail = f"{diags[0].code}: {diags[0].message}"[:160]
            return s

        is_wp = is_whole_program_task(task)
        cases = task.get("cases", [])

        if not is_wp:
            # Function-mode backward compatibility (Python only)
            if tgt != "python":
                s.stage_reached = "transpile"
                s.detail = f"function-mode tasks only supported on python target, got {target}"
                return s

            s.stage_reached = "transpile"
            try:
                from to_python import Transpiler
                py = Transpiler().transpile(code, path=src, roots=roots)
            except Exception as exc:
                s.detail = f"lowering: {type(exc).__name__}: {exc}"[:160]
                return s

            mod = d_path / "cand.py"
            mod.write_text(py)
            harness = d_path / "check.py"
            harness.write_text(
                "import sys, json\n"
                f"sys.path[:0] = [{str(ROOT / 'backend')!r}, {d!r}]\n"
                "import cand\n"
                f"cases = {json.dumps(cases)}\n"
                f"fn = getattr(cand, {task['entry'].replace('-', '_')!r})\n"
                "bad = []\n"
                "for inp, want, *_ in cases:\n"
                "    got = fn(*inp)\n"
                "    if got != want: bad.append((inp, got, want))\n"
                "print(json.dumps({'bad': bad[:3], 'n': len(bad)}))\n"
            )
            s.stage_reached = "execute"
            try:
                r = subprocess.run([sys.executable, str(harness)], capture_output=True, text=True, timeout=30)
            except subprocess.TimeoutExpired:
                s.detail = "timeout after 30s"
                return s

            if r.returncode != 0:
                s.detail = (r.stderr.strip().splitlines() or ["execution error"])[-1][:160]
                return s

            try:
                out = json.loads(r.stdout.strip().splitlines()[-1])
                if out["n"] == 0:
                    s.stage_reached, s.passed = "correct", True
                else:
                    s.detail = f"{out['n']} case(s) wrong, e.g. {out['bad'][:1]}"[:160]
            except Exception as exc:
                s.detail = f"output parsing error: {exc}"[:160]
            return s

        # Whole-program mode
        if tgt in ("interp", "interpreter"):
            s.stage_reached = "execute"
            try:
                cmd = build_interpreter(src, d_path, roots=roots)
            except Exception as exc:
                s.detail = f"{type(exc).__name__}: {exc}"[:160]
                return s
        else:
            s.stage_reached = "transpile"
            try:
                builder = TARGET_BUILDERS[tgt]
                cmd = builder(src, d_path, roots=roots)
            except Exception as exc:
                s.detail = f"lowering: {type(exc).__name__}: {exc}"[:160]
                return s
            s.stage_reached = "execute"

        for idx, case in enumerate(cases):
            argv = case.get("argv", [])
            stdin = case.get("stdin", "")
            files = case.get("files", {})
            want_stdout = case.get("stdout", "")
            want_stderr = case.get("stderr", "")
            want_exit = case.get("exit", 0)

            case_dir = d_path / f"case_{idx}"
            case_dir.mkdir(parents=True, exist_ok=True)
            retcode, got_stdout, got_stderr = run_target(
                cmd + argv, cwd=case_dir, stdin=stdin, files=files
            )

            if (got_stdout, got_stderr, retcode) != (want_stdout, want_stderr, want_exit):
                s.detail = (
                    f"case {idx} mismatch: exit={retcode} (want {want_exit}), "
                    f"stdout={got_stdout!r} (want {want_stdout!r}), "
                    f"stderr={got_stderr!r} (want {want_stderr!r})"
                )[:160]
                return s

        s.stage_reached = "correct"
        s.passed = True
        return s


SYNTHETIC_DRY_RUN_TASK = {
    "id": "synthetic_dry_run",
    "prompt": "Write a whole-program module `synthetic` exporting `main` that writes `hello dry-run\n` to stdout.",
    "cases": [
        {
            "argv": [],
            "stdin": "",
            "files": {},
            "stdout": "hello dry-run\n",
            "stderr": "",
            "exit": 0,
        }
    ],
}


def get_canned_reply(target: str, index: int) -> str:
    tgt = target.lower()
    if index == 0:
        return (
            "```lisp\n"
            '(module synthetic :doc "Dry run test" :export [main])\n'
            "(defun ! main [(args (List String))] -> (Result Unit IoError)\n"
            '  :doc "Entry point."\n'
            '  (println "hello dry-run"))\n'
            "```"
        )
    elif index == 1:
        return "This is a prose reply without any markdown code fence."
    elif index == 2:
        return "```lisp\n(defun broken [ -> Int64 1)\n```"
    elif index == 3:
        return (
            "```lisp\n"
            '(module synthetic :doc "Dry run test" :export [main])\n'
            "(defun ! main [(args (List String))] -> (Result Unit IoError)\n"
            '  :doc "Entry point."\n'
            '  "not-a-result")\n'
            "```"
        )
    elif index == 4:
        if tgt in ("interp", "interpreter"):
            return (
                "```lisp\n"
                '(module synthetic :doc "Dry run test" :export [main])\n'
                "(defun ! main [(args (List String))] -> (Result Unit IoError)\n"
                '  :doc "Entry point."\n'
                '  (println "interp-sample-4"))\n'
                "```"
            )
        elif tgt in ("python",):
            return (
                "```lisp\n"
                '(module synthetic :doc "Dry run test" :export [main])\n'
                "(defun ! import [(args (List String))] -> (Result Unit IoError)\n"
                '  :doc "Entry point."\n'
                '  (println "hi"))\n'
                "(defun ! main [(args (List String))] -> (Result Unit IoError)\n"
                '  :doc "Entry point."\n'
                "  (import args))\n"
                "```"
            )
        else:
            return (
                "```lisp\n"
                '(module synthetic :doc "Dry run test" :export [main])\n'
                '(defun foo [] -> Int64 :doc "" 1)\n'
                '(defun foo [] -> Int64 :doc "" 2)\n'
                "(defun ! main [(args (List String))] -> (Result Unit IoError)\n"
                '  :doc "Entry point."\n'
                '  (println (string-from-int64 (foo))))\n'
                "```"
            )
    elif index == 5:
        return (
            "```lisp\n"
            '(module synthetic :doc "Dry run test" :export [main])\n'
            "(defun ! main [(args (List String))] -> (Result Unit IoError)\n"
            '  :doc "Entry point."\n'
            '  (println "wrong-dry-run-output"))\n'
            "```"
        )
    else:
        return (
            "```lisp\n"
            '(module synthetic :doc "Dry run test" :export [main])\n'
            "(defun ! main [(args (List String))] -> (Result Unit IoError)\n"
            '  :doc "Entry point."\n'
            '  (println "hello dry-run"))\n'
            "```"
        )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=str(Path(__file__).parent / "config.json"))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--tasks", default=str(ROOT / "bench" / "tasks"))
    ap.add_argument(
        "--target",
        default="python",
        choices=["python", "ts", "typescript", "rust", "go", "interp", "interpreter"],
        help="Execution target (default: python)",
    )
    ap.add_argument(
        "--roots",
        nargs="*",
        default=None,
        help="Search paths for module resolution (default: grammar/corpus/modules)",
    )
    args = ap.parse_args()

    target = args.target.lower()
    roots = [Path(r) for r in args.roots] if args.roots else DEFAULT_ROOTS

    if args.dry_run:
        cfg = {
            "samples_per_task": 6,
            "spend_cap_usd": 0.20,
            "price_per_1m_input": 0.15,
            "price_per_1m_output": 0.60,
            "model": "dry-run",
            "endpoint": "-",
            "api_key_env": "-",
            "temperature": 0.2,
            "max_tokens": 1200,
        }
        tasks = [SYNTHETIC_DRY_RUN_TASK]
    else:
        p = Path(args.config)
        if not p.exists():
            raise SystemExit(f"no config at {p}; copy config.example.json and fill it in")
        cfg = json.loads(p.read_text())
        tasks = [json.loads(p.read_text()) for p in sorted(Path(args.tasks).glob("*.json"))]

    budget = Budget(cfg["spend_cap_usd"], cfg["price_per_1m_input"], cfg["price_per_1m_output"])
    samples: list[Sample] = []
    aborted = False

    for task in tasks:
        for i in range(cfg["samples_per_task"]):
            if budget.exhausted:
                aborted = True
                break
            s = Sample(task=task["id"], index=i)
            if args.dry_run:
                reply = get_canned_reply(target, i)
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
                evaluate(code, task, s, target=target, roots=roots)
            samples.append(s)
            print(
                f"  {task['id']}#{i}  {s.stage_reached:<10} "
                f"{'PASS' if s.passed else 'fail'}  ${budget.spent:.4f}"
                + (f"  {s.detail}" if s.detail else "")
            )
        if aborted:
            break

    n = len(samples)
    ok = sum(1 for s in samples if s.passed)
    print(f"\npass@1 {ok}/{n} = {ok/n:.0%}" if n else "\nno samples")
    print("stage reached:", {st: sum(1 for s in samples if s.stage_reached == st) for st in STAGES})
    print(f"spent ${budget.spent:.4f} of ${budget.cap:.2f}" + ("  [ABORTED ON CAP]" if aborted else ""))

    out = ROOT / "results" / ("dry-run.json" if args.dry_run else "run.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps(
            {
                "model": cfg["model"],
                "target": target,
                "spent_usd": round(budget.spent, 6),
                "aborted": aborted,
                "samples": [asdict(s) for s in samples],
            },
            indent=1,
        )
    )
    print(f"wrote {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
