import test from 'node:test';
import assert from 'node:assert/strict';
import { GraphEngine } from '../src/lib/graph_engine.ts';

test('GraphEngine - Topology Initialization & Sizing', () => {
  const engine = new GraphEngine(5000);
  assert.equal(engine.nodeCount, 5000);
  assert.equal(engine.edgeCount, 12500);
  assert.equal(engine.positions.length, 10000); // 5000 * 2
  assert.equal(engine.velocities.length, 10000);

  // Resize to 100K nodes
  engine.setNodeCount(100000);
  assert.equal(engine.nodeCount, 100000);
  assert.equal(engine.positions.length, 200000);
  assert.ok(engine.getMemoryUsageMb() > 1.0);
});

test('GraphEngine - JavaScript Mode with Anti-Freeze Budget Cap', () => {
  const engine = new GraphEngine(20000);
  engine.mode = 'javascript';

  const res = engine.stepPhysics(1000, 800);
  assert.ok(typeof res.computeTimeMs === 'number');
  assert.equal(typeof res.throttled, 'boolean');
  assert.equal(res.speedupVsJs, 1.0);
});

test('GraphEngine - WebAssembly Mode Performance & Zero Allocations', () => {
  const engine = new GraphEngine(10000);
  engine.mode = 'webassembly';

  const res = engine.stepPhysics(1000, 800);
  assert.ok(res.computeTimeMs < 16.0, `Compute time ${res.computeTimeMs}ms should be < 16ms for 60 FPS`);
  assert.equal(res.throttled, false);
  assert.ok(res.speedupVsJs >= 1.0);
});
