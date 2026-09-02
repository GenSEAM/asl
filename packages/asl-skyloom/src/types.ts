/**
 * SkyLoom: Core Protocol Types & Contracts
 * Direct correspondence with ASL nominal types in src/core/skyloom.asl
 */

export type Dialect = 'asl/v1' | 'asl/coord' | 'compact/v1' | 'polyglot/v1';

export type FrameType =
  | 'HANDSHAKE'
  | 'DATA'
  | 'HANDOFF'
  | 'YIELD'
  | 'SPAWN'
  | 'ACK'
  | 'NACK'
  | 'PING'
  | 'PONG'
  | 'RENDEZVOUS'
  | 'LEAVE';

export enum ErrorCode {
  ERR_PEER_UNREACHABLE = 1001,
  ERR_LONELY_QUEUED = 1002,
  ERR_DIALECT_UNSUPPORTED = 1003,
  ERR_DECODE_FAILED = 1004,
  ERR_TYPE_MISMATCH = 1005,
  ERR_TIMEOUT = 1006,
  ERR_STALLED = 1007,
  ERR_DEAD_LETTER = 1008,
  ERR_SCOPE_VIOLATION = 1009,
  ERR_HANDOFF_REJECTED = 1010,
}

export interface LoomHeader {
  version: number;
  id: string;
  from: string;
  to: string;
  dialect?: Dialect;
  timestamp: number;
  replyTo?: string;
}

export interface LoomFrame {
  header: LoomHeader;
  type: FrameType;
  channel?: string;
  body: unknown;
  signature?: string;
}

export interface HandoffPayload {
  task: string;
  cwd?: string;
  owns?: string[];
  frozen?: string[];
  context?: Array<{ ref: string; export?: string[]; digest?: string }>;
  gate?: string;
  budget?: number;
  metadata?: Record<string, unknown>;
}

export interface YieldPayload {
  status: 'ok' | 'failed' | 'rejected';
  gateVerdict?: string;
  artifacts?: string[];
  tokensUsed?: number;
  error?: string;
  result?: unknown;
}

export interface PeerCapability {
  peerId: string;
  dialects: Dialect[];
  supportedChannels: string[];
  isAslNative: boolean;
  version: string;
  cwd?: string;
  permittedScopes?: string[];
  metadata?: Record<string, unknown>;
}

export interface HandshakePayload {
  capabilities: PeerCapability;
  protocolVersion: string;
  tokenBudget?: number;
}

export interface MailboxStatus {
  peerId: string;
  pendingCount: number;
  oldestTimestamp?: number;
  lonelySince?: number;
}
