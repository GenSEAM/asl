/**
 * SkyLoom Codec & Frame Validation Test Suite
 */

import assert from 'assert';
import {
  LoomFrame,
  encodeAslSExpr,
  decodeAslSExpr,
  encodeCompact,
  decodeCompact,
  encodePolyglot,
  decodePolyglot,
  encodeFrame,
  decodeFrame,
  detectDialect,
  CodecError,
  ErrorCode,
} from '../src/index.js';

console.log('--- Running SkyLoom Codec Test Suite ---');

const sampleFrame: LoomFrame = {
  header: {
    version: 1,
    id: 'msg-abc-123',
    from: 'agent-orchestrator',
    to: 'agent-worker',
    dialect: 'asl/v1',
    timestamp: 1725270000000,
    replyTo: 'msg-req-000',
  },
  type: 'DATA',
  channel: 'task/codegen',
  body: {
    action: 'compile_wasm',
    module: 'math/matrix',
    optimizationLevel: 'O3',
  },
};

// 1. ASL Native S-Expression Codec Test
console.log('Testing ASL Native S-Expression Codec...');
const aslEncoded = encodeAslSExpr(sampleFrame);
assert(aslEncoded.startsWith('(loom:frame'), 'Encoded ASL must start with (loom:frame');
assert(aslEncoded.includes(':channel "task/codegen"'), 'ASL frame must include channel');
console.log('Encoded ASL:\n', aslEncoded);

const aslDecoded = decodeAslSExpr(aslEncoded);
assert.strictEqual(aslDecoded.header.id, sampleFrame.header.id);
assert.strictEqual(aslDecoded.header.from, sampleFrame.header.from);
assert.strictEqual(aslDecoded.header.to, sampleFrame.header.to);
assert.strictEqual(aslDecoded.type, 'DATA');
assert.strictEqual(aslDecoded.channel, 'task/codegen');
assert.deepStrictEqual(aslDecoded.body, sampleFrame.body);
console.log('✓ ASL Native Codec round-trip OK');

// 2. Compact Positional Codec Test
console.log('Testing Compact Positional Codec...');
const compactEncoded = encodeCompact(sampleFrame);
assert(compactEncoded.startsWith('SK1|'), 'Compact frame must start with SK1|');
console.log('Encoded Compact:\n', compactEncoded);

const compactDecoded = decodeCompact(compactEncoded);
assert.strictEqual(compactDecoded.header.id, sampleFrame.header.id);
assert.strictEqual(compactDecoded.type, sampleFrame.type);
assert.strictEqual(compactDecoded.channel, sampleFrame.channel);
assert.deepStrictEqual(compactDecoded.body, sampleFrame.body);
console.log('✓ Compact Codec round-trip OK');

// 3. Polyglot Markdown/JSON Codec Test
console.log('Testing Polyglot Markdown/JSON Codec...');
const polyglotEncoded = encodePolyglot(sampleFrame);
assert(polyglotEncoded.includes('<!-- SKYLOOM_HEADER:'), 'Polyglot must include metadata header comment');
assert(polyglotEncoded.includes('```json'), 'Polyglot must include json fenced code block');
console.log('Encoded Polyglot:\n', polyglotEncoded);

const polyglotDecoded = decodePolyglot(polyglotEncoded);
assert.strictEqual(polyglotDecoded.header.id, sampleFrame.header.id);
assert.strictEqual(polyglotDecoded.header.from, sampleFrame.header.from);
assert.strictEqual(polyglotDecoded.type, 'DATA');
assert.deepStrictEqual(polyglotDecoded.body, sampleFrame.body);
console.log('✓ Polyglot Codec round-trip OK');

// 4. Universal Dialect Detection & Decoding
console.log('Testing Universal Dialect Detection & Decoding...');
assert.strictEqual(detectDialect(aslEncoded), 'asl/v1');
assert.strictEqual(detectDialect(compactEncoded), 'compact/v1');
assert.strictEqual(detectDialect(polyglotEncoded), 'polyglot/v1');

const decodedViaAutoAsl = decodeFrame(aslEncoded);
assert.strictEqual(decodedViaAutoAsl.header.id, sampleFrame.header.id);

const decodedViaAutoCompact = decodeFrame(compactEncoded);
assert.strictEqual(decodedViaAutoCompact.header.id, sampleFrame.header.id);

const decodedViaAutoPolyglot = decodeFrame(polyglotEncoded);
assert.strictEqual(decodedViaAutoPolyglot.header.id, sampleFrame.header.id);
console.log('✓ Universal Auto-detection OK');

// 5. Error & Edge Case Handling
console.log('Testing Malformed Input Handling...');
assert.throws(() => {
  decodeAslSExpr('invalid data');
}, (err: any) => err instanceof CodecError && err.code === ErrorCode.ERR_DECODE_FAILED);

assert.throws(() => {
  decodeCompact('BAD|1|2');
}, (err: any) => err instanceof CodecError && err.code === ErrorCode.ERR_DECODE_FAILED);

console.log('✓ Error handling OK');

console.log('--- ALL SKYLOOM CODEC TESTS PASSED SUCCESSFULLY ---');
