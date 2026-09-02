/**
 * SkyLoom MCP Stdio Server Runner
 * Implements the standard Model Context Protocol over stdin/stdout for AI agent harnesses.
 */

import * as readline from 'readline';
import { SkyLoomRouter } from '../mesh.js';
import { SkyLoomMcpServer } from './server.js';

export function runMcpStdio(router?: SkyLoomRouter): void {
  const meshRouter = router || new SkyLoomRouter();
  const mcpServer = new SkyLoomMcpServer(meshRouter);

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false,
  });

  const sendResponse = (id: string | number | null, result?: unknown, error?: unknown) => {
    const payload: Record<string, unknown> = { jsonrpc: '2.0', id };
    if (error) {
      payload.error = error;
    } else {
      payload.result = result ?? {};
    }
    process.stdout.write(JSON.stringify(payload) + '\n');
  };

  rl.on('line', async (line) => {
    const trimmed = line.trim();
    if (!trimmed) return;

    try {
      const msg = JSON.parse(trimmed);
      const { id, method, params } = msg;

      switch (method) {
        case 'initialize': {
          sendResponse(id, {
            protocolVersion: '2024-11-05',
            capabilities: {
              tools: {},
            },
            serverInfo: {
              name: 'skyloom-mcp',
              version: '1.0.0',
            },
          });
          break;
        }

        case 'notifications/initialized': {
          // Client acknowledgement
          break;
        }

        case 'tools/list': {
          const tools = mcpServer.getTools();
          sendResponse(id, { tools });
          break;
        }

        case 'tools/call': {
          const { name, arguments: toolArgs } = params || {};
          const result = await mcpServer.handleToolCall(name, toolArgs || {});
          sendResponse(id, result);
          break;
        }

        case 'ping': {
          sendResponse(id, {});
          break;
        }

        default: {
          if (id !== undefined && id !== null) {
            sendResponse(id, undefined, {
              code: -32601,
              message: `Method not found: ${method}`,
            });
          }
          break;
        }
      }
    } catch (err: any) {
      sendResponse(null, undefined, {
        code: -32700,
        message: `Parse error: ${err?.message}`,
      });
    }
  });

  rl.on('close', () => {
    process.exit(0);
  });

  process.stderr.write('[SkyLoom MCP] Stdio server initialized and listening on stdin/stdout\n');
}

// Auto-run if executed directly
if (process.argv[1]?.endsWith('stdio.js') || process.argv[1]?.endsWith('stdio.ts')) {
  runMcpStdio();
}
