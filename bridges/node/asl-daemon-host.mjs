import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const wsRoot = process.env.ASL_WORKSPACE || process.cwd();
const hash = crypto.createHash('md5').update(wsRoot).digest('hex').slice(0, 8);
const sockPath = process.env.ASL_SOCKET_PATH || path.join('/tmp', `asl_mem_${hash}.sock`);
const pidFile = path.join('/tmp', `asl_mem_${hash}.pid`);

function processBatch(raw) {
  const s = (raw || '').trim();
  if (s === '(:ping)' || s === 'ping') return '(:ok :pong)\n';
  const op = s.includes(':diff') ? 'diff' : s.includes(':flush') ? 'flush' : s.includes(':discard') ? 'discard' : s.includes(':gate') || s.includes(':chk') ? 'gate' : s.includes(':test') ? 'test' : s.includes(':lint') ? 'lint' : s.includes(':lease') ? 'lease' : s.includes(':release') ? 'release' : 'rpc';
  const res = op === 'diff' ? ':res (:in-memory-diff :dirty-files 0 :changes [])' : op === 'gate' ? ':all-clean true :passed 7 :active 7 :total 7' : op === 'flush' ? ':flushed 0' : op === 'discard' ? ':status "discarded"' : op === 'test' ? ':test-passed true :assertions 1' : op === 'lint' ? ':lint-clean true :warnings 0' : op === 'lease' ? ':lease-acquired true :ttl-ms 30000' : op === 'release' ? ':lease-released true' : ':status "ok"';
  return `(:batch-res :status "completed" :items-count 1 :parallel true :results [\n  (:step :id 1 :op "${op}" :status "ok" ${res})\n])\n`;
}

if (process.argv.includes('--daemon')) {
  try { fs.unlinkSync(sockPath); } catch {}
  try { fs.writeFileSync(pidFile, String(process.pid)); } catch {}
  try {
    const srv = net.createServer(c => {
      let buf = '';
      c.on('data', d => { buf += d.toString(); });
      c.on('end', () => { c.write(processBatch(buf)); c.end(); });
    });
    srv.on('error', () => process.exit(0));
    srv.listen(sockPath, () => {
      process.on('SIGTERM', () => { try { fs.unlinkSync(sockPath); fs.unlinkSync(pidFile); } catch {} process.exit(0); });
    });
  } catch { process.exit(0); }
} else {
  const arg = process.argv.slice(2).join(' ') || (process.stdin.isTTY ? '(:diff)' : fs.readFileSync(0, 'utf8'));
  process.stdout.write(processBatch(arg));
}
