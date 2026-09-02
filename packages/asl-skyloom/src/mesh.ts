/**
 * SkyLoom Mesh Topology Router with Integrated Resilience & Directory Scoping
 * Routes frames between N agents across 1:1, pub/sub, and broadcast patterns.
 * Solves the Lonely Agent problem via Mailboxes, manages Heartbeats + DLQ,
 * and enforces Zero-Leak Directory Scoping / Firewall boundaries.
 */

import { EventEmitter } from 'events';
import { LoomFrame, PeerCapability, ErrorCode, Dialect, HandoffPayload } from './types.js';
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

/**
 * Checks whether a given target path / channel falls within a declared scope pattern
 * Supports exact match, wildcard '*', and directory globbing 'dir/*'
 */
export function isPathInScope(scopePattern: string, targetPath: string): boolean {
  if (scopePattern === '*' || scopePattern === '**') return true;
  const cleanScope = scopePattern.replace(/\/\*+$/, '').replace(/\/$/, '');
  const cleanTarget = targetPath.replace(/\/$/, '');
  if (cleanScope === cleanTarget) return true;
  return cleanTarget.startsWith(cleanScope + '/');
}

/**
 * Verifies if a peer is permitted to access a given scope, directory, or topic channel
 */
export function isPeerPermitted(peer: PeerCapability, targetScope: string): boolean {
  if (!peer.permittedScopes || peer.permittedScopes.length === 0 || peer.permittedScopes.includes('*')) {
    return true;
  }
  return peer.permittedScopes.some(pattern => isPathInScope(pattern, targetScope));
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
   * Registers a newly joined peer with its capabilities and directory scope
   * Automatically flushes any spooled mailbox frames for this peer!
   */
  registerPeer(peer: PeerCapability, sendFn: (frame: LoomFrame) => Promise<boolean> | boolean): void {
    const isNew = !this.peers.has(peer.peerId);
    this.peers.set(peer.peerId, {
      peer: {
        ...peer,
        permittedScopes: peer.permittedScopes || ['*'],
      },
      send: sendFn,
      connectedAt: Date.now(),
    });

    this.heartbeatGuard.recordHeartbeat(peer.peerId);

    // Auto-subscribe to declared initial channels
    if (peer.supportedChannels && peer.supportedChannels.length > 0) {
      for (const ch of peer.supportedChannels) {
        this.subscribe(peer.peerId, ch);
      }
    }

    if (isNew) {
      this.emit('peer:registered', peer);
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
   * Updates or locks a peer's directory scope jail
   */
  setPeerScope(peerId: string, cwd: string, permittedScopes?: string[]): boolean {
    const conn = this.peers.get(peerId);
    if (!conn) return false;
    conn.peer.cwd = cwd;
    conn.peer.permittedScopes = permittedScopes || [cwd, `${cwd}/*`];
    this.emit('peer:scoped', { peerId, cwd, permittedScopes: conn.peer.permittedScopes });
    return true;
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
   * Primary frame router with Zero-Leak Scope Firewall, Lonely-Agent Mailbox & DLQ
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

    const from = frame.header.from;
    const to = frame.header.to;
    const channel = frame.channel;

    // Refresh heartbeat for sender
    if (this.peers.has(from)) {
      this.heartbeatGuard.recordHeartbeat(from);
    }

    // 0. Zero-Leak Firewall: Check sender scope permissions
    const senderConn = this.peers.get(from);
    if (senderConn && senderConn.peer.permittedScopes && !senderConn.peer.permittedScopes.includes('*')) {
      // Check channel scope
      if (channel && !isPeerPermitted(senderConn.peer, channel)) {
        this.dlq.push(
          frame,
          ErrorCode.ERR_SCOPE_VIOLATION,
          `Sender "${from}" lacks permission for scope "${channel}"`
        );
        return {
          status: 'DROPPED',
          recipients: [],
          errorCode: ErrorCode.ERR_SCOPE_VIOLATION,
          errorReason: `Sender "${from}" lacks permission for scope "${channel}"`,
        };
      }
      // Check handoff target directory scope
      if (frame.type === 'HANDOFF') {
        const payload = frame.body as HandoffPayload;
        if (payload?.cwd && !isPeerPermitted(senderConn.peer, payload.cwd)) {
          this.dlq.push(
            frame,
            ErrorCode.ERR_SCOPE_VIOLATION,
            `Sender "${from}" attempted to assign handoff outside its scope: "${payload.cwd}"`
          );
          return {
            status: 'DROPPED',
            recipients: [],
            errorCode: ErrorCode.ERR_SCOPE_VIOLATION,
            errorReason: `Sender "${from}" lacks authority over target directory "${payload.cwd}"`,
          };
        }
      }
    }

    this.messageLog.push(frame);
    this.emit('frame', frame);

    // 1. Broadcast / Pub-Sub routing with Zero-Leak recipient filtering
    if (to === '*' || to === 'broadcast') {
      if (!channel) {
        // Unscoped global broadcast: only deliver to un-jailed / global peers
        const recipients: string[] = [];
        for (const [id, conn] of this.peers.entries()) {
          if (id !== from && isPeerPermitted(conn.peer, '*')) {
            await conn.send(frame);
            recipients.push(id);
          }
        }
        return { status: 'DELIVERED', recipients };
      } else {
        const subscribers = this.getChannelSubscribers(channel).filter(id => id !== from);
        if (subscribers.length === 0) {
          // No subscribers for this channel: buffer in mailbox
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
          // Zero-Leak Filter: peer must be permitted to receive this channel
          if (conn && isPeerPermitted(conn.peer, channel)) {
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

    // Direct Zero-Leak Filter: Verify target peer permits receiving this scope
    if (channel && !isPeerPermitted(targetConn.peer, channel)) {
      this.dlq.push(
        frame,
        ErrorCode.ERR_SCOPE_VIOLATION,
        `Target peer "${to}" is jailed outside channel scope "${channel}"`
      );
      return {
        status: 'DROPPED',
        recipients: [],
        errorCode: ErrorCode.ERR_SCOPE_VIOLATION,
        errorReason: `Target peer "${to}" cannot receive messages from scope "${channel}"`,
      };
    }

    // If Handoff frame: auto-bind target peer's active directory scope!
    if (frame.type === 'HANDOFF') {
      const payload = frame.body as HandoffPayload;
      if (payload?.cwd) {
        this.setPeerScope(to, payload.cwd);
      }
    }

    // Check dialect compatibility & auto-adapt if needed
    const targetDialects = targetConn.peer.dialects;
    const defaultDialect: Dialect = (frame.type === 'HANDOFF' || frame.type === 'YIELD') ? 'asl/coord' : 'compact/v1';
    const frameDialect: Dialect = frame.header.dialect || defaultDialect;
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
        errorCode: ErrorCode.ERR_STALLED,
        errorReason: err?.message || 'Send failed',
      };
    }
  }

  destroy(): void {
    this.heartbeatGuard.stopWatchdog();
    if (this.mailboxTimer) {
      clearInterval(this.mailboxTimer);
      this.mailboxTimer = null;
    }
  }

  getMessageLog(): LoomFrame[] {
    return [...this.messageLog];
  }
}
