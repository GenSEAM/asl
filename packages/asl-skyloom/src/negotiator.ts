/**
 * SkyLoom Asymmetric Negotiation Engine & Polyglot Adapter
 * Enables seamless communication between protocol-aware and unaware agents.
 */

import { LoomFrame, PeerCapability, Dialect, ErrorCode } from './types.js';
import { encodeAslSExpr, decodeAslSExpr, encodePolyglot, decodePolyglot, decodeFrame } from './codec.js';

export interface NegotiatedSession {
  senderId: string;
  receiverId: string;
  isAsymmetrical: boolean;
  activeDialect: Dialect;
  requiresInstructionPrimer: boolean;
}

export class AsymmetricNegotiator {
  /**
   * Evaluates capabilities between two peers and determines the optimal wire dialect
   */
  static negotiate(sender: PeerCapability, receiver: PeerCapability): NegotiatedSession {
    const isAsymmetrical = sender.isAslNative !== receiver.isAslNative;

    // Both aware: Native ASL
    if (sender.isAslNative && receiver.isAslNative) {
      return {
        senderId: sender.peerId,
        receiverId: receiver.peerId,
        isAsymmetrical: false,
        activeDialect: 'asl/v1',
        requiresInstructionPrimer: false,
      };
    }

    // Both compact
    if (sender.dialects.includes('compact/v1') && receiver.dialects.includes('compact/v1')) {
      return {
        senderId: sender.peerId,
        receiverId: receiver.peerId,
        isAsymmetrical: false,
        activeDialect: 'compact/v1',
        requiresInstructionPrimer: false,
      };
    }

    // Unaware counterparty: Polyglot dialect with instructional envelope
    return {
      senderId: sender.peerId,
      receiverId: receiver.peerId,
      isAsymmetrical: true,
      activeDialect: 'polyglot/v1',
      requiresInstructionPrimer: !receiver.isAslNative,
    };
  }

  /**
   * Generates instruction primer markdown for unaware agents
   */
  static generateSkillPrimer(senderId: string): string {
    return `[SkyLoom Autonomous Protocol Primer]
You are communicating with agent "${senderId}" over SkyLoom.
To reply, you must format your response with:
1. An acknowledgement or natural thought summary.
2. A fenced code block (\`\`\`json ... \`\`\`) with your structured response:
{
  "status": "COMPLETED" | "NEED_INFO" | "ERROR",
  "result": <your answer or output>,
  "replyTo": "<original_message_id>"
}`;
  }

  /**
   * Wraps an outgoing frame for target agent
   */
  static wrapOutgoing(frame: LoomFrame, targetCap: PeerCapability): string {
    if (targetCap.isAslNative && targetCap.dialects.includes('asl/v1')) {
      return encodeAslSExpr(frame);
    }

    if (targetCap.dialects.includes('compact/v1')) {
      return encodePolyglot(frame);
    }

    // Target is unaware or polyglot: enrich envelope with primer
    const primer = AsymmetricNegotiator.generateSkillPrimer(frame.header.from);
    const meta = {
      v: frame.header.version,
      id: frame.header.id,
      from: frame.header.from,
      to: frame.header.to,
      dialect: 'polyglot/v1',
      type: frame.type,
      channel: frame.channel,
      timestamp: frame.header.timestamp,
      replyTo: frame.header.replyTo,
    };

    const bodyJson = JSON.stringify(frame.body, null, 2);

    return `<!-- SKYLOOM_HEADER: ${JSON.stringify(meta)} -->
${primer}

--- Message from ${frame.header.from} ---
Type: ${frame.type}${frame.channel ? ` | Topic: ${frame.channel}` : ''}
ID: ${frame.header.id}

\`\`\`json
${bodyJson}
\`\`\`
<!-- SKYLOOM_FOOTER -->`;
  }

  /**
   * Unwraps incoming raw response from any agent into a valid LoomFrame
   */
  static unwrapIncoming(raw: string, fromOverride?: string, toOverride?: string): LoomFrame {
    const trimmed = raw.trim();

    // 1. Check if native ASL
    if (trimmed.startsWith('(loom:frame')) {
      return decodeAslSExpr(trimmed);
    }

    // 2. Check if polyglot comment header exists
    if (trimmed.includes('<!-- SKYLOOM_HEADER:')) {
      return decodePolyglot(trimmed);
    }

    // 3. Fallback: Parse unaware agent response (e.g. LLM natural chat with embedded json)
    const jsonMatch = trimmed.match(/```json\s*([\s\S]*?)\s*```/);
    let parsedBody: any = null;
    if (jsonMatch) {
      try {
        parsedBody = JSON.parse(jsonMatch[1]);
      } catch {
        parsedBody = { rawText: trimmed };
      }
    } else {
      try {
        parsedBody = JSON.parse(trimmed);
      } catch {
        parsedBody = { naturalLanguage: trimmed };
      }
    }

    const replyTo = parsedBody?.replyTo || undefined;
    const msgId = `unaware-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;

    return {
      header: {
        version: 1,
        id: msgId,
        from: fromOverride || 'unaware-agent',
        to: toOverride || 'agent-orchestrator',
        dialect: 'polyglot/v1',
        timestamp: Date.now(),
        replyTo,
      },
      type: 'DATA',
      body: parsedBody,
    };
  }
}
