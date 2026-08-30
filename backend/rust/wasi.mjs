// WASI runner for a whole AgentScript program compiled to wasm32-wasip1.
// argv: [node, this, program.wasm, ...argv]; the guest's root maps to the cwd
// the differential gate seeds each run from, so relative file I/O lands there.
import { WASI } from 'node:wasi';
import { readFileSync } from 'node:fs';

const wasmPath = process.argv[2];
const argv = process.argv.slice(3);
const wasi = new WASI({
  version: 'preview1',
  args: ['main', ...argv],
  env: process.env,
  preopens: { '/': process.cwd() },
  returnOnExit: true,
});
const instance = new WebAssembly.Instance(
  new WebAssembly.Module(readFileSync(wasmPath)), wasi.getImportObject());
const code = wasi.start(instance);
process.exit(typeof code === 'number' ? code : 0);
