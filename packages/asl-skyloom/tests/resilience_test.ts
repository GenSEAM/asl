/**
 * SkyLoom Resilience Acceptance Test Suite
 * Validates:
 * 1. Lonely Agent resolution via Mailbox queue & late peer join auto-delivery
 * 2. Heartbeat Watchdog & Stalled/Dead peer eviction
 * 3. Dead Letter Queue (DLQ) capture
 */

import assert from 'assert';
import {
  SkyLoomRouter,
  InMemoryAgentClient,
  PeerCapability,
  ErrorCode,
  LoomFrame,
} from '../src/index.js';

console.log('--- Running SkyLoom Resilience & Fault Tolerance Test Suite ---');

const router = new SkyLoomRouter({
  mailboxTtlMs: 10000,
  heartbeatTimeoutMs: 200, // fast timeout for test
});

const aliceCap: PeerCapability = {
  peerId: 'agent-alice',
  dialects: ['asl/v1'],
  supportedChannels: [],
  isAslNative: true,
  version: '1.0.0',
};

const bobCap: PeerCapability = {
  peerId: 'agent-bob',
  dialects: ['asl/v1'],
  supportedChannels: [],
  isAslNative: true,
  version: '1.0.0',
};

const alice = new InMemoryAgentClient(aliceCap, router);
const bob = new InMemoryAgentClient(bobCap, router);

// Connect Alice only (Bob is offline)
alice.connect();
console.log('1. Alice connected. Bob is currently offline (Lonely Agent scenario)...');

// 1. Alice sends messages to offline Bob
const res1 = await alice.send('agent-bob', 'DATA', { query: 'fetch_user_profile', uid: 42 });
const res2 = await alice.send('agent-bob', 'DATA', { query: 'fetch_user_audit', uid: 42 });

assert.strictEqual(res1.status, 'QUEUED');
assert.strictEqual(res1.errorCode, ErrorCode.ERR_LONELY_QUEUED);
assert.strictEqual(res2.status, 'QUEUED');
assert.strictEqual(res2.errorCode, ErrorCode.ERR_LONELY_QUEUED);

const mailboxStatusBefore = router.mailbox.getStatus('agent-bob');
assert.strictEqual(mailboxStatusBefore.pendingCount, 2, 'Mailbox must hold 2 queued messages for Bob');
console.log(`✓ 2 messages successfully buffered in mailbox for offline Bob (Lonely Agent handled)`);

// 2. Bob connects late!
console.log('2. Bob comes online and connects to SkyLoom mesh...');
let lonelyResolvedEventFired = false;
router.on('lonely:resolved', (evt) => {
  if (evt.peerId === 'agent-bob' && evt.deliveredCount === 2) {
    lonelyResolvedEventFired = true;
  }
});

bob.connect();

// Verify Bob automatically received the spooled mailbox messages!
assert.strictEqual(bob.receivedFrames.length, 2, 'Bob must have received both spooled messages upon connecting');
assert.deepStrictEqual(bob.receivedFrames[0].body, { query: 'fetch_user_profile', uid: 42 });
assert.deepStrictEqual(bob.receivedFrames[1].body, { query: 'fetch_user_audit', uid: 42 });

const mailboxStatusAfter = router.mailbox.getStatus('agent-bob');
assert.strictEqual(mailboxStatusAfter.pendingCount, 0, 'Mailbox must now be empty for Bob');
assert(lonelyResolvedEventFired, 'lonely:resolved event must fire to notify mesh of resolution');
console.log('✓ Automatic mailbox draining and message delivery to late-joining peer verified!');

// 3. Heartbeat Watchdog & Stalled Peer Eviction
console.log('3. Testing Heartbeat Watchdog and Stalled Peer Eviction...');
const charlieCap: PeerCapability = {
  peerId: 'agent-charlie',
  dialects: ['asl/v1'],
  supportedChannels: [],
  isAslNative: true,
  version: '1.0.0',
};

const charlie = new InMemoryAgentClient(charlieCap, router);
charlie.connect();
assert(router.getPeer('agent-charlie') !== undefined, 'Charlie is registered');

console.log('Charlie crashes/freezes and ceases heartbeats. Waiting for watchdog eviction...');
await new Promise((resolve) => setTimeout(resolve, 400));

assert.strictEqual(router.getPeer('agent-charlie'), undefined, 'Charlie must be evicted due to heartbeat expiration');
console.log('✓ Dead peer successfully evicted by heartbeat watchdog');

// 4. Dead Letter Queue (DLQ) Verification
console.log('4. Testing DLQ on unrecoverable transport delivery failure...');
const failingPeerCap: PeerCapability = {
  peerId: 'agent-faulty',
  dialects: ['asl/v1'],
  supportedChannels: [],
  isAslNative: true,
  version: '1.0.0',
};

// Register peer whose send function intentionally throws
router.registerPeer(failingPeerCap, () => {
  throw new Error('Kernel buffer overflow');
});

const sendFailResult = await alice.send('agent-faulty', 'DATA', { task: 'heavy_computation' });
assert.strictEqual(sendFailResult.status, 'DROPPED');
assert.strictEqual(sendFailResult.errorCode, ErrorCode.ERR_STALLED);

const dlqItems = router.dlq.getItems();
assert(dlqItems.length >= 1, 'DLQ must contain at least 1 failed message');
assert.strictEqual(dlqItems[dlqItems.length - 1].frame.header.to, 'agent-faulty');
assert.strictEqual(dlqItems[dlqItems.length - 1].code, ErrorCode.ERR_STALLED);
console.log('✓ Delivery failure safely captured in DLQ for analysis and retry');

router.destroy();
console.log('--- ALL SKYLOOM RESILIENCE TESTS PASSED SUCCESSFULLY ---');
