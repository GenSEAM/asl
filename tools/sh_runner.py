#!/usr/bin/env python3
"""
AgentScript System Process & Pipeline Runner (@pcp:d-446d).
Executes typed command vectors with strict shell injection prevention,
timeout deadlines, and multi-stage process pipelines.
"""
import sys
import time
import os
import subprocess
from pathlib import Path
from dataclasses import dataclass
from typing import List, Optional, Dict, Any

ROOT = Path(__file__).resolve().parent.parent


@dataclass
class ProcessResult:
    exit_code: int
    stdout: str
    stderr: str
    duration_ms: float
    timed_out: bool = False


class ShProcessRunner:
    """Safe subprocess runner preventing shell injection and enforcing timeouts."""

    @staticmethod
    def run_cmd(
        bin_path: str,
        args: List[str],
        cwd: Optional[Path] = None,
        env: Optional[Dict[str, str]] = None,
        timeout_sec: float = 10.0,
        stdin_data: Optional[str] = None
    ) -> ProcessResult:
        t0 = time.perf_counter()
        full_env = os.environ.copy()
        if env:
            full_env.update(env)

        exec_args = [bin_path] + list(args)

        try:
            p = subprocess.run(
                exec_args,
                cwd=str(cwd) if cwd else None,
                env=full_env,
                input=stdin_data,
                text=True,
                capture_output=True,
                timeout=timeout_sec,
                shell=False  # Crucial: Prevent shell injection by design
            )
            duration = (time.perf_counter() - t0) * 1000.0
            return ProcessResult(
                exit_code=p.returncode,
                stdout=p.stdout,
                stderr=p.stderr,
                duration_ms=duration
            )
        except subprocess.TimeoutExpired as te:
            duration = (time.perf_counter() - t0) * 1000.0
            return ProcessResult(
                exit_code=-1,
                stdout=te.stdout.decode() if te.stdout else "",
                stderr=f"Timeout expired after {timeout_sec}s",
                duration_ms=duration,
                timed_out=True
            )
        except FileNotFoundError:
            duration = (time.perf_counter() - t0) * 1000.0
            return ProcessResult(
                exit_code=127,
                stdout="",
                stderr=f"Command not found: '{bin_path}'",
                duration_ms=duration
            )

    @staticmethod
    def run_pipeline(stages: List[List[str]], timeout_sec: float = 15.0) -> ProcessResult:
        """Executes piped commands (stage 1 | stage 2 | stage 3) without shell eval."""
        if not stages:
            return ProcessResult(exit_code=0, stdout="", stderr="", duration_ms=0.0)

        t0 = time.perf_counter()
        procs = []
        try:
            prev_stdout = None
            for i, cmd in enumerate(stages):
                is_last = (i == len(stages) - 1)
                proc = subprocess.Popen(
                    cmd,
                    stdin=prev_stdout,
                    stdout=subprocess.PIPE if not is_last else subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    shell=False
                )
                if prev_stdout:
                    prev_stdout.close()
                prev_stdout = proc.stdout
                procs.append(proc)

            last_proc = procs[-1]
            stdout, stderr = last_proc.communicate(timeout=timeout_sec)
            duration = (time.perf_counter() - t0) * 1000.0

            return ProcessResult(
                exit_code=last_proc.returncode,
                stdout=stdout,
                stderr=stderr,
                duration_ms=duration
            )
        except subprocess.TimeoutExpired:
            for p in procs:
                p.kill()
            return ProcessResult(
                exit_code=-1,
                stdout="",
                stderr=f"Pipeline timeout after {timeout_sec}s",
                duration_ms=(time.perf_counter() - t0) * 1000.0,
                timed_out=True
            )
        except FileNotFoundError as e:
            return ProcessResult(
                exit_code=127,
                stdout="",
                stderr=str(e),
                duration_ms=(time.perf_counter() - t0) * 1000.0
            )


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python tools/sh_runner.py <cmd> [args...]")
        sys.exit(1)

    cmd = sys.argv[1]
    args = sys.argv[2:]
    res = ShProcessRunner.run_cmd(cmd, args)
    print(f"Exit: {res.exit_code} ({res.duration_ms:.1f}ms)")
    if res.stdout:
        print(f"STDOUT:\n{res.stdout}")
    if res.stderr:
        print(f"STDERR:\n{res.stderr}", file=sys.stderr)
    sys.exit(res.exit_code)
