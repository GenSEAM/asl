/**
 * SkyLoom Mesh Topology Router with Integrated Resilience
 * Routes frames between N agents across 1:1, pub/sub, and broadcast patterns.
 * Solves the Lonely Agent problem via Mailboxes, and manages Heartbeats + DLQ.
 */

import { EventEmitter } from 'events';
import { LoomFrame, PeerCapability, ErrorCode, Dialect } from './types.js';
import { validateFrame, decodeFrame, encodeFrame } from './codec.js';
import { SkyLoomMailbox, HeartbeatGuard, DeadLetterQueue } from './resilience.js';

export interface RouteResult {
  status: 'DELIVERED' | 'QUEUED' | 'DROPPED';
  recipients: string[];
  undelivered?: string[];
  errorCode?: ErrorCode;
  errorReason?: string;
}

export interface PeerConnection {
  peer: PeerCapability;
  send: (frame: LoomFrame) => Promise<boolean> | boolean;
  connectedAt: number;
}

export class SkyLoomRouter extends EventEmitter {
  private peers: Map<string, PeerConnection> = new Map();
  private channelSubscriptions: Map<string, Set<string>> = new Map();
  private messageLog: LoomFrame[] = [];

  public readonly mailbox: SkyLoomMailbox;
  public readonly heartbeatGuard: HeartbeatGuard;
  public readonly dlq: DeadLetterQueue;

  private mailboxTimer: NodeJS.Timeout | null = null;

  constructor(options?: { mailboxTtlMs?: number; heartbeatTimeoutMs?: number }) {
    super();
    this.mailbox = new SkyLoomMailbox(options?.mailboxTtlMs ?? 60000);
    this.heartbeatGuard = new HeartbeatGuard(options?.heartbeatTimeoutMs ?? 5000);
    this.dlq = new DeadLetterQueue();

    // Start watchdog to evict dead/stalled peers
    this.heartbeatGuard.startWatchdog((deadPeerId) => {
      this.unregisterPeer(deadPeerId, 'heartbeat_timeout');
    });

    // Periodically clean expired mailbox items
    this.mailboxTimer = setInterval(() => {
      this.mailbox.cleanExpired();
    }, 5000);
    if (this.mailboxTimer && typeof this.mailboxTimer.unref === 'function') {
      this.mailboxTimer.unref();
    }
  }

  /**
   * Registers a newly joined peer with its capabilities
   * Automatically flushes any spooled mailbox frames for this peer!
   */
  registerPeer(peer: PeerCapability, sendFn: (frame: LoomFrame) => Promise<boolean> | boolean): void {
    const isNew = !this.peers.has(peer.peerId);
    this.peers.set(peer.peerId, {
      peer,
      send: sendFn,
      connectedAt: Date.now(),
    });

    this.heartbeatGuard.recordHeartbeat(peer.peerId);

    // Auto-subscribe to default channels
    for (const ch of peer.supportedChannels || []) {
      this.subscribe(peer.peerId, ch);
    }

    this.emit('peer:registered', peer);
    if (isNew) {
      this.emit('peer:joined', peer);
    }

    // Drain mailbox for late-arriving peer
    const pendingFrames = this.mailbox.drain(peer.peerId);
    if (pendingFrames.length > 0) {
      for (const frame of pendingFrames) {
        Promise.resolve(sendFn(frame)).catch(() => {});
      }
      this.emit('lonely:resolved', { peerId: peer.peerId, deliveredCount: pendingFrames.length });
    }
  }

  /**
   * Record a heartbeat from an active peer
   */
  pingPeer(peerId: string): void {
    if (this.peers.has(peerId)) {
      this.heartbeatGuard.recordHeartbeat(peerId);
    }
  }

  /**
   * Unregisters a peer that disconnected or gracefully left
   */
  unregisterPeer(peerId: string, reason = 'client_left'): boolean {
    const existing = this.peers.get(peerId);
    if (!existing) return false;

    this.peers.delete(peerId);
    this.heartbeatGuard.unregister(peerId);

    // Clean up channel subscriptions
    for (const [ch, subscriberSet] of this.channelSubscriptions.entries()) {
      subscriberSet.delete(peerId);
      if (subscriberSet.size === 0) {
        this.channelSubscriptions.delete(ch);
      }
    }

    this.emit('peer:unregistered', { peerId, reason });
    this.emit('peer:left', { peerId, reason });
    return true;
  }

  /**
   * Subscribes a peer to a specific topic/channel
   */
  subscribe(peerId: string, channel: string): void {
    if (!this.channelSubscriptions.has(channel)) {
      this.channelSubscriptions.set(channel, new Set());
    }
    this.channelSubscriptions.get(channel)!.add(peerId);
    this.emit('channel:subscribed', { peerId, channel });
  }

