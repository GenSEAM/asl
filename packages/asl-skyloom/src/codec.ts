/**
 * SkyLoom Triple-Dialect Codec & Wire Parser
 * Supports:
 *  - ASL Native S-expression (`asl/v1`)
 *  - ASL Coordination & Handoff Dialect (`asl/coord`)
 *  - Compact Positional Token stream (`compact/v1`)
 *  - Polyglot Markdown & JSON (`polyglot/v1`)
 */

import { LoomFrame, LoomHeader, Dialect, FrameType, ErrorCode, HandoffPayload, YieldPayload } from './types.js';

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

  const validTypes: FrameType[] = [
    'HANDSHAKE',
    'DATA',
    'HANDOFF',
    'YIELD',
    'SPAWN',
    'ACK',
    'NACK',
    'PING',
    'PONG',
    'RENDEZVOUS',
    'LEAVE',
  ];
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
 * Encodes a LoomFrame into ASL Native S-Expression syntax (`asl/v1`)
 */
export function encodeAslSExpr(frame: LoomFrame): string {
  const h = frame.header;
  const replyPart = h.replyTo ? ` :reply-to "${escapeStr(h.replyTo)}"` : '';
  const chanPart = frame.channel ? ` :channel "${escapeStr(frame.channel)}"` : '';
  const bodyJson = JSON.stringify(frame.body);
  
  return `(loom:frame :v ${h.version} :id "${escapeStr(h.id)}" :from "${escapeStr(h.from)}" :to "${escapeStr(h.to)}" :dialect "asl/v1" :ts ${h.timestamp}${replyPart} :type "${frame.type}"${chanPart} :body ${bodyJson})`;
}

function parseSExprAttrs(source: string) {
  const strAttrs: Record<string, string> = {};
  const strRegex = /:([a-zA-Z0-9_-]+)\s+"((?:[^"\\\\]|\\.)*)"/g;
  let match: RegExpExecArray | null;
  while ((match = strRegex.exec(source)) !== null) {
    strAttrs[match[1]] = unescapeStr(match[2]);
  }

  const numAttrs: Record<string, number> = {};
  const numRegex = /:([a-zA-Z0-9_-]+)\s+([0-9]+)/g;
  while ((match = numRegex.exec(source)) !== null) {
    numAttrs[match[1]] = Number(match[2]);
  }

  const listAttrs: Record<string, string[]> = {};
  const listRegex = /:([a-zA-Z0-9_-]+)\s+\[(.*?)\]/g;
  while ((match = listRegex.exec(source)) !== null) {
    listAttrs[match[1]] = [...match[2].matchAll(/"((?:[^"\\\\]|\\.)*)"/g)].map(m => unescapeStr(m[1]));
  }

  return { strAttrs, numAttrs, listAttrs };
}

/**
 * Decodes ASL Native S-Expression into LoomFrame (`asl/v1`)
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

  const { strAttrs, numAttrs } = parseSExprAttrs(headerPart);
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
 * Encodes a LoomFrame into ASL Coordination & Handoff Dialect (`asl/coord`)
 */
export function encodeAslCoord(frame: LoomFrame): string {
  const h = frame.header;
  if (frame.type === 'HANDOFF') {
    const payload = (frame.body || {}) as HandoffPayload;
    const taskPart = payload.task ? ` :task "${escapeStr(payload.task)}"` : '';
    const cwdPart = payload.cwd ? ` :cwd "${escapeStr(payload.cwd)}"` : '';
    const ownsPart = payload.owns && payload.owns.length ? ` :owns [${payload.owns.map(o => `"${escapeStr(o)}"`).join(' ')}]` : '';
    const frozenPart = payload.frozen && payload.frozen.length ? ` :frozen [${payload.frozen.map(f => `"${escapeStr(f)}"`).join(' ')}]` : '';
    const gatePart = payload.gate ? ` :gate "${escapeStr(payload.gate)}"` : '';
    const budgetPart = payload.budget ? ` :budget ${payload.budget}` : '';
    const replyPart = h.replyTo ? ` :reply-to "${escapeStr(h.replyTo)}"` : '';

    return `(loom:handoff :v ${h.version} :id "${escapeStr(h.id)}" :from "${escapeStr(h.from)}" :to "${escapeStr(h.to)}" :ts ${h.timestamp}${replyPart}${taskPart}${cwdPart}${ownsPart}${frozenPart}${gatePart}${budgetPart})`;
  }

  if (frame.type === 'YIELD') {
    const payload = (frame.body || {}) as YieldPayload;
    const statusPart = payload.status ? ` :status "${escapeStr(payload.status)}"` : ' :status "ok"';
    const verdictPart = payload.gateVerdict ? ` :verdict "${escapeStr(payload.gateVerdict)}"` : '';
    const artifactsPart = payload.artifacts && payload.artifacts.length ? ` :artifacts [${payload.artifacts.map(a => `"${escapeStr(a)}"`).join(' ')}]` : '';
    const errPart = payload.error ? ` :error "${escapeStr(payload.error)}"` : '';
    const replyPart = h.replyTo ? ` :reply-to "${escapeStr(h.replyTo)}"` : '';

    return `(loom:yield :v ${h.version} :id "${escapeStr(h.id)}"${replyPart} :from "${escapeStr(h.from)}" :to "${escapeStr(h.to)}" :ts ${h.timestamp}${statusPart}${verdictPart}${artifactsPart}${errPart})`;
  }

  // Fallback for general frames in asl/coord
  const bodyJson = JSON.stringify(frame.body);
  const replyPart = h.replyTo ? ` :reply-to "${escapeStr(h.replyTo)}"` : '';
  const chanPart = frame.channel ? ` :channel "${escapeStr(frame.channel)}"` : '';
  return `(loom:coord :v ${h.version} :id "${escapeStr(h.id)}" :from "${escapeStr(h.from)}" :to "${escapeStr(h.to)}" :type "${frame.type}" :ts ${h.timestamp}${replyPart}${chanPart} :body ${bodyJson})`;
}

