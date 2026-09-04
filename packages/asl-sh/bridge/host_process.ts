/**
 * Host Subprocess Execution Driver (@pcp:d-446d)
 *
 * Spawns child processes safely (shell: false), injects unbuffered environment
 * variables (PYTHONUNBUFFERED=1), and enforces the justified bypass policy.
 */

import { spawn, ChildProcess, SpawnOptions as NodeSpawnOptions } from "child_process";
import { Writable, Readable } from "stream";

export interface HostProcessOptions {
  cwd?: string;
  env?: Record<string, string>;
  timeoutMs?: number;
  /** If true, bypasses token stream reduction (requires bypassReason >= 10 chars) */
  bypassReduction?: boolean;
  /** Mandatory audit rationale for bypassing reduction */
  bypassReason?: string;
  stdinData?: string;
}

export class BypassPolicyViolationError extends Error {
  constructor(reason: string) {
    super(`BypassPolicyViolation: ${reason}`);
    this.name = "BypassPolicyViolationError";
  }
}

export interface ProcessExitResult {
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  durationMs: number;
  timedOut: boolean;
}

export class HostProcess {
  readonly command: string;
  readonly args: string[];
  readonly options: HostProcessOptions;

  private child: ChildProcess | null = null;
  private startTime = 0;
  private hardTimeoutTimer: NodeJS.Timeout | null = null;
  private timedOut = false;

  constructor(command: string, args: string[] = [], options: HostProcessOptions = {}) {
    this.command = command;
    this.args = args;
    this.options = options;

    // Enforce §1.6 Justified Bypass
    if (options.bypassReduction) {
      if (!options.bypassReason || options.bypassReason.trim().length < 10) {
        throw new BypassPolicyViolationError(
          "Bypassing reduction requires a justified bypass_reason >= 10 characters."
        );
      }
    }
  }

  get pid(): number | undefined {
    return this.child?.pid;
  }

  get stdin(): Writable | null {
    return this.child?.stdin ?? null;
  }

  get stdout(): Readable | null {
    return this.child?.stdout ?? null;
  }

  get stderr(): Readable | null {
    return this.child?.stderr ?? null;
  }

  start(): ChildProcess {
    this.startTime = performance.now();

    // Prepare unbuffered environment
    const childEnv: Record<string, string> = {
      ...(process.env as Record<string, string>),
      PYTHONUNBUFFERED: "1",
      ...(this.options.env || {}),
    };

    const spawnOpts: NodeSpawnOptions = {
      cwd: this.options.cwd || process.cwd(),
      env: childEnv,
      shell: false, // Strict injection prevention
      stdio: ["pipe", "pipe", "pipe"],
    };

    this.child = spawn(this.command, this.args, spawnOpts);

    if (this.options.timeoutMs && this.options.timeoutMs > 0) {
      this.hardTimeoutTimer = setTimeout(() => {
        this.timedOut = true;
        this.kill("SIGKILL");
      }, this.options.timeoutMs);
      if (this.hardTimeoutTimer.unref) {
        this.hardTimeoutTimer.unref();
      }
    }

    if (this.options.stdinData && this.child.stdin) {
      this.child.stdin.write(this.options.stdinData);
      this.child.stdin.end();
    }

    return this.child;
  }

  kill(signal: NodeJS.Signals = "SIGTERM"): boolean {
    if (this.child && !this.child.killed) {
      return this.child.kill(signal);
    }
    return false;
  }

  async waitForExit(): Promise<ProcessExitResult> {
    if (!this.child) {
      throw new Error("Process has not been started yet.");
    }

    return new Promise<ProcessExitResult>((resolve) => {
      this.child!.once("close", (code, signal) => {
        if (this.hardTimeoutTimer) {
          clearTimeout(this.hardTimeoutTimer);
          this.hardTimeoutTimer = null;
        }
        const durationMs = +(performance.now() - this.startTime).toFixed(2);
        resolve({
          exitCode: code,
          signal,
          durationMs,
          timedOut: this.timedOut,
        });
      });
    });
  }
}
