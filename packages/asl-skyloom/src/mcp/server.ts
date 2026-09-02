/**
 * SkyLoom Model Context Protocol (MCP) Server
 * Exposes inter-agent mesh communication tools to external AI agents.
 */

import { SkyLoomRouter } from '../mesh.js';
import { LoomFrame, PeerCapability, ErrorCode } from '../types.js';
import { AsymmetricNegotiator } from '../negotiator.js';
import { encodeFrame } from '../codec.js';

export interface McpToolDefinition {
  name: string;
  description: string;
  parameters: {
    type: 'object';
    properties: Record<string, unknown>;
    required: string[];
  };
}

export class SkyLoomMcpServer {
  private inboxes: Map<string, LoomFrame[]> = new Map(); // peerId -> received messages

  constructor(public readonly router: SkyLoomRouter) {}

  /**
   * Returns tool definitions exposed by SkyLoom MCP server
   */
  getTools(): McpToolDefinition[] {
    return [
      {
        name: 'skyloom_connect',
        description: 'Connects the calling AI agent to the SkyLoom inter-agent mesh network.',
        parameters: {
          type: 'object',
          properties: {
            agentId: { type: 'string', description: 'Unique agent identifier' },
            channels: {
              type: 'array',
              items: { type: 'string' },
              description: 'Topic channels to subscribe to',
            },
            isAslNative: {
              type: 'boolean',
              description: 'Whether the agent can directly process ASL S-expression ASTs',
            },
          },
          required: ['agentId'],
        },
      },
      {
        name: 'skyloom_send',
        description: 'Sends a message to a direct peer or topic channel across the mesh.',
        parameters: {
          type: 'object',
          properties: {
            from: { type: 'string', description: 'Sender agent ID' },
            to: { type: 'string', description: 'Target agent ID or "*" for topic broadcast' },
            channel: { type: 'string', description: 'Optional channel name for topic routing' },
            payload: { type: 'object', description: 'Structured JSON payload or task instructions' },
            type: {
              type: 'string',
              enum: ['DATA', 'HANDSHAKE', 'ACK', 'NACK', 'PING'],
              description: 'Frame type (defaults to DATA)',
            },
          },
          required: ['from', 'to', 'payload'],
        },
      },
      {
        name: 'skyloom_poll',
        description: 'Polls incoming messages and drained mailbox events for this agent.',
        parameters: {
          type: 'object',
          properties: {
            agentId: { type: 'string', description: 'Agent ID checking its inbox' },
            limit: { type: 'number', description: 'Maximum messages to fetch' },
          },
          required: ['agentId'],
        },
      },
      {
        name: 'skyloom_peers',
        description: 'Lists all currently active peers connected to the SkyLoom mesh.',
        parameters: {
          type: 'object',
          properties: {},
          required: [],
        },
      },
      {
        name: 'skyloom_mailbox_status',
        description: 'Inspects queued messages in the Lonely-Agent mailbox.',
        parameters: {
          type: 'object',
          properties: {
            peerId: { type: 'string', description: 'Agent ID to inspect mailbox for' },
          },
          required: ['peerId'],
        },
      },
      {
        name: 'skyloom_bootstrap_peer',
        description:
          'Generates a self-describing protocol primer to inject into an unaware LLM peer so it learns how to communicate via SkyLoom.',
        parameters: {
          type: 'object',
          properties: {
            targetPeerId: { type: 'string', description: 'Unaware peer ID to generate primer for' },
            senderId: { type: 'string', description: 'Sender agent ID' },
          },
          required: ['targetPeerId', 'senderId'],
        },
      },
      {
        name: 'skyloom_handoff',
        description:
          'Issues a context-isolated handoff frame in asl/coord dialect with directory scoping, owned files, and verification gate.',
        parameters: {
          type: 'object',
          properties: {
            from: { type: 'string', description: 'Orchestrator or delegating agent ID' },
            to: { type: 'string', description: 'Assignee target agent ID' },
            task: { type: 'string', description: 'Discrete task name' },
            cwd: { type: 'string', description: 'Scoped working directory' },
            owns: { type: 'array', items: { type: 'string' }, description: 'Permitted files agent can edit' },
            frozen: { type: 'array', items: { type: 'string' }, description: 'Frozen files agent must not edit' },
            gate: { type: 'string', description: 'Verification shell command' },
            budget: { type: 'number', description: 'Maximum token budget' },
          },
          required: ['from', 'to', 'task', 'cwd', 'gate'],
        },
      },
      {
        name: 'skyloom_yield',
        description: 'Yields completed task artifacts and verification status back to delegating agent.',
        parameters: {
          type: 'object',
          properties: {
            from: { type: 'string', description: 'Assignee agent ID completing work' },
            to: { type: 'string', description: 'Orchestrator agent ID' },
            replyTo: { type: 'string', description: 'Original handoff frame ID' },
            status: { type: 'string', enum: ['ok', 'failed', 'rejected'], description: 'Execution verdict' },
            gateVerdict: { type: 'string', description: 'Output summary of gate verification command' },
            artifacts: { type: 'array', items: { type: 'string' }, description: 'Modified or created files' },
            error: { type: 'string', description: 'Error message if failed' },
          },
          required: ['from', 'to', 'replyTo', 'status'],
        },
      },
    ];
  }

