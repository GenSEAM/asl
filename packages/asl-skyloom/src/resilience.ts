/**
 * SkyLoom Resilience Engine: Mailbox, Heartbeat Guard, and Dead Letter Queue (DLQ)
 * Addresses the Lonely Agent problem, stalls, timeouts, and crashed peers.
 */

import { EventEmitter } from 'events';
import { LoomFrame, ErrorCode, MailboxStatus } from './types.js';

export interface MailboxItem {
  frame: LoomFrame;
  enqueuedAt: number;
  expiresAt: number;
  attempts: number;
}

export interface DlqItem {
  frame: LoomFrame;
  code: ErrorCode;
  reason: string;
  failedAt: number;
  attempts: number;
}

/**
 * SkyLoom Mailbox for Lonely Agents & Offline Counterparties
 */
export class SkyLoomMailbox extends EventEmitter {
  private queues: Map<string, MailboxItem[]> = new Map(); // targetPeerId -> items

  constructor(public defaultTtlMs: number = 60000) {
    super();
  }

  /**
   * Enqueue a frame for a target peer that is currently offline or unreachable
   */
  enqueue(frame: LoomFrame, ttlMs?: number): void {
    const target = frame.header.to;
    const ttl = ttlMs ?? this.defaultTtlMs;
    const item: MailboxItem = {
      frame,
      enqueuedAt: Date.now(),
      expiresAt: Date.now() + ttl,
      attempts: 0,
    };

    if (!this.queues.has(target)) {
      this.queues.set(target, []);
    }

    this.queues.get(target)!.push(item);
    this.emit('message:queued', { peerId: target, frameId: frame.header.id });
  }

  /**
   * Drains all valid (non-expired) messages for a newly arrived peer
   */
  drain(peerId: string): LoomFrame[] {
    const queue = this.queues.get(peerId);
    if (!queue || queue.length === 0) {
      return [];
    }

    const now = Date.now();
    const valid: LoomFrame[] = [];
    const remaining: MailboxItem[] = [];

    for (const item of queue) {
      if (item.expiresAt > now) {
        item.attempts += 1;
        valid.push(item.frame);
      } else {
        this.emit('message:expired', { peerId, frame: item.frame });
      }
    }

    this.queues.delete(peerId);
    if (remaining.length > 0) {
      this.queues.set(peerId, remaining);
    }

    if (valid.length > 0) {
      this.emit('mailbox:drained', { peerId, count: valid.length });
    }

    return valid;
  }

  /**
   * Returns mailbox status for a peer
   */
  getStatus(peerId: string): MailboxStatus {
    const queue = this.queues.get(peerId) || [];
    const now = Date.now();
    const active = queue.filter(item => item.expiresAt > now);

    return {
      peerId,
      pendingCount: active.length,
      oldestTimestamp: active.length > 0 ? active[0].enqueuedAt : undefined,
      lonelySince: active.length > 0 ? active[0].enqueuedAt : undefined,
    };
  }

  /**
   * Cleans all expired frames across all queues
   */
  cleanExpired(): number {
    const now = Date.now();
    let expiredCount = 0;

    for (const [peerId, queue] of this.queues.entries()) {
      const active = queue.filter(item => {
        const ok = item.expiresAt > now;
        if (!ok) expiredCount++;
        return ok;
      });

      if (active.length === 0) {
        this.queues.delete(peerId);
      } else {
        this.queues.set(peerId, active);
      }
    }

    return expiredCount;
  }
}

/**
 * Heartbeat Watchdog & Lease Monitor
 */
export class HeartbeatGuard extends EventEmitter {
  private lastSeen: Map<string, number> = new Map();
  private timer: NodeJS.Timeout | null = null;

  constructor(
    public readonly heartbeatTimeoutMs: number = 5000,
    checkIntervalMs?: number
  ) {
    super();
    this.checkIntervalMs = checkIntervalMs ?? Math.min(1000, Math.max(20, Math.floor(this.heartbeatTimeoutMs / 4)));
  }
  public readonly checkIntervalMs: number;

  recordHeartbeat(peerId: string): void {
    this.lastSeen.set(peerId, Date.now());
    this.emit('heartbeat:received', { peerId, timestamp: Date.now() });
  }

  unregister(peerId: string): void {
    this.lastSeen.delete(peerId);
  }

  startWatchdog(onEvict: (deadPeerId: string) => void): void {
    if (this.timer) return;
    this.timer = setInterval(() => {
      const now = Date.now();
      for (const [peerId, ts] of this.lastSeen.entries()) {
        if (now - ts > this.heartbeatTimeoutMs) {
          this.lastSeen.delete(peerId);
          this.emit('peer:stalled', { peerId, elapsedMs: now - ts });
          onEvict(peerId);
        }
      }
    }, this.checkIntervalMs);
    if (this.timer && typeof this.timer.unref === 'function') {
      this.timer.unref();
    }
  }

  stopWatchdog(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }
}

/**
 * Dead Letter Queue (DLQ)
 */
export class DeadLetterQueue extends EventEmitter {
  private dlq: DlqItem[] = [];

  constructor(public maxCapacity: number = 1000) {
    super();
  }

  push(frame: LoomFrame, code: ErrorCode, reason: string): void {
    const item: DlqItem = {
      frame,
      code,
      reason,
      failedAt: Date.now(),
      attempts: 1,
    };

    this.dlq.push(item);
    if (this.dlq.length > this.maxCapacity) {
      this.dlq.shift();
    }

    this.emit('dlq:item', item);
  }

  getItems(): DlqItem[] {
    return [...this.dlq];
  }

  getAll(): DlqItem[] {
    return this.getItems();
  }

  clear(): void {
    this.dlq = [];
  }
}
