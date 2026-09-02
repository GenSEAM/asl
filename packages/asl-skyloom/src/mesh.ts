/**
 * SkyLoom Mesh Topology Router
 * Routes frames between N agents across 1:1, pub/sub, and broadcast patterns.
 */

import { EventEmitter } from 'events';
import { LoomFrame, PeerCapability, ErrorCode, Dialect } from './types.js';
import { validateFrame, decodeFrame, encodeFrame } from './codec.js';

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

  constructor() {
    super();
  }

  /**
   * Registers a newly joined peer with its capabilities
   */
  registerPeer(peer: PeerCapability, sendFn: (frame: LoomFrame) => Promise<boolean> | boolean): void {
    const isNew = !this.peers.has(peer.peerId);
    this.peers.set(peer.peerId, {
      peer,
      send: sendFn,
      connectedAt: Date.now(),
    });

    // Auto-subscribe to default channels
    for (const ch of peer.supportedChannels || []) {
      this.subscribe(peer.peerId, ch);
    }

    this.emit('peer:registered', peer);
    if (isNew) {
      this.emit('peer:joined', peer);
    }
  }

  /**
   * Unregisters a peer that disconnected or gracefully left
   */
  unregisterPeer(peerId: string, reason = 'client_left'): boolean {
    const existing = this.peers.get(peerId);
    if (!existing) return false;

    this.peers.delete(peerId);

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
   * Primary frame router
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

    this.messageLog.push(frame);
    this.emit('frame', frame);

    const from = frame.header.from;
    const to = frame.header.to;
    const channel = frame.channel;

    // 1. Broadcast to channel
    if (to === '*' || to === 'broadcast') {
      if (!channel) {
        // Broadcast to all connected peers except sender
        const recipients: string[] = [];
        for (const [id, conn] of this.peers.entries()) {
          if (id !== from) {
            await conn.send(frame);
            recipients.push(id);
          }
        }
        return { status: 'DELIVERED', recipients };
      } else {
        // Topic broadcast
        const subscribers = this.getChannelSubscribers(channel).filter(id => id !== from);
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
      return {
        status: 'DROPPED',
        recipients: [],
        undelivered: [to],
        errorCode: ErrorCode.ERR_PEER_UNREACHABLE,
        errorReason: `Target peer ${to} is not connected to SkyLoom mesh`,
      };
    }

    // Check dialect compatibility
    const targetDialects = targetConn.peer.dialects;
    const frameDialect = frame.header.dialect;
    if (targetDialects.length > 0 && !targetDialects.includes(frameDialect)) {
      // Auto-adapt dialect to target's preferred dialect
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

    await targetConn.send(frame);
    return { status: 'DELIVERED', recipients: [to] };
  }

  /**
   * Get message history for diagnostics/telemetry
   */
  getMessageLog(limit = 100): LoomFrame[] {
    return this.messageLog.slice(-limit);
  }
}
