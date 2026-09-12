#!/usr/bin/env node
/**
 * ASL Sovereign Host Daemon Bridge (Node.js projection)
 * Architectural Reference: docs/LayerStratificationSpec.asn:102, docs/TestDebtAndFutureRefinements.asn:51
 *
 * Implements Layer 3 Node host daemon bridge with resilient S-expression stream framing,
 * defensive error handling, and continuous socket liveness.
 */

import net from 'node:net';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';

function parseArgs(args) {
  const options = {
    socketPath: `/tmp/asl_${process.env.USER || 'default'}_global.sock`,
    workspaceRoot: process.cwd(),
    pidFile: null,
    help: false
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--help' || arg === '-h') {
      options.help = true;
    } else if (arg === '--socket' && i + 1 < args.length) {
      options.socketPath = args[++i];
    } else if (arg === '--workspace' && i + 1 < args.length) {
      options.workspaceRoot = path.resolve(args[++i]);
    } else if (arg === '--pid-file' && i + 1 < args.length) {
      options.pidFile = args[++i];
    }
  }

  return options;
}

function showHelp() {
  console.log(`ASL Sovereign Host Daemon Bridge (Node.js Projection)

Usage:
  node asl-daemon-host.mjs [options]

Options:
  --socket <path>     UNIX domain socket path (default: /tmp/asl_<user>_global.sock)
  --workspace <path>  Workspace root directory (default: cwd)
  --pid-file <path>   Write process PID to file
  -h, --help          Show this help message
`);
}

function escapeString(str) {
  return str.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n').replace(/\r/g, '\\r');
}

function countParenAndQuoteBalance(str) {
  let depth = 0;
  let inStr = false;
  let esc = false;
  let malformed = false;

  for (let i = 0; i < str.length; i++) {
    const c = str[i];
    if (inStr) {
      if (esc) {
        esc = false;
      } else if (c === '\\') {
        esc = true;
      } else if (c === '"') {
        inStr = false;
      }
    } else {
      if (c === '"') {
        inStr = true;
      } else if (c === '(') {
        depth++;
      } else if (c === ')') {
        depth--;
        if (depth < 0) {
          malformed = true;
          break;
        }
      }
    }
  }

  return { depth, inStr, malformed };
}

function executeSingleStep(stepId, stepStr, workspaceRoot) {
  const trimmed = stepStr.trim();
  if (!trimmed.startsWith('(')) {
    return {
      success: false,
      output: `  (:step :id ${stepId} :op "batch" :status "error" :error-code ":ERR_INVALID_AST" :message "Invalid AST: expected S-expression")\n`
    };
  }

  let inner = trimmed.slice(1);
  if (inner.endsWith(')')) inner = inner.slice(0, -1);
  inner = inner.trim();

  const opMatch = inner.match(/^:?([a-zA-Z0-9_\-]+)/);
  const op = opMatch ? opMatch[1] : '';

  if (!op) {
    return {
      success: false,
      output: `  (:step :id ${stepId} :op "" :status "error" :error-code ":ERR_INVALID_AST" :message "Empty S-expression step")\n`
    };
  }

  if (op === 'ping') {
    return {
      success: true,
      output: `  (:step :id ${stepId} :op "ping" :status "ok" :result (:ok :pong))\n`
    };
  }

  if (op === 'echo') {
    const msgMatch = inner.match(/:message\s+"([^"]*)"/) || inner.match(/:echo\s+"([^"]*)"/);
    const msg = msgMatch ? msgMatch[1] : '';
    return {
      success: true,
      output: `  (:step :id ${stepId} :op "echo" :status "ok" :message "${escapeString(msg)}")\n`
    };
  }

  if (op === 'inspect') {
    return {
      success: true,
      output: `  (:step :id ${stepId} :op "inspect" :status "ok" :daemon-status (:daemon-status :status "active" :active-op ":idle"))\n`
    };
  }

  return {
    success: false,
    output: `  (:step :id ${stepId} :op "${escapeString(op)}" :status "rejected" :error-code ":ERR_UNIMPLEMENTED" :message "Operation not implemented")\n`
  };
}

