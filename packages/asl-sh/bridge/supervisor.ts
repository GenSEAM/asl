/**
 * Process Supervisor & Execution Driver (@pcp:d-446d)
 *
 * Coordinates child process execution, in-memory ring buffering, silence watchdog,
 * interactive prompt detection, token reduction, and inline adaptive digests.
 */

import { EventEmitter } from "events";
import { RingBuffer, RingBufferOptions } from "./ring_buffer.js";
import { StreamWatcher, StreamWatcherOptions, WatcherState, PromptEvent, QuietStallEvent } from "./stream_watcher.js";
import { HostProcess, HostProcessOptions, ProcessExitResult, BypassPolicyViolationError } from "./host_process.js";
import { reduceStream, ReducedStream, ReductionConfig, DEFAULT_REDUCTION_CONFIG } from "./reducer.js";

export interface SupervisorOptions extends HostProcessOptions, RingBufferOptions, StreamWatcherOptions {
  reductionConfig?: ReductionConfig;
}

export interface AdaptiveDigest {
  mode: "inline" | "summary";
  text: string;
  totalLines: number;
  reducedLines: number;
  evictedLines: number;
  durationMs: number;
  exitCode: number | null;
  diagnostics: {
    errors: number;
    warnings: number;
    failures: number;
  };
  navHandles?: {
    slice: string;
    grep: string;
    query: string;
  };
}

export interface ExecutionResult {
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  durationMs: number;
  timedOut: boolean;
  state: WatcherState;
  stdout: string;
  stderr: string;
  rawText: string;
  reduced: ReducedStream;
  digest: AdaptiveDigest;
  ringBuffer: RingBuffer;
}

export class ProcessSupervisor extends EventEmitter {
  readonly options: SupervisorOptions;
  readonly ringBuffer: RingBuffer;
  readonly watcher: StreamWatcher;

  private hostProcess: HostProcess | null = null;
  private _latestResult: ExecutionResult | null = null;

  constructor(options: SupervisorOptions = {}) {
    super();
    if (options.bypassReduction) {
      if (!options.bypassReason || options.bypassReason.trim().length < 10) {
        throw new BypassPolicyViolationError(
          "Bypassing reduction requires a justified bypass_reason >= 10 characters."
        );
      }
    }
    this.options = options;
    this.ringBuffer = new RingBuffer({
      maxBytes: options.maxBytes,
      maxLines: options.maxLines,
      headLimit: options.headLimit,
      tailLimit: options.tailLimit,
      ttlMs: options.ttlMs,
      pinned: options.pinned,
    });
    this.watcher = new StreamWatcher({
      silenceTimeoutMs: options.silenceTimeoutMs,
      promptPatterns: options.promptPatterns,
    });

    // Forward watcher events
    this.watcher.on("prompt", (e: PromptEvent) => this.emit("prompt", e));
    this.watcher.on("quiet-stall", (e: QuietStallEvent) => this.emit("quiet-stall", e));
    this.watcher.on("resume", () => this.emit("resume"));
    this.watcher.on("state-change", (st: WatcherState) => this.emit("state-change", st));
  }

  get state(): WatcherState {
    return this.watcher.state;
  }

  get pid(): number | undefined {
    return this.hostProcess?.pid;
  }

  get latestResult(): ExecutionResult | null {
    return this._latestResult;
  }

  getBuffer(): RingBuffer {
    return this.ringBuffer;
  }

  /**
   * Sends stdin data to the running subprocess.
   */
  sendInput(data: string): void {
    if (this.hostProcess && this.hostProcess.stdin && !this.hostProcess.stdin.destroyed) {
      this.hostProcess.stdin.write(data);
      this.watcher.notifyInputSent();
    }
  }

  /**
   * Sends signal to running subprocess.
   */
  kill(signal: NodeJS.Signals = "SIGTERM"): boolean {
    if (this.hostProcess) {
      this.watcher.stop("Killed");
      return this.hostProcess.kill(signal);
    }
    return false;
  }

