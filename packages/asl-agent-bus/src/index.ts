/**
 * TypeScript Agent Bus & SSE / WebSocket Hub
 */
import { EventEmitter } from 'events';

export interface AgentPeer {
  id: string;
  name: string;
  role: 'orchestrator' | 'planner' | 'coder' | 'reviewer' | 'searcher';
  status: 'idle' | 'busy' | 'streaming' | 'terminated';
  lastPing: number;
}

export interface AgentPacket {
  id: string;
  from: string;
  to: string;
  event: string;
  payload: Record<string, unknown>;
  timestamp: number;
}

export class AgentBusServer extends EventEmitter {
  private peers: Map<string, AgentPeer> = new Map();
  private messageHistory: AgentPacket[] = [];

  registerPeer(peer: AgentPeer): void {
    this.peers.set(peer.id, { ...peer, lastPing: Date.now() });
    this.emit('peer:registered', peer);
  }

  getPeers(): AgentPeer[] {
    return Array.from(this.peers.values());
  }

  send(packet: AgentPacket): boolean {
    this.messageHistory.push(packet);
    this.emit(`msg:${packet.to}`, packet);
    this.emit('broadcast', packet);
    return true;
  }

  formatSSE(event: string, data: unknown): string {
    return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  }
}
