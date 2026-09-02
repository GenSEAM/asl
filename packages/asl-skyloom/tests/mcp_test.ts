/**
 * SkyLoom MCP Server Acceptance Test Suite
 * Tests MCP tool definitions, tool invocations, session states, and skill consistency.
 */

import assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';
import {
  SkyLoomRouter,
  SkyLoomMcpServer,
} from '../src/index.js';

console.log('--- Running SkyLoom MCP Server Test Suite ---');

const router = new SkyLoomRouter();
const mcp = new SkyLoomMcpServer(router);

// 1. Tool Listing Test
console.log('1. Verifying MCP Tool Definitions...');
const tools = mcp.getTools();
assert.strictEqual(tools.length, 6, 'Must expose 6 MCP tools');
const toolNames = tools.map(t => t.name);
assert(toolNames.includes('skyloom_connect'));
assert(toolNames.includes('skyloom_send'));
assert(toolNames.includes('skyloom_poll'));
assert(toolNames.includes('skyloom_peers'));
assert(toolNames.includes('skyloom_mailbox_status'));
assert(toolNames.includes('skyloom_bootstrap_peer'));
console.log(`✓ 6 MCP tools validated: ${toolNames.join(', ')}`);

// 2. Connect Tool Calls
console.log('2. Testing skyloom_connect tool call for 2 agents...');
const connRes1 = await mcp.handleToolCall('skyloom_connect', {
  agentId: 'agent-mcp-orchestrator',
  channels: ['control'],
  isAslNative: true,
});
assert.strictEqual(connRes1.isError, undefined);
const parsedConn1 = JSON.parse(connRes1.content[0].text);
assert.strictEqual(parsedConn1.status, 'CONNECTED');
assert.strictEqual(parsedConn1.agentId, 'agent-mcp-orchestrator');

const connRes2 = await mcp.handleToolCall('skyloom_connect', {
  agentId: 'agent-mcp-worker',
  channels: ['tasks'],
  isAslNative: false,
});
assert.strictEqual(connRes2.isError, undefined);
console.log('✓ Both agents successfully connected via MCP');

// 3. Peers Discovery Tool Call
console.log('3. Testing skyloom_peers tool call...');
const peersRes = await mcp.handleToolCall('skyloom_peers', {});
const peersData = JSON.parse(peersRes.content[0].text);
assert.strictEqual(peersData.count, 2);
const ids = peersData.peers.map((p: any) => p.peerId);
assert(ids.includes('agent-mcp-orchestrator'));
assert(ids.includes('agent-mcp-worker'));
console.log(`✓ Active peers discovered: ${ids.join(', ')}`);

// 4. Send & Poll Tool Calls
console.log('4. Testing skyloom_send and skyloom_poll tool calls...');
const sendRes = await mcp.handleToolCall('skyloom_send', {
  from: 'agent-mcp-orchestrator',
  to: 'agent-mcp-worker',
  payload: { action: 'build_ui_showcase', target: 'web' },
});
assert.strictEqual(sendRes.isError, undefined);
const sendData = JSON.parse(sendRes.content[0].text);
assert.strictEqual(sendData.status, 'DELIVERED');

const pollRes = await mcp.handleToolCall('skyloom_poll', {
  agentId: 'agent-mcp-worker',
});
const pollData = JSON.parse(pollRes.content[0].text);
assert.strictEqual(pollData.messageCount, 1);
assert.strictEqual(pollData.messages[0].header.from, 'agent-mcp-orchestrator');
assert.deepStrictEqual(pollData.messages[0].body, { action: 'build_ui_showcase', target: 'web' });
console.log('✓ Message delivered and polled via MCP tools successfully');

// 5. Mailbox & Lonely-Agent Check Tool Call
console.log('5. Testing skyloom_mailbox_status on offline agent...');
await mcp.handleToolCall('skyloom_send', {
  from: 'agent-mcp-orchestrator',
  to: 'agent-offline-peer',
  payload: { note: 'wake_up' },
});

const mailboxRes = await mcp.handleToolCall('skyloom_mailbox_status', {
  peerId: 'agent-offline-peer',
});
const mailboxData = JSON.parse(mailboxRes.content[0].text);
assert.strictEqual(mailboxData.pendingCount, 1);
console.log('✓ Lonely-agent mailbox verified via MCP tool');

// 6. Bootstrap Peer Tool Call
console.log('6. Testing skyloom_bootstrap_peer tool call...');
const bootRes = await mcp.handleToolCall('skyloom_bootstrap_peer', {
  targetPeerId: 'vanilla-agent',
  senderId: 'agent-mcp-orchestrator',
});
const bootData = JSON.parse(bootRes.content[0].text);
assert(bootData.primerMarkdown.includes('SkyLoom'));
console.log('✓ Bootstrap primer generated successfully');

// 7. Verify Skill File on disk
console.log('7. Verifying skills/skyloom/SKILL.md existence and format...');
const skillPath = path.resolve(process.cwd(), 'skills/skyloom/SKILL.md');
assert(fs.existsSync(skillPath), 'SKILL.md must exist in skills/skyloom');
const skillContent = fs.readFileSync(skillPath, 'utf-8');
assert(skillContent.includes('name: skyloom'));
assert(skillContent.includes('skyloom_connect'));
console.log('✓ Universal SkyLoom skill definition verified on disk');

router.destroy();
console.log('--- ALL SKYLOOM MCP SERVER TESTS PASSED SUCCESSFULLY ---');
