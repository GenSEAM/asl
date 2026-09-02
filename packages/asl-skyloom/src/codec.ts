/**
 * SkyLoom Triple-Dialect Codec & Wire Parser
 * Supports: ASL Native S-expression, Compact Positional, and Polyglot JSON/Markdown
 */

import { LoomFrame, LoomHeader, Dialect, FrameType, ErrorCode } from './types.js';

export class CodecError extends Error {
  constructor(public code: ErrorCode, message: string) {
    super(`[SkyLoom CodecError ${code}] ${message}`);
    this.name = 'CodecError';
  }
}

/**
 * Validates that an object conforms to LoomFrame schema
 */
export function validateFrame(obj: any): LoomFrame {
  if (!obj || typeof obj !== 'object') {
    throw new CodecError(ErrorCode.ERR_DECODE_FAILED, 'Frame must be a non-null object');
  }

  const header = obj.header;
  if (!header || typeof header !== 'object') {
    throw new CodecError(ErrorCode.ERR_DECODE_FAILED, 'Frame missing header object');
  }

  if (typeof header.version !== 'number' || !header.id || !header.from || !header.to) {
    throw new CodecError(ErrorCode.ERR_DECODE_FAILED, 'Invalid header fields (version, id, from, to required)');
  }

  const validTypes: FrameType[] = ['HANDSHAKE', 'DATA', 'ACK', 'NACK', 'PING', 'PONG', 'RENDEZVOUS', 'LEAVE'];
  if (!validTypes.includes(obj.type)) {
    throw new CodecError(ErrorCode.ERR_TYPE_MISMATCH, `Unsupported frame type: ${obj.type}`);
  }

  return obj as LoomFrame;
}

/**
 * Encodes a LoomFrame into ASL Native S-Expression syntax
 */
export function encodeAslSExpr(frame: LoomFrame): string {
  const h = frame.header;
  const replyPart = h.replyTo ? ` :reply-to "${escapeStr(h.replyTo)}"` : '';
  const chanPart = frame.channel ? ` :channel "${escapeStr(frame.channel)}"` : '';
  const bodyJson = JSON.stringify(frame.body);
  
  return `(loom:frame :v ${h.version} :id "${escapeStr(h.id)}" :from "${escapeStr(h.from)}" :to "${escapeStr(h.to)}" :dialect "asl/v1" :ts ${h.timestamp}${replyPart} :type "${frame.type}"${chanPart} :body ${bodyJson})`;
}

/**
 * Decodes ASL Native S-Expression into LoomFrame
 */
export function decodeAslSExpr(raw: string): LoomFrame {
  const trimmed = raw.trim();
  if (!trimmed.startsWith('(loom:frame') || !trimmed.endsWith(')')) {
    throw new CodecError(ErrorCode.ERR_DECODE_FAILED, 'Invalid ASL S-expression frame delimiter');
  }

  const getAttr = (key: string): string | undefined => {
    const regex = new RegExp(`:${key}\\s+"([^"]*)"`);
    const match = trimmed.match(regex);
    return match ? match[1] : undefined;
  };

  const getNumAttr = (key: string): number | undefined => {
    const regex = new RegExp(`:${key}\\s+([0-9]+)`);
    const match = trimmed.match(regex);
    return match ? Number(match[1]) : undefined;
  };

  const version = getNumAttr('v') ?? 1;
  const id = getAttr('id');
  const from = getAttr('from');
  const to = getAttr('to');
  const type = getAttr('type') as FrameType | undefined;
  const timestamp = getNumAttr('ts') ?? Date.now();
  const replyTo = getAttr('reply-to');
  const channel = getAttr('channel');

  // Extract :body
  const bodyIdx = trimmed.indexOf(':body ');
  if (bodyIdx === -1) {
    throw new CodecError(ErrorCode.ERR_DECODE_FAILED, 'Missing :body in ASL frame');
  }

  const rawBody = trimmed.slice(bodyIdx + 6, trimmed.length - 1).trim();
  let body: unknown = null;
  try {
    body = JSON.parse(rawBody);
  } catch {
    // If not raw JSON, use trimmed string
    body = rawBody;
  }

  if (!id || !from || !to || !type) {
    throw new CodecError(ErrorCode.ERR_DECODE_FAILED, 'Missing required fields in ASL frame');
  }

  return validateFrame({
    header: {
      version,
      id,
      from,
      to,
      dialect: 'asl/v1',
      timestamp,
      replyTo,
    },
    type,
    channel,
    body,
  });
}

/**
 * Compact Positional Token Codec:
 * [SK1|id|from|to|type|channel|ts|replyTo|base64_or_json_payload]
 */
export function encodeCompact(frame: LoomFrame): string {
  const h = frame.header;
  const payloadStr = JSON.stringify(frame.body);
  const parts = [
    'SK1',
    h.version,
    h.id,
    h.from,
    h.to,
    frame.type,
    frame.channel || '',
    h.timestamp,
    h.replyTo || '',
    payloadStr,
  ];
  return parts.join('|');
}