  /**
   * Dispatches an MCP tool call
   */
  async handleToolCall(name: string, args: any): Promise<{ content: Array<{ type: 'text'; text: string }>; isError?: boolean }> {
    try {
      switch (name) {
        case 'skyloom_connect': {
          const agentId = args.agentId;
          const channels = args.channels || [];
          const isAslNative = args.isAslNative ?? false;

          if (!this.inboxes.has(agentId)) {
            this.inboxes.set(agentId, []);
          }

          const capability: PeerCapability = {
            peerId: agentId,
            dialects: isAslNative ? ['asl/v1', 'polyglot/v1'] : ['polyglot/v1'],
            supportedChannels: channels,
            isAslNative,
            version: '1.0.0',
          };

          this.router.registerPeer(capability, (frame: LoomFrame) => {
            if (!this.inboxes.has(agentId)) {
              this.inboxes.set(agentId, []);
            }
            this.inboxes.get(agentId)!.push(frame);
            return true;
          });

          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  status: 'CONNECTED',
                  agentId,
                  channels,
                  dialect: capability.dialects[0],
                  meshActivePeers: this.router.getActivePeers().length,
                }),
              },
            ],
          };
        }

        case 'skyloom_send': {
          const from = args.from;
          const to = args.to;
          const channel = args.channel;
          const payload = args.payload;
          const type = args.type || 'DATA';

          const senderCap = this.router.getPeer(from);
          const dialect = senderCap?.dialects[0] || 'polyglot/v1';

          const frame: LoomFrame = {
            header: {
              version: 1,
              id: `msg-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
              from,
              to,
              dialect,
              timestamp: Date.now(),
            },
            type,
            channel,
            body: payload,
          };

          const result = await this.router.route(frame);
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify(result),
              },
            ],
          };
        }

        case 'skyloom_poll': {
          const agentId = args.agentId;
          const limit = args.limit || 50;
          const inbox = this.inboxes.get(agentId) || [];
          const messages = inbox.splice(0, limit);

          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  agentId,
                  messageCount: messages.length,
                  messages,
                }),
              },
            ],
          };
        }

        case 'skyloom_peers': {
          const peers = this.router.getActivePeers();
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({ peers, count: peers.length }),
              },
            ],
          };
        }

        case 'skyloom_mailbox_status': {
          const peerId = args.peerId;
          const status = this.router.mailbox.getStatus(peerId);
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify(status),
              },
            ],
          };
        }

        case 'skyloom_bootstrap_peer': {
          const primer = AsymmetricNegotiator.generateSkillPrimer(args.senderId);
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  targetPeerId: args.targetPeerId,
                  primerMarkdown: primer,
                  instruction: 'Inject this primer into your outgoing message or the target agent prompt.',
                }),
              },
            ],
          };
        }

        case 'skyloom_handoff': {
          const { from, to, task, cwd, owns, frozen, gate, budget } = args;
          const frame: LoomFrame = {
            header: {
              version: 1,
              id: `handoff-${Date.now()}`,
              from,
              to,
              dialect: 'asl/coord',
              timestamp: Date.now(),
            },
            type: 'HANDOFF',
            body: {
              task,
              cwd,
              owns: owns || [],
              frozen: frozen || [],
              gate,
              budget: budget || 5000,
            },
          };
          const result = await this.router.route(frame);
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify(
                  {
                    status: result.status,
                    frameId: frame.header.id,
                    wireFrame: encodeFrame(frame, 'asl/coord'),
                  },
                  null,
                  2
                ),
              },
            ],
          };
        }

        case 'skyloom_yield': {
          const { from, to, replyTo, status, gateVerdict, artifacts, error } = args;
          const frame: LoomFrame = {
            header: {
              version: 1,
              id: `yield-${Date.now()}`,
              replyTo,
              from,
              to,
              dialect: 'asl/coord',
              timestamp: Date.now(),
            },
            type: 'YIELD',
            body: {
              status,
              gateVerdict,
              artifacts: artifacts || [],
              error,
            },
          };
          const result = await this.router.route(frame);
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify(
                  {
                    status: result.status,
                    frameId: frame.header.id,
                    wireFrame: encodeFrame(frame, 'asl/coord'),
                  },
                  null,
                  2
                ),
              },
            ],
          };
        }

        default:
          return {
            isError: true,
            content: [{ type: 'text', text: `Unknown tool: ${name}` }],
          };
      }
    } catch (err: any) {
      return {
        isError: true,
        content: [{ type: 'text', text: `Tool execution failed: ${err?.message}` }],
      };
    }
  }
}
