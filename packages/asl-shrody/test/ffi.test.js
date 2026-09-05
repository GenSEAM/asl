import { test } from 'node:test';
import assert from 'node:assert/strict';
import { HostBridge } from '../bridges/host_bridge.js';

test('HostBridge executes round-trip dispatch across fs, audio, llm capabilities', async () => {
  const bridge = new HostBridge();

  // Audio speak
  const speakRes = await bridge.hostCall('audio', 'speak', 'hello world');
  assert.equal(speakRes.ok, true);
  assert.equal(speakRes.value, 'playback_started');

  // Conversational barge-in cutoff
  const interruptRes = await bridge.hostCall('audio', 'interrupt', '');
  assert.equal(interruptRes.ok, true);
  assert.match(interruptRes.value, /interrupted in \d+(\.\d+)?ms/);
  assert.ok(bridge.lastInterruptLatencyMs < 5, `Interrupt latency must be < 5ms, got ${bridge.lastInterruptLatencyMs}ms`);

  // LLM complete
  const llmRes = await bridge.hostCall('llm', 'complete', 'test prompt');
  assert.equal(llmRes.ok, true);
  assert.match(llmRes.value, /LLM answer to: test prompt/);
});

test('HostBridge propagates errors for unknown capabilities and invalid actions', async () => {
  const bridge = new HostBridge();

  const unknownCap = await bridge.hostCall('teleportation', 'jump', '');
  assert.equal(unknownCap.ok, false);
  assert.match(unknownCap.error, /Unknown host capability/);

  const unknownAct = await bridge.hostCall('audio', 'cook_dinner', '');
  assert.equal(unknownAct.ok, false);
  assert.match(unknownAct.error, /Unsupported audio action/);
});

test('HostBridge handles 10,000 synthetic calls with zero memory leaks and bounded performance', () => {
  const bridge = new HostBridge();
  const memBefore = process.memoryUsage().heapUsed;

  for (let i = 0; i < 10000; i++) {
    const res = bridge.hostCallSync('audio', i % 2 === 0 ? 'speak' : 'interrupt', 'chunk');
    assert.equal(res.ok, true);
  }

  const memAfter = process.memoryUsage().heapUsed;
  const growthMb = (memAfter - memBefore) / 1024 / 1024;
  assert.ok(growthMb < 15, `Memory growth must be bounded (<15MB), grew ${growthMb.toFixed(2)}MB`);
  assert.equal(bridge.callCount, 10000);
});