export function decodeCompact(raw: string): LoomFrame {
  const parts = raw.split('|');
  if (parts.length < 10 || parts[0] !== 'SK1') {
    throw new CodecError(ErrorCode.ERR_DECODE_FAILED, 'Invalid Compact SkyLoom frame format');
  }

  const [, vStr, id, from, to, typeStr, channel, tsStr, replyTo, ...payloadParts] = parts;
  const bodyRaw = payloadParts.join('|');
  let body: unknown = null;
  try {
    body = JSON.parse(bodyRaw);
  } catch {
    body = bodyRaw;
  }

  return validateFrame({
    header: {
      version: Number(vStr) || 1,
      id,
      from,
      to,
      dialect: 'compact/v1',
      timestamp: Number(tsStr) || Date.now(),
      replyTo: replyTo || undefined,
    },
    type: typeStr as FrameType,
    channel: channel || undefined,
    body,
  });
}

/**
 * Polyglot Markdown & Self-describing JSON Codec
 */
export function encodePolyglot(frame: LoomFrame): string {
  const h = frame.header;
  const meta = {
    v: h.version,
    id: h.id,
    from: h.from,
    to: h.to,
    dialect: 'polyglot/v1',
    type: frame.type,
    channel: frame.channel,
    timestamp: h.timestamp,
    replyTo: h.replyTo,
  };

  const bodyJson = JSON.stringify(frame.body, null, 2);
  return `<!-- SKYLOOM_HEADER: ${JSON.stringify(meta)} -->
[SkyLoom Inter-Agent Protocol Frame]
From Agent: ${h.from}
To Agent: ${h.to}
Message Type: ${frame.type}${frame.channel ? ` | Channel: ${frame.channel}` : ''}

\`\`\`json
${bodyJson}
\`\`\`
<!-- SKYLOOM_FOOTER -->`;
}

export function decodePolyglot(raw: string): LoomFrame {
  const headerMatch = raw.match(/<!-- SKYLOOM_HEADER:\s*({.*?})\s*-->/s);
  if (headerMatch) {
    try {
      const meta = JSON.parse(headerMatch[1]);
      
      // Extract json block
      const jsonMatch = raw.match(/```json\s*([\s\S]*?)\s*```/);
      let body: unknown = null;
      if (jsonMatch) {
        body = JSON.parse(jsonMatch[1]);
      }

      return validateFrame({
        header: {
          version: meta.v || 1,
          id: meta.id,
          from: meta.from,
          to: meta.to,
          dialect: 'polyglot/v1',
          timestamp: meta.timestamp || Date.now(),
          replyTo: meta.replyTo,
        },
        type: meta.type as FrameType,
        channel: meta.channel,
        body,
      });
    } catch (err: any) {
      throw new CodecError(ErrorCode.ERR_DECODE_FAILED, `Malformed Polyglot header: ${err?.message}`);
    }
  }

  // Fallback: standard JSON payload
  try {
    const parsed = JSON.parse(raw);
    if (parsed.header && parsed.type) {
      return validateFrame(parsed);
    }
    // Convert generic JSON to polyglot data frame
    return validateFrame({
      header: {
        version: 1,
        id: `auto-${Date.now()}`,
        from: 'unknown-peer',
        to: 'self',
        dialect: 'polyglot/v1',
        timestamp: Date.now(),
      },
      type: 'DATA',
      body: parsed,
    });
  } catch {
    throw new CodecError(ErrorCode.ERR_DECODE_FAILED, 'Unable to parse polyglot payload');
  }
}

/**
 * Universal dialect detection
 */
export function detectDialect(raw: string): Dialect {
  const trimmed = raw.trim();
  if (trimmed.startsWith('(loom:frame')) {
    return 'asl/v1';
  }
  if (trimmed.startsWith('SK1|')) {
    return 'compact/v1';
  }
  return 'polyglot/v1';
}

/**
 * Universal Frame Encoder
 */
export function encodeFrame(frame: LoomFrame, targetDialect?: Dialect): string {
  const dialect = targetDialect || frame.header.dialect || 'asl/v1';
  switch (dialect) {
    case 'asl/v1':
      return encodeAslSExpr({ ...frame, header: { ...frame.header, dialect: 'asl/v1' } });
    case 'compact/v1':
      return encodeCompact({ ...frame, header: { ...frame.header, dialect: 'compact/v1' } });
    case 'polyglot/v1':
      return encodePolyglot({ ...frame, header: { ...frame.header, dialect: 'polyglot/v1' } });
    default:
      throw new CodecError(ErrorCode.ERR_DIALECT_UNSUPPORTED, `Unsupported dialect: ${dialect}`);
  }
}

/**
 * Universal Frame Decoder
 */
export function decodeFrame(raw: string): LoomFrame {
  const dialect = detectDialect(raw);
  switch (dialect) {
    case 'asl/v1':
      return decodeAslSExpr(raw);
    case 'compact/v1':
      return decodeCompact(raw);
    case 'polyglot/v1':
      return decodePolyglot(raw);
  }
}

function escapeStr(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}