  /**
   * Spawns and supervises a subprocess to completion.
   */
  async run(command: string, args: string[] = []): Promise<ExecutionResult> {
    this.hostProcess = new HostProcess(command, args, this.options);
    const child = this.hostProcess.start();
    this.watcher.start();

    // Attach stream listeners
    if (child.stdout) {
      child.stdout.on("data", (chunk: Buffer) => {
        const text = chunk.toString("utf-8");
        this.ringBuffer.append(chunk, "stdout");
        this.watcher.feed(text, "stdout");
        this.emit("chunk", { data: text, channel: "stdout" });
      });
    }

    if (child.stderr) {
      child.stderr.on("data", (chunk: Buffer) => {
        const text = chunk.toString("utf-8");
        this.ringBuffer.append(chunk, "stderr");
        this.watcher.feed(text, "stderr");
        this.emit("chunk", { data: text, channel: "stderr" });
      });
    }

    // Wait for exit
    const exitRes: ProcessExitResult = await this.hostProcess.waitForExit();
    this.ringBuffer.flush();

    const finalState: WatcherState = exitRes.timedOut ? "TimedOut" : "Exited";
    this.watcher.stop(finalState);

    // Compute reduction
    const rawText = this.ringBuffer.getText("all");
    const stdout = this.ringBuffer.getStdout();
    const stderr = this.ringBuffer.getStderr();

    let reduced: ReducedStream;
    if (this.options.bypassReduction) {
      // Justified bypass: return raw output as-is
      const lines = rawText.split("\n");
      reduced = {
        rawLineCount: lines.length,
        reducedLineCount: lines.length,
        evictedLineCount: 0,
        lines,
        text: rawText,
        diagnostics: { errors: 0, warnings: 0, failures: 0, diagnostics: [] },
      };
    } else {
      reduced = reduceStream(rawText, this.options.reductionConfig || {
        headLimit: this.options.headLimit,
        tailLimit: this.options.tailLimit,
      });
    }

    // Produce adaptive digest (§1.5)
    // Short fast runs (<2s and <40 lines) return clean inline output
    const isFastShort = exitRes.durationMs < 2000 && reduced.rawLineCount < 40;
    const digest: AdaptiveDigest = isFastShort
      ? {
          mode: "inline",
          text: reduced.text,
          totalLines: reduced.rawLineCount,
          reducedLines: reduced.reducedLineCount,
          evictedLines: reduced.evictedLineCount,
          durationMs: exitRes.durationMs,
          exitCode: exitRes.exitCode,
          diagnostics: {
            errors: reduced.diagnostics.errors,
            warnings: reduced.diagnostics.warnings,
            failures: reduced.diagnostics.failures,
          },
        }
      : {
          mode: "summary",
          text: reduced.text,
          totalLines: reduced.rawLineCount,
          reducedLines: reduced.reducedLineCount,
          evictedLines: reduced.evictedLineCount,
          durationMs: exitRes.durationMs,
          exitCode: exitRes.exitCode,
          diagnostics: {
            errors: reduced.diagnostics.errors,
            warnings: reduced.diagnostics.warnings,
            failures: reduced.diagnostics.failures,
          },
          navHandles: {
            slice: "proc_slice(startLine, endLine)",
            grep: "proc_grep(pattern, context)",
            query: "proc_query(pathExpr)",
          },
        };

    const result: ExecutionResult = {
      exitCode: exitRes.exitCode,
      signal: exitRes.signal,
      durationMs: exitRes.durationMs,
      timedOut: exitRes.timedOut,
      state: finalState,
      stdout,
      stderr,
      rawText,
      reduced,
      digest,
      ringBuffer: this.ringBuffer,
    };

    this._latestResult = result;
    this.emit("exit", result);
    return result;
  }
}
