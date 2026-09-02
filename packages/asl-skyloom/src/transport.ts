/**
 * SkyLoom Transport Layer
 * Provides Unix Domain Socket, In-Memory EventBus, and SSE streaming transports.
 */

import * as net from 'net';
import * as fs from 'fs';
import { EventEmitter } from 'events';
import { SkyLoomRouter } from './mesh.js';
import { LoomFrame, PeerCapability } from './types.js';
import { encodeFrame, decodeFrame } from './codec.js';

export interface TransportServer {
  start(): Promise<void>;
  stop(): Promise<void>;
}

/**
 * In-Memory Transport for testing and warm co-located subagents
 */
export class InMemoryAgentClient extends EventEmitter {
  public receivedFrames: LoomFrame[] = [];

  constructor(
    public readonly capability: PeerCapability,
    private router: SkyLoomRouter
  ) {
    super();
  }

  connect(): void {
    this.router.registerPeer(this.capability, async (frame: LoomFrame) => {
      this.receivedFrames.push(frame);
      this.emit('message', frame);
      return true;
    });
  }

  disconnect(): void {
    this.router.unregisterPeer(this.capability.peerId);
  }

  subscribe(channel: string): void {
    this.router.subscribe(this.capability.peerId, channel);
  }

  unsubscribe(channel: string): void {
    this.router.unsubscribe(this.capability.peerId, channel);
  }

  async send(to: string, type: LoomFrame['type'], body: unknown, channel?: string): Promise<any> {
    const frame: LoomFrame = {
      header: {
        version: 1,
        id: `msg-${Math.random().toString(36).slice(2, 9)}`,
        from: this.capability.peerId,
        to,
        dialect: this.capability.dialects[0] || 'asl/v1',
        timestamp: Date.now(),
      },
      type,
      channel,
      body,
    };
    return this.router.route(frame);
  }
}

/**
 * Unix Domain Socket Transport Server
 */
export class UnixSocketDaemon implements TransportServer {
  private server: net.Server | null = null;

  constructor(
    private router: SkyLoomRouter,
    public readonly socketPath: string = '/tmp/skyloom.sock'
  ) {}

  async start(): Promise<void> {
    if (fs.existsSync(this.socketPath)) {
      try {
        fs.unlinkSync(this.socketPath);
      } catch {
        // ignore if not removable
      }
    }

    return new Promise((resolve, reject) => {
      this.server = net.createServer((socket) => {
        let peerId: string | null = null;
        let buffer = '';

        socket.on('data', async (chunk) => {
          buffer += chunk.toString('utf-8');
          const lines = buffer.split('\n');
          buffer = lines.pop() || '';

          for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;

            try {
              const frame = decodeFrame(trimmed);
              if (frame.type === 'HANDSHAKE') {
                const payload = frame.body as any;
                peerId = payload.capabilities?.peerId || frame.header.from;
                this.router.registerPeer(
                  payload.capabilities || {
                    peerId,
                    dialects: [frame.header.dialect],
                    supportedChannels: [],
                    isAslNative: true,
                    version: '1.0.0',
                  },
                  (outFrame: LoomFrame) => {
                    const encoded = encodeFrame(outFrame, frame.header.dialect) + '\n';
                    socket.write(encoded);
                    return true;
                  }
                );
              } else {
                await this.router.route(frame);
              }
            } catch (err: any) {
              socket.write(JSON.stringify({ error: err?.message }) + '\n');
            }
          }
        });

        socket.on('close', () => {
          if (peerId) {
            this.router.unregisterPeer(peerId, 'socket_closed');
          }
        });

        socket.on('error', () => {
          if (peerId) {
            this.router.unregisterPeer(peerId, 'socket_error');
          }
        });
      });

      this.server.listen(this.socketPath, () => {
        resolve();
      });

      this.server.on('error', (err) => {
        reject(err);
      });
    });
  }

  async stop(): Promise<void> {
    return new Promise((resolve) => {
      if (this.server) {
        this.server.close(() => {
          if (fs.existsSync(this.socketPath)) {
            try {
              fs.unlinkSync(this.socketPath);
            } catch {}
          }
          resolve();
        });
      } else {
        resolve();
      }
    });
  }
}
