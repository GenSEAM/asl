/**
 * SkyLoom Context Snapshot Compressor & Handoff Serializer
 * Distills multi-turn conversational chat logs and session state into
 * minimal, typed AST coordination frames, eliminating 75-90% token bloat.
 */

import { LoomFrame, HandoffPayload } from './types.js';
import { encodeFrame } from './codec.js';

export interface SessionTurn {
  role: 'user' | 'assistant' | 'tool' | 'system';
  content: string;
  toolCalls?: Array<{ name: string; args?: unknown }>;
  timestamp?: number;
}

export interface FileChangeRecord {
  path: string;
  status: 'created' | 'modified' | 'deleted';
  summary?: string;
}

export interface HandoffSnapshot {
  sessionId: string;
  task: string;
  objective: string;
  cwd: string;
  owns: string[];
  frozen: string[];
  decisions: string[];
  modifiedFiles: FileChangeRecord[];
  verificationGate: string;
  budget?: number;
  metadata?: Record<string, unknown>;
}

export interface CompressionReport {
  rawCharLength: number;
  snapshotCharLength: number;
  rawTokenEst: number;
  snapshotTokenEst: number;
  savingsPct: number;
}

export class HandoffSerializer {
  /**
   * Distills a raw multi-turn session into a compact, actionable HandoffSnapshot
   */
  static compressSession(
    sessionId: string,
    task: string,
    turns: SessionTurn[],
    options: {
      cwd: string;
      owns: string[];
      frozen?: string[];
      verificationGate: string;
      budget?: number;
      decisions?: string[];
      modifiedFiles?: FileChangeRecord[];
    }
  ): HandoffSnapshot {
    const extractedDecisions: string[] = [...(options.decisions || [])];
    const modifiedMap: Map<string, FileChangeRecord> = new Map();

    if (options.modifiedFiles) {
      for (const f of options.modifiedFiles) {
        modifiedMap.set(f.path, f);
      }
    }

    // Heuristically extract key decisions and file operations from turns if not explicit
    for (const turn of turns) {
      const text = turn.content;
      
      // Match decision markers (e.g., "Decision:", "Decided:", "Resolved:")
      const decisionMatches = text.matchAll(/(?:Decision|Decided|Resolved|Rule):\s*([^\n\.]+)/gi);
      for (const m of decisionMatches) {
        const item = m[1].trim();
        if (item && !extractedDecisions.includes(item)) {
          extractedDecisions.push(item);
        }
      }

      // Match file operations in tool calls or text
      if (turn.toolCalls) {
        for (const tc of turn.toolCalls) {
          if (tc.name.includes('write') || tc.name.includes('create') || tc.name.includes('edit') || tc.name.includes('replace')) {
            const path = (tc.args as any)?.TargetFile || (tc.args as any)?.path || (tc.args as any)?.file;
            if (path && typeof path === 'string') {
              modifiedMap.set(path, {
                path,
                status: tc.name.includes('create') || tc.name.includes('write') ? 'created' : 'modified',
              });
            }
          }
        }
      }
    }

    return {
      sessionId,
      task,
      objective: `Execute "${task}" in "${options.cwd}" satisfying gate "${options.verificationGate}"`,
      cwd: options.cwd,
      owns: options.owns,
      frozen: options.frozen || [],
      decisions: extractedDecisions.slice(0, 5), // Keep top 5 architectural decisions
      modifiedFiles: Array.from(modifiedMap.values()),
      verificationGate: options.verificationGate,
      budget: options.budget,
    };
  }

  /**
   * Converts a HandoffSnapshot into a typed LoomFrame under the 'asl/coord' dialect
   */
  static toCoordFrame(snapshot: HandoffSnapshot, from: string, to: string): LoomFrame {
    const payload: HandoffPayload = {
      task: snapshot.task,
      cwd: snapshot.cwd,
      owns: snapshot.owns,
      frozen: snapshot.frozen,
      gate: snapshot.verificationGate,
      budget: snapshot.budget,
      metadata: {
        sessionId: snapshot.sessionId,
        decisions: snapshot.decisions,
        modifiedFiles: snapshot.modifiedFiles.map(f => f.path),
      },
    };

    return {
      header: {
        version: 1,
        id: `handoff-${snapshot.sessionId}-${Date.now()}`,
        from,
        to,
        dialect: 'asl/coord',
        timestamp: Date.now(),
      },
      type: 'HANDOFF',
      body: payload,
    };
  }

  /**
   * Measures token and character savings between raw conversational history and compressed snapshot frame
   */
  static measureSavings(turns: SessionTurn[], frame: LoomFrame): CompressionReport {
    const rawText = turns.map(t => `${t.role.toUpperCase()}: ${t.content}`).join('\n\n');
    const rawCharLength = rawText.length;
    const rawTokenEst = Math.ceil(rawCharLength / 3.8); // ~3.8 chars per token for code/text mix

    const encodedFrame = encodeFrame(frame, 'asl/coord');
    const snapshotCharLength = encodedFrame.length;
    const snapshotTokenEst = Math.ceil(snapshotCharLength / 3.8);

    const savingsPct = rawCharLength > 0 
      ? Number(((1 - snapshotCharLength / rawCharLength) * 100).toFixed(1))
      : 0;

    return {
      rawCharLength,
      snapshotCharLength,
      rawTokenEst,
      snapshotTokenEst,
      savingsPct,
    };
  }
}
