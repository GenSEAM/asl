/**
 * SkyLoom Triple-Dialect Codec & Wire Parser
 * Supports: ASL Native S-expression, Compact Positional, and Polyglot JSON/Markdown.
 * Hardened for robust escape handling, arbitrary payloads, and zero schema drift.
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

function escapeStr(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

function unescapeStr(s: string): string {
  return s.replace(/\\"/g, '"').replace(/\\\\/g, '\\');
}

function escapePipe(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/\|/g, '\\|');
}

function unescapePipe(s: string): string {
  return s.replace(/\\\|/g, '|').replace(/\\\\/g, '\\');
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

  // Find :body marker separating header attributes from the body expression
  const bodyMarker = ':body ';
  const bodyIdx = trimmed.indexOf(bodyMarker);
  if (bodyIdx === -1) {
    throw new CodecError(ErrorCode.ERR_DECODE_FAILED, 'Missing :body in ASL frame');
  }

  const headerPart = trimmed.slice(11, bodyIdx).trim();
  const rawBodyPart = trimmed.slice(bodyIdx + bodyMarker.length, trimmed.length - 1).trim();

  // Extract attributes from headerPart safely
  const strAttrs: Record<string, string> = {};
  const strRegex = /:([a-zA-Z0-9_-]+)\s+"((?:[^"\\\\]|\\.)*)"/g;
  let match: RegExpExecArray | null;
  while ((match = strRegex.exec(headerPart)) !== null) {
    strAttrs[match[1]] = unescapeStr(match[2]);
  }

  const numAttrs: Record<string, number> = {};
  const numRegex = /:([a-zA-Z0-9_-]+)\s+([0-9]+)/g;
  while ((match = numRegex.exec(headerPart)) !== null) {
    numAttrs[match[1]] = Number(match[2]);
  }

  const version = numAttrs['v'] ?? 1;
  const id = strAttrs['id'];
  const from = strAttrs['from'];
  const to = strAttrs['to'];
  const type = strAttrs['type'] as FrameType | undefined;
  const timestamp = numAttrs['ts'] ?? Date.now();
  const replyTo = strAttrs['reply-to'];
  const channel = strAttrs['channel'];

  if (!id || !from || !to || !type) {
    throw new CodecError(ErrorCode.ERR_DECODE_FAILED, 'Missing required fields in ASL frame');
  }

  let body: unknown = null;
  try {
    body = JSON.parse(rawBodyPart);
  } catch {
    body = rawBodyPart;
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
 * SK1|v|id|from|to|type|channel|ts|replyTo|payload
 */
export function encodeCompact(frame: LoomFrame): string {
  const h = frame.header;
  const payloadStr = JSON.stringify(frame.body);
  const parts = [
    'SK1',
    h.version.toString(),
    escapePipe(h.id),
    escapePipe(h.from),
    escapePipe(h.to),
    frame.type,
    escapePipe(frame.channel || ''),
    h.timestamp.toString(),
    escapePipe(h.replyTo || ''),
    payloadStr,
  ];
  return parts.join('|');
}

export function decodeCompact(raw: string): LoomFrame {
  // Regex to split on unescaped pipes
  const parts: string[] = [];
  let current = '';
  let escaped = false;
  let fieldCount = 0;

  for (let i = 0; i < raw.length; i++) {
    const ch = raw[i];
    if (escaped) {
      current += ch;
      escaped = false;
    } else if (ch === '\\') {
      escaped = true;
      current += ch;
    } else if (ch === '|' && fieldCount < 9) {
      parts.push(current);
      current = '';
      fieldCount++;
    } else {
      current += ch;
    }
  }
  parts.push(current);

  if (parts.length < 10 || parts[0] !== 'SK1') {
    throw new CodecError(ErrorCode.ERR_DECODE_FAILED, 'Invalid Compact SkyLoom frame format');
  }

  const [, vStr, id, from, to, typeStr, channel, tsStr, replyTo, bodyRaw] = parts;

  let body: unknown = null;
  try {
    body = JSON.parse(bodyRaw);
  } catch {
    body = bodyRaw;
  }

  return validateFrame({
    header: {
      version: Number(vStr) || 1,
      id: unescapePipe(id),
      from: unescapePipe(from),
      to: unescapePipe(to),
      dialect: 'compact/v1',
      timestamp: Number(tsStr) || Date.now(),
      replyTo: replyTo ? unescapePipe(replyTo) : undefined,
    },
    type: typeStr as FrameType,
    channel: channel ? unescapePipe(channel) : undefined,
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
