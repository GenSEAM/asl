/**
 * SkyLoom Unified Test Runner
 * Executes all test suites in sequence and reports aggregate results.
 */

import { spawnSync } from 'child_process';
import * as path from 'path';

const suites = [
  'codec_test.js',
  'handoff_codec_test.js',
  'scoping_test.js',
  'mesh_test.js',
  'negotiation_test.js',
  'resilience_test.js',
  'mcp_test.js',
];

console.log('====================================================');
console.log('       SkyLoom Unified Test Suite Runner            ');
console.log('====================================================\n');

let failed = 0;

for (const suite of suites) {
  const suitePath = path.resolve(process.cwd(), 'dist', 'tests', suite);
  console.log(`\n▶ Running ${suite}...`);
  const res = spawnSync(process.execPath, [suitePath], { stdio: 'inherit' });
  if (res.status !== 0) {
    console.error(`✗ ${suite} FAILED with status ${res.status}`);
    failed++;
  } else {
    console.log(`✓ ${suite} PASSED`);
  }
}

console.log('\n====================================================');
if (failed === 0) {
  console.log('  ALL 5 SKYLOOM TEST SUITES PASSED CLEANLY (100%)    ');
  console.log('====================================================');
  process.exit(0);
} else {
  console.error(`  ${failed} SUITE(S) FAILED                        `);
  console.log('====================================================');
  process.exit(1);
}
