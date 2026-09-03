/**
 * Every wire frame printed in docs/AGENTIC_PROTOCOL.md and skills/skyloom/SKILL.md
 * must decode with the codec those documents describe. A spec example the reference
 * implementation cannot read is the defect this test exists to catch.
 */

import * as assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { decodeFrame, detectDialect, encodeFrame } from '../src/codec.js';
import { Dialect } from '../src/types.js';

// Walk up to the repository root: this file runs from tests/ in source and dist/tests/ when built.
function findRoot(start: string): string {
  let dir = start;
  for (;;) {
    if (fs.existsSync(path.join(dir, 'docs', 'AGENTIC_PROTOCOL.md'))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) throw new Error(`no repository root above ${start}`);
    dir = parent;
  }
}

const ROOT = findRoot(path.dirname(fileURLToPath(import.meta.url)));

const SOURCES = [
  path.join(ROOT, 'docs', 'AGENTIC_PROTOCOL.md'),
  path.join(ROOT, 'skills', 'skyloom', 'SKILL.md'),
];

/** Pulls each balanced `(loom:...)` form out of a document, ignoring parens inside strings. */
function extractSExprFrames(text: string): string[] {
  const frames: string[] = [];
  const marker = /\(loom:[a-z]+/g;
  let m: RegExpExecArray | null;
  while ((m = marker.exec(text)) !== null) {
    let depth = 0;
    let inString = false;
    for (let i = m.index; i < text.length; i++) {
      const ch = text[i];
      if (inString) {
        if (ch === '\\') i++;
        else if (ch === '"') inString = false;
        continue;
      }
      if (ch === '"') inString = true;
      else if (ch === '(') depth++;
      else if (ch === ')') {
        depth--;
        if (depth === 0) {
          frames.push(text.slice(m.index, i + 1));
          marker.lastIndex = i + 1;
          break;
        }
      }
    }
  }
  return frames;
}

function extractCompactFrames(text: string): string[] {
  return text.split('\n').filter(line => line.startsWith('SK1|'));
}

function extractPolyglotFrames(text: string): string[] {
  const frames: string[] = [];
  const re = /<!-- SKYLOOM_HEADER:[\s\S]*?<!-- SKYLOOM_FOOTER[^>]*-->/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) frames.push(m[0]);
  return frames;
}

console.log('=== SkyLoom Specification Example Conformance ===\n');

let checked = 0;
const seenDialects = new Set<Dialect>();

for (const source of SOURCES) {
  const text = fs.readFileSync(source, 'utf8');
  const rel = path.relative(ROOT, source);
  const frames = [
    ...extractSExprFrames(text),
    ...extractCompactFrames(text),
    ...extractPolyglotFrames(text),
  ];

  assert.ok(frames.length > 0, `${rel} prints no wire frames to check`);

  for (const raw of frames) {
    const dialect = detectDialect(raw);
    seenDialects.add(dialect);

    let frame;
    try {
      frame = decodeFrame(raw);
    } catch (err) {
      assert.fail(`${rel}: example does not decode as ${dialect}\n  ${raw}\n  ${err}`);
    }

    assert.ok(frame.header.id, `${rel}: decoded frame has no id\n  ${raw}`);
    assert.ok(frame.header.from, `${rel}: decoded frame has no sender\n  ${raw}`);
    assert.ok(frame.header.to, `${rel}: decoded frame has no recipient\n  ${raw}`);

    // Re-encoding must land on a frame that decodes to the same header and type.
    const reencoded = encodeFrame(frame, dialect);
    const again = decodeFrame(reencoded);
    assert.strictEqual(again.type, frame.type, `${rel}: type lost on re-encode\n  ${raw}`);
    assert.strictEqual(again.header.id, frame.header.id, `${rel}: id lost on re-encode\n  ${raw}`);

    checked++;
    console.log(`✓ ${rel} [${dialect}] ${frame.type} ${frame.header.id}`);
  }
}

assert.ok(checked >= 6, `expected the documents to print at least 6 frames, found ${checked}`);
for (const required of ['asl/v1', 'asl/coord', 'compact/v1', 'polyglot/v1'] as Dialect[]) {
  assert.ok(seenDialects.has(required), `no ${required} example is printed anywhere`);
}

console.log(`\n--- ${checked} SPECIFICATION EXAMPLES DECODE CLEANLY ---`);
