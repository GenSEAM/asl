/**
 * Test Suite: Nano-Format Default Wire Enforcement & Transcoding
 */

import {
  encodeFrame,
  decodeFrame,
  transcodeFrame,
  isNanoFormat,
  LoomFrame,
} from '../src/index.js';

function assert(cond: boolean, msg: string) {
  if (!cond) {
    throw new Error(`Assertion failed: ${msg}`);
  }
}

console.log('--- Running SkyLoom Nano-Format Enforcement & Transcoder Tests ---');

// 1. Default Encoding must be Nano Format
console.log('1. Testing default encodeFrame() output format...');
const sampleFrame: LoomFrame = {
  header: {
    version: 1,
    id: 'msg-nano-001',
    from: 'agent-orchestrator',
    to: 'agent-coder',
    timestamp: 1788350000000,
  },
  type: 'DATA',
  channel: 'tasks/code',
  body: { action: 'build_binary', target: 'wasm' },
};

const defaultEncoded = encodeFrame(sampleFrame);
console.log('Default Encoded Output:\n ', defaultEncoded);

assert(
  defaultEncoded.startsWith('SK1|'),
  'Default encoded frame must start with compact token prefix SK1|'
);
assert(
  !defaultEncoded.startsWith('(loom:frame'),
  'Default wire frame must NOT use verbose S-expression'
);
console.log('✓ Default frame encoding is strictly Nano Positional Token format (SK1)');

// 2. Default Handoff Frame must be asl/coord Nano AST
console.log('\n2. Testing default handoff frame encoding...');
const handoffFrame: LoomFrame = {
  header: {
    version: 1,
    id: 'handoff-nano-001',
    from: 'agent-orchestrator',
    to: 'agent-coder',
    timestamp: 1788350000000,
  },
  type: 'HANDOFF',
  body: {
    task: 'implement_feature',
    cwd: 'packages/core',
    owns: ['src/feature.asl'],
    gate: 'asl check',
    budget: 3000,
  },
};

const defaultHandoffEncoded = encodeFrame(handoffFrame);
console.log('Default Handoff Encoded:\n ', defaultHandoffEncoded);
assert(
  defaultHandoffEncoded.startsWith('(loom:handoff'),
  'Handoff frames must default to dense (loom:handoff ...) coord AST'
);
console.log('✓ Default handoff frame correctly uses asl/coord nano AST');

// 3. Verbose format generated ONLY when explicitly requested
console.log('\n3. Testing explicit verbose diagnostic format request...');
const explicitVerbose = encodeFrame(sampleFrame, 'asl/v1');
console.log('Explicit Verbose Output:\n ', explicitVerbose);
assert(
  explicitVerbose.startsWith('(loom:frame'),
  'Explicit asl/v1 must yield verbose self-describing S-expression'
);
console.log('✓ Verbose format properly retained for diagnostic introspection');

// 4. Bidirectional Transcoding: Verbose -> Nano
console.log('\n4. Testing Bidirectional Transcoding (Verbose -> Nano)...');
const transcodedToNano = transcodeFrame(explicitVerbose, 'compact/v1');
console.log('Transcoded to Nano:\n ', transcodedToNano);
assert(
  transcodedToNano.startsWith('SK1|'),
  'Transcoding verbose frame to compact/v1 must yield SK1|'
);

const decodedFromNano = decodeFrame(transcodedToNano);
assert(decodedFromNano.header.id === sampleFrame.header.id, 'Frame ID preserved across transcode');
assert(
  (decodedFromNano.body as any).action === 'build_binary',
  'Payload body preserved across transcode'
);
console.log('✓ Verbose -> Nano transcoding roundtrip verified cleanly');

// 5. Bidirectional Transcoding: Nano -> Verbose
console.log('\n5. Testing Bidirectional Transcoding (Nano -> Verbose)...');
const transcodedToVerbose = transcodeFrame(defaultEncoded, 'asl/v1');
console.log('Transcoded to Verbose:\n ', transcodedToVerbose);
assert(
  transcodedToVerbose.startsWith('(loom:frame'),
  'Transcoding nano frame to asl/v1 must yield (loom:frame ...)'
);

const decodedFromVerbose = decodeFrame(transcodedToVerbose);
assert(
  decodedFromVerbose.header.id === sampleFrame.header.id,
  'Frame ID preserved in verbose transcode'
);
console.log('✓ Nano -> Verbose transcoding roundtrip verified cleanly');

// 6. Nano format predicate check
assert(isNanoFormat('compact/v1') === true, 'compact/v1 is nano');
assert(isNanoFormat('asl/coord') === true, 'asl/coord is nano');
assert(isNanoFormat('asl/v1') === false, 'asl/v1 is not nano');
assert(isNanoFormat('polyglot/v1') === false, 'polyglot/v1 is not nano');
console.log('✓ isNanoFormat predicate verified');

console.log('\n--- ALL NANO ENFORCEMENT & TRANSCODER TESTS PASSED CLEANLY ---');
