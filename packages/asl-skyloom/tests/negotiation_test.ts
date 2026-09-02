/**
 * SkyLoom Asymmetric Negotiation & Polyglot Adapter Acceptance Test
 * Proves bidirectional communication:
 * 1. Aware <-> Aware (Native ASL S-Expressions)
 * 2. Aware <-> Unaware (Polyglot instruction envelope & robust LLM output extraction)
 */

import assert from 'assert';
import {
  AsymmetricNegotiator,
  PeerCapability,
  LoomFrame,
} from '../src/index.js';

console.log('--- Running SkyLoom Asymmetric Negotiation Test Suite ---');

const awarePeer1: PeerCapability = {
  peerId: 'agent-orchestrator',
  dialects: ['asl/v1'],
  supportedChannels: ['control'],
  isAslNative: true,
  version: '1.0.0',
};

const awarePeer2: PeerCapability = {
  peerId: 'agent-architect',
  dialects: ['asl/v1'],
  supportedChannels: ['plans'],
  isAslNative: true,
  version: '1.0.0',
};

const unawarePeer: PeerCapability = {
  peerId: 'agent-vanilla-llm',
  dialects: ['polyglot/v1'],
  supportedChannels: [],
  isAslNative: false,
  version: '0.0.1',
};

// 1. Aware <-> Aware Negotiation
console.log('1. Testing Aware <-> Aware Negotiation...');
const sessionAware = AsymmetricNegotiator.negotiate(awarePeer1, awarePeer2);
assert.strictEqual(sessionAware.isAsymmetrical, false);
assert.strictEqual(sessionAware.activeDialect, 'asl/v1');
assert.strictEqual(sessionAware.requiresInstructionPrimer, false);

const taskFrame: LoomFrame = {
  header: {
    version: 1,
    id: 'msg-task-001',
    from: awarePeer1.peerId,
    to: awarePeer2.peerId,
    dialect: 'asl/v1',
    timestamp: Date.now(),
  },
  type: 'DATA',
  body: { action: 'design_architecture', tier: 'Tier 2' },
};

const wrappedForAware = AsymmetricNegotiator.wrapOutgoing(taskFrame, awarePeer2);
assert(wrappedForAware.startsWith('(loom:frame'), 'Must format as ASL S-expression for native peer');
console.log('✓ Aware <-> Aware native encoding verified');

// 2. Aware -> Unaware Negotiation & Outgoing Envelope
console.log('2. Testing Aware -> Unaware Asymmetric Negotiation...');
const sessionUnaware = AsymmetricNegotiator.negotiate(awarePeer1, unawarePeer);
assert.strictEqual(sessionUnaware.isAsymmetrical, true);
assert.strictEqual(sessionUnaware.activeDialect, 'polyglot/v1');
assert.strictEqual(sessionUnaware.requiresInstructionPrimer, true);

const wrappedForUnaware = AsymmetricNegotiator.wrapOutgoing(taskFrame, unawarePeer);
assert(wrappedForUnaware.includes('<!-- SKYLOOM_HEADER:'), 'Must include skyloom metadata');
assert(wrappedForUnaware.includes('[SkyLoom Autonomous Protocol Primer]'), 'Must include instruction primer');
assert(wrappedForUnaware.includes('```json'), 'Must include JSON code fence');
console.log('✓ Polyglot envelope with primer verified:\n', wrappedForUnaware.slice(0, 200) + '...\n');

// 3. Unaware LLM -> Aware Inbound Parsing (Conversational + JSON)
console.log('3. Testing Unaware LLM Chat Response Ingestion...');
const simulatedLlmResponse = `
I have reviewed your request for architecture design.
Everything looks solid. Here is my structured confirmation:

\`\`\`json
{
  "status": "COMPLETED",
  "blueprint": "3-tier-mesh",
  "confidence": 0.98,
  "replyTo": "msg-task-001"
}
\`\`\`

Let me know if you need additional refinement!
`;

const unwrappedFrame = AsymmetricNegotiator.unwrapIncoming(
  simulatedLlmResponse,
  unawarePeer.peerId,
  awarePeer1.peerId
);

assert.strictEqual(unwrappedFrame.header.from, 'agent-vanilla-llm');
assert.strictEqual(unwrappedFrame.header.to, 'agent-orchestrator');
assert.strictEqual(unwrappedFrame.header.replyTo, 'msg-task-001');
assert.strictEqual((unwrappedFrame.body as any).status, 'COMPLETED');
assert.strictEqual((unwrappedFrame.body as any).blueprint, '3-tier-mesh');
console.log('✓ Successfully extracted and normalized LLM conversational response into typed LoomFrame');

// 4. Free-form Plaintext Fallback
console.log('4. Testing Raw Plaintext LLM Fallback...');
const rawEnglishResponse = 'I cannot fulfill this request due to missing credentials.';
const fallbackFrame = AsymmetricNegotiator.unwrapIncoming(rawEnglishResponse, unawarePeer.peerId, awarePeer1.peerId);
assert.strictEqual((fallbackFrame.body as any).naturalLanguage, rawEnglishResponse);
console.log('✓ Raw text fallback safely captured in LoomFrame body');

console.log('--- ALL SKYLOOM ASYMMETRIC NEGOTIATION TESTS PASSED SUCCESSFULLY ---');
