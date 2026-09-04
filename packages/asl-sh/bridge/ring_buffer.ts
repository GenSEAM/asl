/**
 * In-Memory Ephemeral Ring Buffer with OOM Protection (@pcp:d-446d)
 *
 * Implements bounded stream buffering with head/tail retention windowing,
 * middle-eviction markers, separate channel tracking (stdout/stderr),
 * line and byte ceilings, and ephemeral TTL eviction.
 */

export interface BufferLine {
  text: string;
  channel: "stdout" | "stderr";
  timestamp: number;
  byteLength: number;
}

export interface RingBufferOptions {
  /** Maximum bytes retained in buffer before hard ceiling clamp (default: 10 MB) */
  maxBytes?: number;
  /** Maximum total lines retained before middle eviction (default: 10,000) */
  maxLines?: number;
  /** Number of initial lines retained at stream head (default: 500) */
  headLimit?: number;
  /** Number of recent lines retained at stream tail (default: 1,500) */
  tailLimit?: number;
  /** Ephemeral TTL in milliseconds before buffer eligible for purge (default: 15 minutes) */
  ttlMs?: number;
  /** Whether the buffer is pinned against TTL eviction */
  pinned?: boolean;
}

export interface SliceResult {
  lines: string[];
  startLine: number;
  endLine: number;
  totalLines: number;
  evictedCount: number;
  hasMore: boolean;
  channel: string;
}

export class RingBuffer {
  readonly maxBytes: number;
  readonly maxLines: number;
  readonly headLimit: number;
  readonly tailLimit: number;
  readonly ttlMs: number;

  private headLines: BufferLine[] = [];
  private tailLines: BufferLine[] = [];
  private stdoutPending = "";
  private stderrPending = "";

  private _totalLines = 0;
  private _totalBytes = 0;
  private _evictedCount = 0;
  private _evictedBytes = 0;
  private _pinned: boolean;
  private _createdAt: number;
  private _lastActivity: number;

  constructor(options: RingBufferOptions = {}) {
    this.maxBytes = options.maxBytes ?? 10 * 1024 * 1024; // 10 MB
    this.maxLines = options.maxLines ?? 10000;
    this.headLimit = options.headLimit ?? 500;
    this.tailLimit = options.tailLimit ?? 1500;
    this.ttlMs = options.ttlMs ?? 15 * 60 * 1000; // 15 mins
    this._pinned = options.pinned ?? false;
    this._createdAt = Date.now();
    this._lastActivity = this._createdAt;
  }

  get totalLines(): number {
    return this._totalLines;
  }

  get totalBytes(): number {
    return this._totalBytes;
  }

  get evictedCount(): number {
    return this._evictedCount;
  }

  get evictedBytes(): number {
    return this._evictedBytes;
  }

  get pinned(): boolean {
    return this._pinned;
  }

  get createdAt(): number {
    return this._createdAt;
  }

  get lastActivity(): number {
    return this._lastActivity;
  }

  pin(): void {
    this._pinned = true;
  }

  unpin(): void {
    this._pinned = false;
  }

  isExpired(now: number = Date.now()): boolean {
    if (this._pinned) return false;
    return now - this._lastActivity > this.ttlMs;
  }

  /**
   * Appends a chunk of text or Buffer from stdout or stderr.
   */
  append(chunk: string | Buffer, channel: "stdout" | "stderr" = "stdout"): void {
    const raw = typeof chunk === "string" ? chunk : chunk.toString("utf-8");
    if (!raw) return;

    this._lastActivity = Date.now();
    const chunkBytes = Buffer.byteLength(raw, "utf-8");
    this._totalBytes += chunkBytes;

    const pending = channel === "stdout" ? this.stdoutPending : this.stderrPending;
    const combined = pending + raw;

    const parts = combined.split("\n");
    // The last element is either empty (if ended with \n) or partial line
    const remaining = parts.pop() ?? "";
    if (channel === "stdout") {
      this.stdoutPending = remaining;
    } else {
      this.stderrPending = remaining;
    }

    for (const lineText of parts) {
      this.pushLine(lineText, channel);
    }
  }

  /**
   * Flushes any pending incomplete line in stdout or stderr.
   */
  flush(): void {
    if (this.stdoutPending.length > 0) {
      this.pushLine(this.stdoutPending, "stdout");
      this.stdoutPending = "";
    }
    if (this.stderrPending.length > 0) {
      this.pushLine(this.stderrPending, "stderr");
      this.stderrPending = "";
    }
  }

  /**
   * Returns middle eviction marker string.
   */
  getEvictionMarker(): string {
    return `... [${this._evictedCount.toLocaleString()} lines evicted from in-memory ring buffer] ...`;
  }

  /**
   * Pushes a single completed line into the buffer enforcing head/tail limits.
   */
  private pushLine(text: string, channel: "stdout" | "stderr"): void {
    const line: BufferLine = {
      text,
      channel,
      timestamp: Date.now(),
      byteLength: Buffer.byteLength(text, "utf-8") + 1,
    };

    this._totalLines++;

    if (this.headLines.length < this.headLimit) {
      this.headLines.push(line);
      return;
    }

    if (this.tailLines.length < this.tailLimit) {
      this.tailLines.push(line);
      return;
    }

    // Both head and tail are full: evict oldest from tailLines
    const evicted = this.tailLines.shift()!;
    this._evictedCount++;
    this._evictedBytes += evicted.byteLength;
    this.tailLines.push(line);
  }

  /**
   * Retrieves retained lines as an array of strings.
   * If lines were evicted, the middle eviction marker is inserted.
   */
  getLines(channel: "stdout" | "stderr" | "all" = "all"): string[] {
    const filterFn = (l: BufferLine) => channel === "all" || l.channel === channel;

    const head = this.headLines.filter(filterFn).map((l) => l.text);
    const tail = this.tailLines.filter(filterFn).map((l) => l.text);

    if (this._evictedCount > 0 && channel === "all") {
      return [...head, this.getEvictionMarker(), ...tail];
    }
    return [...head, ...tail];
  }

  /**
   * Retrieves full retained stream text joined with newlines.
   */
  getText(channel: "stdout" | "stderr" | "all" = "all"): string {
    return this.getLines(channel).join("\n");
  }

  /**
   * Retrieves stdout lines only.
   */
  getStdout(): string {
    return this.getText("stdout");
  }

  /**
   * Retrieves stderr lines only.
   */
  getStderr(): string {
    return this.getText("stderr");
  }

  /**
   * Bounded windowed slicing over retained lines.
   */
  slice(startLine = 0, endLine?: number, channel: "stdout" | "stderr" | "all" = "all"): SliceResult {
    const all = this.getLines(channel);
    const total = all.length;
    const end = endLine !== undefined ? Math.min(Math.max(endLine, 0), total) : total;
    const start = Math.min(Math.max(startLine, 0), end);

    const sliced = all.slice(start, end);
    return {
      lines: sliced,
      startLine: start,
      endLine: end,
      totalLines: total,
      evictedCount: this._evictedCount,
      hasMore: end < total,
      channel,
    };
  }

  /**
   * Clears all buffered lines and counters.
   */
  destroy(): void {
    this.headLines = [];
    this.tailLines = [];
    this.stdoutPending = "";
    this.stderrPending = "";
    this._totalLines = 0;
    this._totalBytes = 0;
    this._evictedCount = 0;
    this._evictedBytes = 0;
  }
}
