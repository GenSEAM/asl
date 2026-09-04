/**
 * Stream Watcher: Interactive Prompt Detector & Silence Watchdog (@pcp:d-446d)
 *
 * Distinguishes interactive stdin prompts from quiet stalls and monitors
 * stream liveness.
 */

import { EventEmitter } from "events";

export type WatcherState = "Starting" | "Streaming" | "AwaitingStdin" | "QuietStall" | "Exited" | "Killed" | "TimedOut";

export interface StreamWatcherOptions {
  /** Silence threshold in milliseconds before entering QuietStall (default: 10,000 ms) */
  silenceTimeoutMs?: number;
  /** Custom regex patterns for interactive stdin prompt detection */
  promptPatterns?: RegExp[];
}

export interface PromptEvent {
  promptText: string;
  channel: "stdout" | "stderr";
}

export interface QuietStallEvent {
  silentMs: number;
}

const ANSI_REGEX = /\x1b\[[0-9;]*[a-zA-Z]|\x1b\].*?\x07|\x1b[()][AB012]/g;

function stripAnsi(text: string): string {
  return text.replace(ANSI_REGEX, "");
}

export class StreamWatcher extends EventEmitter {
  readonly silenceTimeoutMs: number;
  readonly promptPatterns: RegExp[];

  private _state: WatcherState = "Starting";
  private silenceTimer: NodeJS.Timeout | null = null;
  private lastChunkTime: number = Date.now();
  private pendingTail: string = "";

  constructor(options: StreamWatcherOptions = {}) {
    super();
    this.silenceTimeoutMs = options.silenceTimeoutMs ?? 10000;
    this.promptPatterns = options.promptPatterns ?? [
      /\?\s*$/,
      /\[y\/N\]\s*$/i,
      /\[Y\/n\]\s*$/i,
      /\(y\/n\)\s*$/i,
      /\[yes\/no\]\s*$/i,
      /\(yes\/no\)\s*$/i,
      /(?:password|passphrase|token|enter.*key):\s*$/i,
      /(?:press any key to continue|press enter to continue)\s*$/i,
    ];
  }

  get state(): WatcherState {
    return this._state;
  }

  start(): void {
    this._state = "Streaming";
    this.lastChunkTime = Date.now();
    this.armSilenceTimer();
  }

  /**
   * Feeds a stream chunk from stdout or stderr.
   */
  feed(chunk: string, channel: "stdout" | "stderr" = "stdout"): void {
    this.lastChunkTime = Date.now();

    // If we were in QuietStall, transition back to Streaming
    if (this._state === "QuietStall") {
      this._state = "Streaming";
      this.emit("resume");
      this.emit("state-change", "Streaming");
    }

    // Accumulate tail to detect incomplete line prompts
    if (chunk.includes("\n")) {
      const parts = chunk.split("\n");
      this.pendingTail = parts[parts.length - 1];
    } else {
      this.pendingTail += chunk;
    }

    // Check for interactive stdin prompt
    const cleanTail = stripAnsi(this.pendingTail);
    const matchedPrompt = this.matchPrompt(cleanTail);

    if (matchedPrompt && !cleanTail.endsWith("\n")) {
      if (this._state !== "AwaitingStdin") {
        this._state = "AwaitingStdin";
        this.disarmSilenceTimer();
        const event: PromptEvent = { promptText: cleanTail, channel };
        this.emit("prompt", event);
        this.emit("state-change", "AwaitingStdin");
      }
      return;
    }

    // If chunk ended with newline, clear pending prompt tail
    if (chunk.endsWith("\n")) {
      this.pendingTail = "";
    }

    // Re-arm silence timer if still running
    if (this._state === "Streaming") {
      this.armSilenceTimer();
    }
  }

  /**
   * Notifies the watcher that stdin input was sent by the agent/caller.
   */
  notifyInputSent(): void {
    this.pendingTail = "";
    if (this._state === "AwaitingStdin") {
      this._state = "Streaming";
      this.emit("state-change", "Streaming");
      this.armSilenceTimer();
    }
  }

  /**
   * Sets final exited or killed state and clears all timers.
   */
  stop(finalState: WatcherState = "Exited"): void {
    this._state = finalState;
    this.disarmSilenceTimer();
    this.emit("state-change", finalState);
  }

  private matchPrompt(text: string): boolean {
    if (!text) return false;
    const trimmed = text.trimEnd();
    return this.promptPatterns.some((pattern) => pattern.test(trimmed) || pattern.test(text));
  }

  private armSilenceTimer(): void {
    this.disarmSilenceTimer();
    this.silenceTimer = setTimeout(() => {
      if (this._state === "Streaming") {
        this._state = "QuietStall";
        const silentMs = Date.now() - this.lastChunkTime;
        const event: QuietStallEvent = { silentMs };
        this.emit("quiet-stall", event);
        this.emit("state-change", "QuietStall");
      }
    }, this.silenceTimeoutMs);
    // Unref so the timer does not prevent process exit if idle
    if (this.silenceTimer.unref) {
      this.silenceTimer.unref();
    }
  }

  private disarmSilenceTimer(): void {
    if (this.silenceTimer) {
      clearTimeout(this.silenceTimer);
      this.silenceTimer = null;
    }
  }
}