/**
 * Decodes ASL Coordination & Handoff S-expressions (`asl/coord`)
 */
export function decodeAslCoord(raw: string): LoomFrame {
  const trimmed = raw.trim();
  const isHandoff = trimmed.startsWith('(loom:handoff');
  const isYield = trimmed.startsWith('(loom:yield');
  const isCoord = trimmed.startsWith('(loom:coord');

  if (!isHandoff && !isYield && !isCoord) {
    throw new CodecError(ErrorCode.ERR_DECODE_FAILED, 'Invalid ASL Coordination frame delimiter');
  }

  const { strAttrs, numAttrs, listAttrs } = parseSExprAttrs(trimmed);

  const version = numAttrs['v'] ?? 1;
  const id = strAttrs['id'];
  const from = strAttrs['from'];
  const to = strAttrs['to'];
  const timestamp = numAttrs['ts'] ?? Date.now();
  const replyTo = strAttrs['reply-to'];

  if (!id || !from || !to) {
    throw new CodecError(ErrorCode.ERR_DECODE_FAILED, 'Missing required fields in ASL coord frame');
  }

  if (isHandoff) {
    const handoffPayload: HandoffPayload = {
      task: strAttrs['task'] || '',
      cwd: strAttrs['cwd'],
      owns: listAttrs['owns'],
      frozen: listAttrs['frozen'],
      gate: strAttrs['gate'],
      budget: numAttrs['budget'],
    };

    return validateFrame({
      header: {
        version,
        id,
        from,
        to,
        dialect: 'asl/coord',
        timestamp,
        replyTo,
      },
      type: 'HANDOFF',
      body: handoffPayload,
    });
  }

  if (isYield) {
    const yieldPayload: YieldPayload = {
      status: (strAttrs['status'] || 'ok') as 'ok' | 'failed' | 'rejected',
      gateVerdict: strAttrs['verdict'],
      artifacts: listAttrs['artifacts'],
      error: strAttrs['error'],
    };

    return validateFrame({
      header: {
        version,
        id,
        from,
        to,
        dialect: 'asl/coord',
        timestamp,
        replyTo,
      },
      type: 'YIELD',
      body: yieldPayload,
    });
  }

  // General coord frame
  const type = (strAttrs['type'] || 'DATA') as FrameType;
  const bodyMarker = ':body ';
  const bodyIdx = trimmed.indexOf(bodyMarker);
  let body: unknown = null;
  if (bodyIdx !== -1) {
    const rawBodyPart = trimmed.slice(bodyIdx + bodyMarker.length, trimmed.length - 1).trim();
    try {
      body = JSON.parse(rawBodyPart);
    } catch {
      body = rawBodyPart;
    }
  }

  return validateFrame({
    header: {
      version,
      id,
      from,
      to,
      dialect: 'asl/coord',
      timestamp,
      replyTo,
    },
    type,
    channel: strAttrs['channel'],
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
  if (trimmed.startsWith('(loom:handoff') || trimmed.startsWith('(loom:yield') || trimmed.startsWith('(loom:coord') || trimmed.includes(':dialect "asl/coord"')) {
    return 'asl/coord';
  }
  if (trimmed.startsWith('(loom:frame')) {
    return 'asl/v1';
  }
  if (trimmed.startsWith('SK1|')) {
    return 'compact/v1';
  }
  return 'polyglot/v1';
}

/**
 * Checks if dialect is a dense nano-format.
 */
export function isNanoFormat(dialect: Dialect): boolean {
  return dialect === 'compact/v1' || dialect === 'asl/coord';
}

/**
 * Universal Frame Encoder
 * Strictly enforces nano-format (`compact/v1` or `asl/coord`) as the default wire dialect.
 * Verbose S-expr (`asl/v1`) is retained for explicit diagnostics or introspection.
 */
export function encodeFrame(frame: LoomFrame, targetDialect?: Dialect): string {
  const defaultDialect: Dialect = (frame.type === 'HANDOFF' || frame.type === 'YIELD') ? 'asl/coord' : 'compact/v1';
  const dialect = targetDialect || frame.header.dialect || defaultDialect;
  switch (dialect) {
    case 'asl/coord':
      return encodeAslCoord({ ...frame, header: { ...frame.header, dialect: 'asl/coord' } });
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
    case 'asl/coord':
      return decodeAslCoord(raw);
    case 'asl/v1':
      return decodeAslSExpr(raw);
    case 'compact/v1':
      return decodeCompact(raw);
    case 'polyglot/v1':
      return decodePolyglot(raw);
  }
}

/**
 * Bidirectional Transcoder: Converts any wire frame into target dialect
 * (e.g. nano-token <-> verbose S-expr).
 */
export function transcodeFrame(raw: string, targetDialect: Dialect): string {
  const frame = decodeFrame(raw);
  return encodeFrame(frame, targetDialect);
}
