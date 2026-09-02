/**
 * SkyLoom Phase 3 Acceptance Test:
 * Context Snapshot Compression & Handoff Serializer
 */

import assert from 'node:assert';
import { HandoffSerializer, SessionTurn } from '../src/handoff.js';
import { encodeFrame, decodeFrame } from '../src/codec.js';
import { HandoffPayload } from '../src/types.js';

console.log('--- Running SkyLoom Context Snapshot & Handoff Compression Tests ---');

// 1. Simulate a realistic 12-turn verbose LLM chat session with conversational overhead
const simulatedTurns: SessionTurn[] = [
  { role: 'user', content: 'We need to implement the secure token bucket rate limiter in packages/asl-rate.' },
  { role: 'assistant', content: 'Understood! I will analyze the codebase and see how to structure the rate limiter.' },
  { role: 'assistant', content: 'Let me look at packages/asl-rate/src/core.asl to see what existing primitives we have. Decision: We must not mutate core.asl directly.' },
  { role: 'assistant', content: 'I tried drafting a naive sliding window in Python, but that would violate the ASL Wasm target. Decision: All rate limiting logic must compile to wasm32-wasip1 without external C bindings.' },
  { role: 'user', content: 'Good point. Make sure tests are placed in tests/limiter_test.asl.' },
  { role: 'assistant', content: 'Sure! I will create src/limiter.asl and tests/limiter_test.asl now.', toolCalls: [{ name: 'write_file', args: { TargetFile: 'src/limiter.asl' } }] },
  { role: 'tool', content: 'File written successfully: src/limiter.asl (1024 bytes)' },
  { role: 'assistant', content: 'Now creating tests/limiter_test.asl.', toolCalls: [{ name: 'write_file', args: { TargetFile: 'tests/limiter_test.asl' } }] },
  { role: 'tool', content: 'File written successfully: tests/limiter_test.asl (512 bytes)' },
  { role: 'assistant', content: 'I ran the initial test and encountered an arithmetic overflow on negative timestamp. Apologies for the confusion! Let me patch the integer bounds check.' },
  { role: 'assistant', content: 'Fixed the bounds check. Decision: Use Int64 for millisecond epoch values to prevent 32-bit trap.' },
  { role: 'user', content: 'Excellent. Now hand off to the QA agent to run full verification.' },
];

console.log(`1. Raw Chat History: ${simulatedTurns.length} turns, ${simulatedTurns.map(t => t.content).join(' ').length} chars`);

// 2. Compress session into HandoffSnapshot
console.log('\n2. Compressing session into minimal HandoffSnapshot...');
const snapshot = HandoffSerializer.compressSession('session-xyz-789', 'verify_and_benchmark_limiter', simulatedTurns, {
  cwd: 'packages/asl-rate',
  owns: ['src/limiter.asl', 'tests/limiter_test.asl'],
  frozen: ['src/core.asl'],
  verificationGate: 'asl check src/limiter.asl && asl test tests/',
  budget: 4500,
});

assert.strictEqual(snapshot.sessionId, 'session-xyz-789');
assert.strictEqual(snapshot.task, 'verify_and_benchmark_limiter');
assert.strictEqual(snapshot.cwd, 'packages/asl-rate');
assert.deepStrictEqual(snapshot.owns, ['src/limiter.asl', 'tests/limiter_test.asl']);
assert.deepStrictEqual(snapshot.frozen, ['src/core.asl']);
assert.strictEqual(snapshot.verificationGate, 'asl check src/limiter.asl && asl test tests/');
assert.strictEqual(snapshot.budget, 4500);

// Verify extracted architectural decisions
assert(snapshot.decisions.length >= 2, 'Must automatically extract key architectural decisions');
console.log('Extracted Architectural Decisions:');
snapshot.decisions.forEach(d => console.log(` • ${d}`));

// 3. Convert to typed AST frame
console.log('\n3. Converting snapshot to (loom:handoff ...) frame...');
const coordFrame = HandoffSerializer.toCoordFrame(snapshot, 'agent-coder', 'agent-qa');
assert.strictEqual(coordFrame.type, 'HANDOFF');
assert.strictEqual(coordFrame.header.dialect, 'asl/coord');

const encodedWire = encodeFrame(coordFrame);
console.log('Encoded Wire S-Expression:');
console.log(' ', encodedWire);

// 4. Measure Token and Character Savings
const report = HandoffSerializer.measureSavings(simulatedTurns, coordFrame);
console.log('\n4. Token Compression Scoreboard:');
console.log(` Raw Chat History:      ${report.rawCharLength} chars (~${report.rawTokenEst} tokens)`);
console.log(` Distilled ASL Handoff: ${report.snapshotCharLength} chars (~${report.snapshotTokenEst} tokens)`);
console.log(` Context Window Savings: ${report.savingsPct}%`);

assert(report.savingsPct >= 70.0, `Savings must be >= 70% (actual: ${report.savingsPct}%)`);
console.log(`✓ Verified massive context compression: eliminated ${report.savingsPct}% of token overhead!`);

// 5. Roundtrip validation
console.log('\n5. Verifying roundtrip decoding through universal wire parser...');
const decoded = decodeFrame(encodedWire);
assert.strictEqual(decoded.type, 'HANDOFF');
const payload = decoded.body as HandoffPayload;
assert.strictEqual(payload.task, 'verify_and_benchmark_limiter');
assert.strictEqual(payload.cwd, 'packages/asl-rate');
assert.deepStrictEqual(payload.owns, ['src/limiter.asl', 'tests/limiter_test.asl']);
assert.strictEqual(payload.gate, 'asl check src/limiter.asl && asl test tests/');
assert.strictEqual(payload.budget, 4500);
console.log('✓ Decoded frame matches handoff contract with 100% fidelity');

console.log('\n--- ALL SKYLOOM SNAPSHOT COMPRESSION TESTS PASSED CLEANLY ---');