  /**
   * Unsubscribes a peer from a topic/channel
   */
  unsubscribe(peerId: string, channel: string): void {
    const set = this.channelSubscriptions.get(channel);
    if (set) {
      set.delete(peerId);
      if (set.size === 0) {
        this.channelSubscriptions.delete(channel);
      }
      this.emit('channel:unsubscribed', { peerId, channel });
    }
  }

  /**
   * Returns list of currently active peers
   */
  getActivePeers(): PeerCapability[] {
    return Array.from(this.peers.values()).map(p => p.peer);
  }

  /**
   * Get peer by ID
   */
  getPeer(peerId: string): PeerCapability | undefined {
    return this.peers.get(peerId)?.peer;
  }

  /**
   * Get subscribers for a channel
   */
  getChannelSubscribers(channel: string): string[] {
    const set = this.channelSubscriptions.get(channel);
    return set ? Array.from(set) : [];
  }

  /**
   * Primary frame router with Lonely-Agent Mailbox buffering & DLQ protection
   */
  async route(rawOrFrame: string | LoomFrame, senderOverride?: string): Promise<RouteResult> {
    let frame: LoomFrame;
    if (typeof rawOrFrame === 'string') {
      frame = decodeFrame(rawOrFrame);
    } else {
      frame = validateFrame(rawOrFrame);
    }

    if (senderOverride) {
      frame.header.from = senderOverride;
    }

    // Refresh heartbeat for sender
    if (this.peers.has(frame.header.from)) {
      this.heartbeatGuard.recordHeartbeat(frame.header.from);
    }

    this.messageLog.push(frame);
    this.emit('frame', frame);

    const from = frame.header.from;
    const to = frame.header.to;
    const channel = frame.channel;

    // 1. Broadcast to channel or all peers
    if (to === '*' || to === 'broadcast') {
      if (!channel) {
        const recipients: string[] = [];
        for (const [id, conn] of this.peers.entries()) {
          if (id !== from) {
            await conn.send(frame);
            recipients.push(id);
          }
        }
        return { status: 'DELIVERED', recipients };
      } else {
        const subscribers = this.getChannelSubscribers(channel).filter(id => id !== from);
        if (subscribers.length === 0) {
          // No subscribers for this channel: buffer in mailbox under channel name
          this.mailbox.enqueue(frame);
          return {
            status: 'QUEUED',
            recipients: [],
            errorCode: ErrorCode.ERR_LONELY_QUEUED,
            errorReason: `No listeners currently subscribed to channel "${channel}"; message spooled in mailbox`,
          };
        }

        const recipients: string[] = [];
        for (const id of subscribers) {
          const conn = this.peers.get(id);
          if (conn) {
            await conn.send(frame);
            recipients.push(id);
          }
        }
        return { status: 'DELIVERED', recipients };
      }
    }

    // 2. Direct Point-to-Point routing
    const targetConn = this.peers.get(to);
    if (!targetConn) {
      // Lonely Agent resolution: Peer is not currently connected -> Buffer in Mailbox!
      this.mailbox.enqueue(frame);
      return {
        status: 'QUEUED',
        recipients: [],
        undelivered: [to],
        errorCode: ErrorCode.ERR_LONELY_QUEUED,
        errorReason: `Target peer "${to}" is not online. Message buffered in SkyLoom mailbox.`,
      };
    }

    // Check dialect compatibility & auto-adapt if needed
    const targetDialects = targetConn.peer.dialects;
    const frameDialect = frame.header.dialect;
    if (targetDialects.length > 0 && !targetDialects.includes(frameDialect)) {
      const preferred = targetDialects[0];
      const adaptedFrame: LoomFrame = {
        ...frame,
        header: {
          ...frame.header,
          dialect: preferred,
        },
      };
      await targetConn.send(adaptedFrame);
      return { status: 'DELIVERED', recipients: [to] };
    }

    try {
      await targetConn.send(frame);
      return { status: 'DELIVERED', recipients: [to] };
    } catch (err: any) {
      this.dlq.push(frame, ErrorCode.ERR_STALLED, err?.message || 'Send failed');
      return {
        status: 'DROPPED',
        recipients: [],
        undelivered: [to],
        errorCode: ErrorCode.ERR_STALLED,
        errorReason: `Delivery to peer "${to}" failed: ${err?.message}`,
      };
    }
  }

  /**
   * Stop router and watchdog timers
   */
  destroy(): void {
    this.heartbeatGuard.stopWatchdog();
    if (this.mailboxTimer) {
      clearInterval(this.mailboxTimer);
      this.mailboxTimer = null;
    }
  }

  /**
   * Get message history for diagnostics/telemetry
   */
  getMessageLog(limit = 100): LoomFrame[] {
    return this.messageLog.slice(-limit);
  }
}
