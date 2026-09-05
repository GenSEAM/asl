/**
 * SkyLoom Phase 2 Acceptance Test:
 * Directory Scoping & Zero-Leak Mesh Firewall
 */

import assert from 'node:assert';
import { SkyLoomRouter, isPathInScope, isPeerPermitted } from '../src/mesh.js';
import { LoomFrame, ErrorCode, HandoffPayload } from '../src/types.js';

console.log('--- Running SkyLoom Directory Scoping & Zero-Leak Firewall Tests ---');

// 1. Test isPathInScope utility
console.log('1. Testing path scope matching logic...');
assert(isPathInScope('*', 'any/path/at/all'), 'Wildcard must match anything');
assert(isPathInScope('packages/asl-rate/*', 'packages/asl-rate/src/limiter.asl'), 'Subpath must match');
assert(isPathInScope('packages/asl-rate', 'packages/asl-rate/src/limiter.asl'), 'Root prefix must match');
assert(!isPathInScope('packages/asl-rate/*', 'packages/asl-web-search/src/engine.asl'), 'Disjoint path must NOT match');
assert(!isPathInScope('web/*', 'services/api/routes.asl'), 'Cross-boundary path must NOT match');
console.log('✓ Path matching assertions verified');

// 2. Setup Router with 3 heterogeneous scoped agents
console.log('\n2. Registering agents with distinct directory scopes...');
const router = new SkyLoomRouter();

const orchestratorInbox: LoomFrame[] = [];
const frontendInbox: LoomFrame[] = [];
const backendInbox: LoomFrame[] = [];

router.registerPeer(
  {
    peerId: 'agent-orchestrator',
    dialects: ['asl/coord', 'asl/v1'],
    supportedChannels: ['*'],
    isAslNative: true,
    version: '1.0.0',
    permittedScopes: ['*'], // Global authority
  },
  frame => {
    orchestratorInbox.push(frame);
    return true;
  }
);

router.registerPeer(
  {
    peerId: 'agent-frontend',
    dialects: ['asl/coord', 'asl/v1'],
    supportedChannels: ['general/announcements', 'services/api/events'],
    isAslNative: true,
    version: '1.0.0',
    cwd: 'web',
    permittedScopes: ['web/*', 'ui/*'], // Jailed to frontend
  },
  frame => {
    frontendInbox.push(frame);
    return true;
  }
);

router.registerPeer(
  {
    peerId: 'agent-backend',
    dialects: ['asl/coord', 'asl/v1'],
    supportedChannels: ['services/api/events'],
    isAslNative: true,
    version: '1.0.0',
    cwd: 'services/api',
    permittedScopes: ['services/api/*', 'services/db/*'], // Jailed to backend
  },
  frame => {
    backendInbox.push(frame);
    return true;
  }
);

assert.strictEqual(router.getActivePeers().length, 3);
console.log('✓ 3 peers registered with jailed scopes: orchestrator (*), frontend (web/*), backend (services/*)');

// 3. Test Zero-Leak Firewall on Pub-Sub Topic
console.log('\n3. Testing Zero-Leak Firewall: orchestrator publishes to services/api/events...');
// Both frontend and backend subscribed to 'services/api/events', but frontend is jailed outside services/*
const pubResult = await router.route({
  header: {
    version: 1,
    id: 'evt-001',
    from: 'agent-orchestrator',
    to: '*',
    dialect: 'asl/v1',
    timestamp: Date.now(),
  },
  type: 'DATA',
  channel: 'services/api/events',
  body: { event: 'db_migration_started', targetTable: 'users' },
});

assert.strictEqual(pubResult.status, 'DELIVERED');
assert(pubResult.recipients.includes('agent-backend'), 'Backend must receive services event');
assert(!pubResult.recipients.includes('agent-frontend'), 'Frontend must be filtered out by Zero-Leak Firewall');
assert.strictEqual(backendInbox.length, 1, 'Backend received 1 frame');
assert.strictEqual(frontendInbox.length, 0, 'Frontend received 0 frames (zero token leakage!)');
console.log('✓ Zero-Leak verification: backend received event, frontend context remained 100% clean');

// 4. Test Sender Scope Enforcement (Frontend attempts cross-boundary write)
console.log('\n4. Testing Sender Scope Enforcement: jailed frontend attempts to publish to services/db/migrate...');
const leakAttemptResult = await router.route({
  header: {
    version: 1,
    id: 'leak-001',
    from: 'agent-frontend',
    to: '*',
    dialect: 'asl/v1',
    timestamp: Date.now(),
  },
  type: 'DATA',
  channel: 'services/db/migrate',
  body: { alterTable: 'drop_users' },
});

assert.strictEqual(leakAttemptResult.status, 'DROPPED');
assert.strictEqual(leakAttemptResult.errorCode, ErrorCode.ERR_SCOPE_VIOLATION);
assert.strictEqual(router.dlq.getAll().length, 1, 'Scope violation must be captured in DLQ');
assert(router.dlq.getAll()[0].reason.includes('lacks permission for scope'));
console.log('✓ Sender scope breach rejected with ERR_SCOPE_VIOLATION (1009) and safely logged to DLQ');

// 5. Test Handoff-driven Dynamic Scoping
console.log('\n5. Testing Handoff-driven Dynamic Scoping...');
const workerInbox: LoomFrame[] = [];
router.registerPeer(
  {
    peerId: 'agent-worker',
    dialects: ['asl/coord'],
    supportedChannels: [],
    isAslNative: true,
    version: '1.0.0',
    permittedScopes: ['*'], // Unrestricted until handoff
  },
  frame => {
    workerInbox.push(frame);
    return true;
  }
);

const handoffRes = await router.route({
  header: {
    version: 1,
    id: 'handoff-jail-001',
    from: 'agent-orchestrator',
    to: 'agent-worker',
    dialect: 'asl/coord',
    timestamp: Date.now(),
  },
  type: 'HANDOFF',
  body: {
    task: 'implement_rate_limiter',
    cwd: 'packages/asl-rate',
    owns: ['src/limiter.asl'],
    gate: 'asl check src/limiter.asl',
  } as HandoffPayload,
});

assert.strictEqual(handoffRes.status, 'DELIVERED');
assert.strictEqual(workerInbox.length, 1);

// Verify worker's scope is now dynamically jailed to 'packages/asl-rate'
const workerPeer = router.getPeer('agent-worker')!;
assert.strictEqual(workerPeer.cwd, 'packages/asl-rate');
assert(workerPeer.permittedScopes!.includes('packages/asl-rate/*'));
console.log('✓ Worker peer successfully jailed to handoff directory (packages/asl-rate/*)');

router.destroy();
console.log('\n--- ALL SKYLOOM DIRECTORY SCOPING TESTS PASSED CLEANLY ---');
