import { runWasm, createWasmInstance } from './wasm_runner.js';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as assert from 'node:assert';
import { execSync } from 'node:child_process';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const AGY_CLI = path.join(ROOT, 'agentscript');
const PYTHON = path.join(ROOT, '.venv/bin/python');

function buildWasm(sourcePath: string, outWasm: string): void {
  const cmd = `"${PYTHON}" "${AGY_CLI}" build "${sourcePath}" --target wasm -o "${outWasm}"`;
  execSync(cmd, { stdio: 'pipe' });
}

async function main() {
  console.log('[test_wasm_runner] Running in-memory WASI preview1 tests...');
  const tmpDir = fs.mkdtempSync('/tmp/asex_wasm_test_');

  try {
    // 1. Program execution with I/O (08-io.agentscript) - 1 arg
    const ioWasm = path.join(tmpDir, 'io.wasm');
    buildWasm(path.join(ROOT, 'grammar/corpus/valid/08-io.agentscript'), ioWasm);
    const res1 = await runWasm(fs.readFileSync(ioWasm), { args: ['main', 'missing_file.txt'] });
    assert.strictEqual(res1.exitCode, 0, '08-io should exit with 0');
    assert.strictEqual(res1.stdout.trim(), 'missing', '08-io with 1 arg should output "missing"');
    console.log('  ✔ stdout & argv capture on 08-io.wasm: "missing"');

    // 2. Program execution with I/O (08-io.agentscript) - 0 args -> stderr
    const res1b = await runWasm(fs.readFileSync(ioWasm), { args: ['main'] });
    assert.strictEqual(res1b.exitCode, 0, '08-io 0 args should exit with 0');
    assert.strictEqual(res1b.stderr.trim(), 'usage: io-demo SRC [DST]');
    console.log('  ✔ stderr capture on 08-io.wasm: "usage: io-demo SRC [DST]"');

    // 3. Numeric operations (23-numeric.agentscript)
    const numWasm = path.join(tmpDir, 'numeric.wasm');
    buildWasm(path.join(ROOT, 'grammar/corpus/valid/23-numeric.agentscript'), numWasm);
    const res2 = await runWasm(fs.readFileSync(numWasm));
    assert.strictEqual(res2.exitCode, 0, '23-numeric should exit with 0');
    console.log('  ✔ 23-numeric.wasm clean execution');

    // 4. Direct export invocation via createWasmInstance (01-basics cdylib)
    const basicsWasm = path.join(tmpDir, 'basics.wasm');
    buildWasm(path.join(ROOT, 'grammar/corpus/valid/01-basics.agentscript'), basicsWasm);
    const handle = await createWasmInstance(fs.readFileSync(basicsWasm));
    assert.ok(handle.instance instanceof WebAssembly.Instance);
    assert.ok(handle.memory instanceof WebAssembly.Memory);
    console.log('  ✔ Direct export instantiation via createWasmInstance');

    console.log('[test_wasm_runner] All tests passed! (4/4)');
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