function handlePayload(payload, workspaceRoot) {
  if (!payload || !payload.trim()) {
    return '(:batch-res :status "completed" :items-count 0 :parallel true :results [])\n';
  }

  const trimmed = payload.trim();

  if (trimmed === '(:ping)') {
    return '(:ok :pong)\n';
  }

  if (trimmed === '(:inspect)') {
    return '(:daemon-status :status "active" :active-op ":idle")\n';
  }

  if (!trimmed.startsWith('(')) {
    return '(:batch-res :status "error" :error-code ":ERR_INVALID_AST" :message "Invalid AST: expected S-expression" :items-count 1 :results [(:step :id 1 :op "batch" :status "error" :error-code ":ERR_INVALID_AST" :message "Invalid AST: expected S-expression")])\n';
  }

  const balance = countParenAndQuoteBalance(trimmed);
  if (balance.malformed || balance.inStr || balance.depth !== 0) {
    return '(:batch-res :status "error" :error-code ":ERR_MALFORMED_SEXPR" :message "Malformed S-expression: unclosed delimiter" :items-count 1 :results [(:step :id 1 :op "batch" :status "error" :error-code ":ERR_SYNTAX" :message "Unclosed delimiter in S-expression")])\n';
  }

  if (trimmed.startsWith('(:batch')) {
    let cur = trimmed.slice(7).trim();
    let depth = 0;
    let inStr = false;
    let esc = false;
    let stepStart = -1;
    const steps = [];

    for (let i = 0; i < cur.length; i++) {
      const c = cur[i];
      if (inStr) {
        if (esc) esc = false;
        else if (c === '\\') esc = true;
        else if (c === '"') inStr = false;
      } else {
        if (c === '"') {
          inStr = true;
        } else if (c === '(') {
          if (depth === 0) stepStart = i;
          depth++;
        } else if (c === ')') {
          depth--;
          if (depth === 0 && stepStart >= 0) {
            steps.push(cur.slice(stepStart, i + 1));
            stepStart = -1;
          }
        }
      }
    }

    if (steps.length === 0) {
      const nonParen = cur.replace(/\)/g, '').trim();
      if (nonParen.length > 0) {
        return '(:batch-res :status "error" :error-code ":ERR_INVALID_AST" :message "Invalid AST: expected step S-expressions in batch" :items-count 1 :results [(:step :id 1 :op "batch" :status "error" :error-code ":ERR_INVALID_AST" :message "Invalid AST: expected step S-expressions in batch")])\n';
      }
      return '(:batch-res :status "completed" :items-count 0 :parallel true :results [])\n';
    }

    let failedCount = 0;
    let stepOutputs = '';

    for (let idx = 0; idx < steps.length; idx++) {
      const res = executeSingleStep(idx + 1, steps[idx], workspaceRoot);
      if (!res.success) failedCount++;
      stepOutputs += res.output;
    }

    let status = 'completed';
    if (failedCount === steps.length) {
      status = 'failed';
    } else if (failedCount > 0) {
      status = 'completed-with-errors';
    }

    const failedStr = failedCount > 0 ? ` :failed-count ${failedCount}` : '';
    return `(:batch-res :status "${status}" :items-count ${steps.length}${failedStr} :parallel true :results [\n${stepOutputs}])\n`;
  }

  const res = executeSingleStep(1, trimmed, workspaceRoot);
  const status = res.success ? 'completed' : 'failed';
  const failedStr = res.success ? '' : ' :failed-count 1';
  return `(:batch-res :status "${status}" :items-count 1${failedStr} :parallel true :results [\n${res.output}])\n`;
}

function startServer(options) {
  const { socketPath, workspaceRoot, pidFile } = options;

  try {
    if (fs.existsSync(socketPath)) {
      fs.unlinkSync(socketPath);
    }
  } catch {}

  const server = net.createServer({ allowHalfOpen: true }, (socket) => {
    socket.setTimeout(1000);

    let reqBuf = '';
    let depth = 0;
    let started = false;
    let inStr = false;
    let esc = false;
    let timedOut = false;
    let responded = false;

    function finishAndRespond() {
      if (responded) return;
      responded = true;
      try {
        const response = handlePayload(reqBuf, workspaceRoot);
        socket.end(response);
      } catch (err) {
        const errResp = `(:batch-res :status "error" :error-code ":ERR_INTERNAL" :message "${escapeString(err.message)}" :items-count 1 :results [(:step :id 1 :op "batch" :status "error" :error-code ":ERR_INTERNAL" :message "${escapeString(err.message)}")])\n`;
        socket.end(errResp);
      }
    }

    socket.on('data', (chunk) => {
      if (responded) return;
      const str = chunk.toString('utf8');
      reqBuf += str;

      for (let i = 0; i < str.length; i++) {
        const c = str[i];
        if (inStr) {
          if (esc) esc = false;
          else if (c === '\\') esc = true;
          else if (c === '"') inStr = false;
        } else {
          if (c === '"') {
            inStr = true;
          } else if (c === '(') {
            depth++;
            started = true;
          } else if (c === ')') {
            depth--;
            if (started && depth === 0) break;
          } else if (c === '\n' && !started && reqBuf.trim().length > 0) {
            break;
          }
        }
      }

      if (started && depth === 0) {
        finishAndRespond();
      } else if (!started && reqBuf.endsWith('\n') && reqBuf.trim().length > 0) {
        finishAndRespond();
      }
    });

    socket.on('end', () => {
      if (!responded) {
        finishAndRespond();
      }
    });

    socket.on('timeout', () => {
      if (responded) return;
      timedOut = true;
      if (reqBuf.length > 0) {
        finishAndRespond();
      } else {
        responded = true;
        const timeoutErr = '(:batch-res :status "error" :error-code ":ERR_TIMEOUT" :message "Socket receive timeout" :items-count 1 :results [(:step :id 1 :op "batch" :status "error" :error-code ":ERR_TIMEOUT" :message "Socket receive timeout")])\n';
        socket.end(timeoutErr);
      }
    });

    socket.on('error', () => {
      socket.destroy();
    });
  });

  server.on('error', (err) => {
    console.error(`Daemon server error: ${err.message}`);
    process.exit(1);
  });

  const cleanup = () => {
    try {
      if (fs.existsSync(socketPath)) fs.unlinkSync(socketPath);
      if (pidFile && fs.existsSync(pidFile)) fs.unlinkSync(pidFile);
    } catch {}
    process.exit(0);
  };

  process.on('SIGINT', cleanup);
  process.on('SIGTERM', cleanup);
  process.on('exit', () => {
    try {
      if (fs.existsSync(socketPath)) fs.unlinkSync(socketPath);
      if (pidFile && fs.existsSync(pidFile)) fs.unlinkSync(pidFile);
    } catch {}
  });

  server.listen(socketPath, () => {
    if (pidFile) {
      fs.writeFileSync(pidFile, `${process.pid}\n`, 'utf8');
    }
    console.log(`ASL Sovereign Node Bridge resident at: ${socketPath} (PID: ${process.pid})`);
  });
}

function main() {
  const options = parseArgs(process.argv.slice(2));

  if (options.help) {
    showHelp();
    process.exit(0);
  }

  startServer(options);
}

main();
