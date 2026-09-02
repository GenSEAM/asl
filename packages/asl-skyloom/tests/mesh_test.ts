/**
 * SkyLoom Multi-Agent Mesh Topology Acceptance Test
 * Proves 5-agent heterogeneous mesh, pub/sub channels, direct P2P, and dynamic join/leave.
 */

import assert from 'assert';
import {
  SkyLoomRouter,
  InMemoryAgentClient,
  PeerCapability,
} from '../src/index.js';

console.log('--- Running SkyLoom Multi-Agent Mesh Topology Test Suite ---');

const router = new SkyLoomRouter();

// Define 5 heterogeneous agent capabilities
const orchestratorCap: PeerCapability = {
  peerId: 'agent-orchestrator',
  dialects: ['asl/v1'],
  supportedChannels: ['control', 'status'],
  isAslNative: true,
  version: '1.0.0',
};

const plannerCap: PeerCapability = {
  peerId: 'agent-planner',
  dialects: ['asl/v1'],
  supportedChannels: ['plans'],
  isAslNative: true,
  version: '1.0.0',
};

const coder1Cap: PeerCapability = {
  peerId: 'agent-coder-1',
  dialects: ['compact/v1'],
  supportedChannels: [],
  isAslNative: false,
  version: '1.0.0',
};

const coder2Cap: PeerCapability = {
  peerId: 'agent-coder-2',
  dialects: ['compact/v1'],
  supportedChannels: [],
  isAslNative: false,
  version: '1.0.0',
};

const qaCap: PeerCapability = {
  peerId: 'agent-qa',
  dialects: ['polyglot/v1'],
  supportedChannels: ['qa/reports'],
  isAslNative: false,
  version: '1.0.0',
};

// Instantiate 5 clients
const orchestrator = new InMemoryAgentClient(orchestratorCap, router);
const planner = new InMemoryAgentClient(plannerCap, router);
const coder1 = new InMemoryAgentClient(coder1Cap, router);
const coder2 = new InMemoryAgentClient(coder2Cap, router);
const qa = new InMemoryAgentClient(qaCap, router);

// 1. Connect all 5 peers
console.log('1. Connecting 5 simulated heterogeneous agents...');
orchestrator.connect();
planner.connect();
coder1.connect();
coder2.connect();
qa.connect();

const activePeers = router.getActivePeers();
assert.strictEqual(activePeers.length, 5, 'All 5 peers must be registered');
console.log(`✓ 5 active peers verified: ${activePeers.map(p => p.peerId).join(', ')}`);

// 2. Direct Point-to-Point routing test
console.log('2. Testing Direct 1:1 message routing (orchestrator -> planner)...');
await orchestrator.send('agent-planner', 'DATA', { task: 'write_plan', phase: 'mesh_v1' });

assert.strictEqual(planner.receivedFrames.length, 1, 'Planner must receive 1 frame');
assert.strictEqual(coder1.receivedFrames.length, 0, 'Coder 1 must not receive 1:1 frame');
assert.strictEqual(qa.receivedFrames.length, 0, 'QA must not receive 1:1 frame');
assert.deepStrictEqual(planner.receivedFrames[0].body, { task: 'write_plan', phase: 'mesh_v1' });
console.log('✓ Direct 1:1 message verified');

// 3. Channel Pub/Sub Subscription Test
console.log('3. Testing Channel Pub/Sub (tasks/code)...');
coder1.subscribe('tasks/code');
coder2.subscribe('tasks/code');

const subscribers = router.getChannelSubscribers('tasks/code');
assert.strictEqual(subscribers.length, 2);
assert(subscribers.includes('agent-coder-1'));
assert(subscribers.includes('agent-coder-2'));
console.log(`✓ Channel subscribers verified: ${subscribers.join(', ')}`);

// 4. Topic Broadcast Test
console.log('4. Broadcasting task to tasks/code topic...');
const routeResult = await orchestrator.send('*', 'DATA', { action: 'implement_feature', id: 42 }, 'tasks/code');

assert.strictEqual(routeResult.status, 'DELIVERED');
assert.strictEqual(coder1.receivedFrames.length, 1, 'Coder 1 must receive broadcast');
assert.strictEqual(coder2.receivedFrames.length, 1, 'Coder 2 must receive broadcast');
assert.strictEqual(planner.receivedFrames.length, 1, 'Planner must still have only initial message');
assert.strictEqual(qa.receivedFrames.length, 0, 'QA must receive 0 messages');
console.log('✓ Topic broadcast delivered to all and only subscribers');

// 5. Dialect auto-adaptation (ASL Native -> Polyglot)
console.log('5. Testing Dialect Auto-adaptation (orchestrator -> QA)...');
await orchestrator.send('agent-qa', 'DATA', { check: 'run_security_scan' });
assert.strictEqual(qa.receivedFrames.length, 1, 'QA must receive message');
assert.strictEqual(qa.receivedFrames[0].header.dialect, 'polyglot/v1', 'Dialect must be auto-adapted to target preference');
console.log('✓ Dialect auto-adaptation verified (asl/v1 -> polyglot/v1)');

// 6. Dynamic Leave & Re-route Test
console.log('6. Testing Dynamic Leave (coder 1 disconnects)...');
coder1.disconnect();

const remainingPeers = router.getActivePeers();
assert.strictEqual(remainingPeers.length, 4, 'Must have 4 peers remaining after coder-1 leaves');
assert.strictEqual(router.getPeer('agent-coder-1'), undefined, 'coder-1 must be absent from registry');

console.log('Broadcasting second task to tasks/code after coder-1 departed...');
await orchestrator.send('*', 'DATA', { action: 'review_patch', patchId: 101 }, 'tasks/code');
assert.strictEqual(coder1.receivedFrames.length, 1, 'Coder 1 must not receive new message after leaving');
assert.strictEqual(coder2.receivedFrames.length, 2, 'Coder 2 must receive second task');
console.log('✓ Dynamic leave and topic subscription cleanup verified');

router.destroy();
console.log('--- ALL SKYLOOM MESH TOPOLOGY TESTS PASSED SUCCESSFULLY ---');
