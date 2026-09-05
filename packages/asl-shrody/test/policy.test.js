import { test } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import os from 'node:os';
import { checkPermission } from '../bridges/host_bridge.js';

const mockManifest = {
  workspaceRoot: '/Users/test/workspace/repo',
  worktreeRoots: [
    '/Users/test/workspace/repo/.worktrees/feature-auth',
    '/Users/test/workspace/repo/.worktrees/fix-bug-42'
  ],
  tempDir: '/tmp/shrody/session-1234',
  readOnly: false,
};

test('Workspace root paths are allowed silently without prompting', () => {
  const res1 = checkPermission('read', '/Users/test/workspace/repo/src/index.js', mockManifest);
  assert.equal(res1.allowed, true, 'workspace read should be allowed');
  assert.equal(res1.silent, true, 'workspace read must be silent (zero user prompt)');
  assert.equal(res1.code, 'ALLOW_SILENT');

  const res2 = checkPermission('write', '/Users/test/workspace/repo/src/output.txt', mockManifest);
  assert.equal(res2.allowed, true, 'workspace write should be allowed');
  assert.equal(res2.silent, true, 'workspace write must be silent');
  assert.equal(res2.code, 'ALLOW_SILENT');
});

test('Worktree roots are allowed silently without prompting', () => {
  const wtPath1 = '/Users/test/workspace/repo/.worktrees/feature-auth/lib/auth.js';
  const res1 = checkPermission('read', wtPath1, mockManifest);
  assert.equal(res1.allowed, true);
  assert.equal(res1.silent, true);
  assert.equal(res1.code, 'ALLOW_SILENT');

  const wtPath2 = '/Users/test/workspace/repo/.worktrees/fix-bug-42/patch.diff';
  const res2 = checkPermission('write', wtPath2, mockManifest);
  assert.equal(res2.allowed, true);
  assert.equal(res2.silent, true);
  assert.equal(res2.code, 'ALLOW_SILENT');
});

test('Sandbox temp directory is allowed silently without prompting', () => {
  const tempPath = '/tmp/shrody/session-1234/scratch.json';
  const res = checkPermission('write', tempPath, mockManifest);
  assert.equal(res.allowed, true);
  assert.equal(res.silent, true);
  assert.equal(res.code, 'ALLOW_SILENT');
});

test('Directory traversal attempts (../) are strictly denied as sandbox escapes', () => {
  const traversalVectors = [
    '/Users/test/workspace/repo/../../../etc/passwd',
    '../secret.env',
    '../../etc/shadow',
    '/Users/test/workspace/repo/subdir/../../..',
    '..',
    'subdir/../../escaped.txt'
  ];

  for (const v of traversalVectors) {
    const res = checkPermission('read', v, mockManifest);
    assert.equal(res.allowed, false, `traversal vector '${v}' must be disallowed`);
    assert.equal(res.code, 'DENY_STRICT');
    assert.match(res.reason, /sandbox escape|traversal/i);
  }
});

test('Sensitive system paths (/etc, ~/.ssh, /root) are strictly denied', () => {
  const dangerousPaths = [
    '/etc/hosts',
    '/etc/ssl/certs',
    '/root/.bashrc',
    '~/.ssh/id_rsa',
    path.join(os.homedir(), '.ssh', 'authorized_keys'),
    '/sys/kernel/security',
    '/proc/version'
  ];

  for (const p of dangerousPaths) {
    const res = checkPermission('read', p, mockManifest);
    assert.equal(res.allowed, false, `system path '${p}' must be disallowed`);
    assert.equal(res.code, 'DENY_STRICT');
    assert.match(res.reason, /sandbox escape|system path/i);
  }
});

test('Paths outside manifest boundaries are denied without escape violation', () => {
  const outsidePath = '/Users/test/other-unauthorized-project/config.yaml';
  const res = checkPermission('read', outsidePath, mockManifest);
  assert.equal(res.allowed, false);
  assert.equal(res.code, 'DENY_UNAUTHORIZED');
});

test('Read-only manifest strictly forbids write operations', () => {
  const roManifest = { ...mockManifest, readOnly: true };
  const writeRes = checkPermission('write', '/Users/test/workspace/repo/src/index.js', roManifest);
  assert.equal(writeRes.allowed, false);
  assert.equal(writeRes.code, 'DENY_READONLY');

  const readRes = checkPermission('read', '/Users/test/workspace/repo/src/index.js', roManifest);
  assert.equal(readRes.allowed, true);
  assert.equal(readRes.silent, true);
});
