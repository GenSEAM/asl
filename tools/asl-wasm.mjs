#!/usr/bin/env node
import { runWasm } from '../backend/ts/wasm_runner.js';
import { readFileSync } from 'fs';

const args = process.argv.slice(2);
if (args.length === 0) {
  console.error("Usage: asl-wasm <file.wasm> [args...]");
  process.exit(1);
}

const wasmFile = args[0];
const wasmArgs = args.slice(1);

try {
  const bytes = readFileSync(wasmFile);
  const result = await runWasm(bytes, { args: [wasmFile, ...wasmArgs] });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  process.exit(result.exitCode);
} catch (err) {
  console.error(`asl-wasm: ${err.message}`);
  process.exit(1);
}
