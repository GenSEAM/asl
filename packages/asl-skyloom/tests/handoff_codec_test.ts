/**
 * SkyLoom Phase 1 Acceptance Test:
 * Coordination Dialect (`asl/coord`) & Algebraic Handoff Types
 */

import assert from 'node:assert';
import {
  encodeFrame,
  decodeFrame,
  detectDialect,
  encodeAslCoord,
  decodeAslCoord,
} from '../src/codec.js';
import { LoomFrame, HandoffPayload, YieldPayload } from '../src/types.js';

console.log('--- Running SkyLoom Handoff & Coordination Codec Tests ---');

// 1. Test loom:handoff encoding & decoding
console.log('1. Testing (loom:handoff ...) encoding & roundtrip...');
const handoffFrame: LoomFrame = {
  header: {
    version: 1,
    id: 'handoff-req-001',
    from: 'agent-orchestrator',
    to: 'agent-coder',
    dialect: 'asl/coord',
    timestamp: 1725280000000,
  },
  type: 'HANDOFF',
  body: {
    task: 'implement_token_bucket_limiter',
    cwd: 'packages/asl-rate',
    owns: ['src/limiter.asl', 'tests/limiter_test.asl'],
    frozen: ['src/core.asl'],
    gate: 'asl check src/limiter.asl && asl test tests/',
    budget: 5000,
  } as HandoffPayload,
};

const encodedHandoff = encodeFrame(handoffFrame);
console.log('Encoded (loom:handoff):');
console.log(' ', encodedHandoff);

assert(encodedHandoff.startsWith('(loom:handoff'), 'Must start with (loom:handoff');
assert(encodedHandoff.includes(':task "implement_token_bucket_limiter"'));
assert(encodedHandoff.includes(':cwd "packages/asl-rate"'));
assert(encodedHandoff.includes(':owns ["src/limiter.asl" "tests/limiter_test.asl"]'));
assert(encodedHandoff.includes(':frozen ["src/core.asl"]'));
assert(encodedHandoff.includes(':gate "asl check src/limiter.asl && asl test tests/"'));
assert(encodedHandoff.includes(':budget 5000'));

const detectedDialect1 = detectDialect(encodedHandoff);
assert.strictEqual(detectedDialect1, 'asl/coord');

const decodedHandoff = decodeFrame(encodedHandoff);
assert.strictEqual(decodedHandoff.header.id, 'handoff-req-001');
assert.strictEqual(decodedHandoff.header.from, 'agent-orchestrator');
assert.strictEqual(decodedHandoff.header.to, 'agent-coder');
assert.strictEqual(decodedHandoff.type, 'HANDOFF');
assert.strictEqual(decodedHandoff.header.dialect, 'asl/coord');

const bodyHandoff = decodedHandoff.body as HandoffPayload;
assert.strictEqual(bodyHandoff.task, 'implement_token_bucket_limiter');
assert.strictEqual(bodyHandoff.cwd, 'packages/asl-rate');
assert.deepStrictEqual(bodyHandoff.owns, ['src/limiter.asl', 'tests/limiter_test.asl']);
assert.deepStrictEqual(bodyHandoff.frozen, ['src/core.asl']);
assert.strictEqual(bodyHandoff.gate, 'asl check src/limiter.asl && asl test tests/');
assert.strictEqual(bodyHandoff.budget, 5000);
console.log('✓ (loom:handoff ...) roundtrip verified cleanly');

// 2. Test loom:yield encoding & decoding
console.log('\n2. Testing (loom:yield ...) encoding & roundtrip...');
const yieldFrame: LoomFrame = {
  header: {
    version: 1,
    id: 'yield-resp-001',
    replyTo: 'handoff-req-001',
    from: 'agent-coder',
    to: 'agent-orchestrator',
    dialect: 'asl/coord',
    timestamp: 1725280005000,
  },
  type: 'YIELD',
  body: {
    status: 'ok',
    gateVerdict: 'PASS (0 diagnostics, 8 tests passed)',
    artifacts: ['src/limiter.asl', 'dist/limiter.wasm'],
  } as YieldPayload,
};

const encodedYield = encodeFrame(yieldFrame);
console.log('Encoded (loom:yield):');
console.log(' ', encodedYield);

assert(encodedYield.startsWith('(loom:yield'));
assert(encodedYield.includes(':reply-to "handoff-req-001"'));
assert(encodedYield.includes(':status "ok"'));
assert(encodedYield.includes(':verdict "PASS (0 diagnostics, 8 tests passed)"'));
assert(encodedYield.includes(':artifacts ["src/limiter.asl" "dist/limiter.wasm"]'));

const decodedYield = decodeFrame(encodedYield);
assert.strictEqual(decodedYield.header.id, 'yield-resp-001');
assert.strictEqual(decodedYield.header.replyTo, 'handoff-req-001');
assert.strictEqual(decodedYield.type, 'YIELD');
assert.strictEqual(decodedYield.header.dialect, 'asl/coord');

const bodyYield = decodedYield.body as YieldPayload;
assert.strictEqual(bodyYield.status, 'ok');
assert.strictEqual(bodyYield.gateVerdict, 'PASS (0 diagnostics, 8 tests passed)');
assert.deepStrictEqual(bodyYield.artifacts, ['src/limiter.asl', 'dist/limiter.wasm']);
console.log('✓ (loom:yield ...) roundtrip verified cleanly');

// 3. Test token density comparison: English vs asl/coord
console.log('\n3. Testing Token Density / Size Comparison...');
const englishCoordination = `Hello agent-coder. Please take over and implement the token bucket limiter in directory packages/asl-rate. You own src/limiter.asl and tests/limiter_test.asl. Do not touch src/core.asl as it is frozen. When finished, ensure gate "asl check src/limiter.asl && asl test tests/" passes. Your maximum token budget is 5000 tokens.`;

console.log(`Natural English Char Length: ${englishCoordination.length}`);
console.log(`ASL Coord Char Length:      ${encodedHandoff.length}`);
const savingsPct = ((1 - encodedHandoff.length / englishCoordination.length) * 100).toFixed(1);
console.log(`Payload Size Reduction:     ${savingsPct}%`);
assert(encodedHandoff.length < englishCoordination.length, 'asl/coord must be significantly more compact than English');

console.log('\n--- ALL SKYLOOM HANDOFF CODEC TESTS PASSED CLEANLY ---');
