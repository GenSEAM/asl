import { test } from 'node:test';
import assert from 'node:assert/strict';
import { triageRequest, decideFrontline, allowedShape } from '../bridges/host_bridge.js';

// ==================================================================================================
// 1. DISPATCH TO CANONICAL INTENTS: :dev, :non-dev, :question, :setup, :admin
// ==================================================================================================

test('triageRequest dispatches setup commands to :setup on general workspace (@pcp:d-1a1a)', () => {
  const setupVectors = [
    'git init',
    'init my-new-project',
    'git clone https://github.com/org/repo.git',
    'clone repo',
    'git branch feature-login',
    'branch release-v1',
    'checkout -b my-branch',
    'project.init repo',
    'project.clone my-repo',
    'setup workspace'
  ];

  for (const cmd of setupVectors) {
    const res = triageRequest(cmd, { projectName: 'local' });
    assert.equal(res.kind, 'setup', `expected :setup for '${cmd}'`);
    assert.equal(res.targetProject, 'general', `expected general project for '${cmd}'`);
    assert.equal(res.shape, 'single');
    assert.equal(res.collapsedSingle, false);
  }
});

test('triageRequest dispatches administrative commands to :admin', () => {
  const adminVectors = [
    'voice.preset low-latency',
    'config.set key value',
    'cancel',
    'drop',
    'status',
    'help'
  ];

  for (const cmd of adminVectors) {
    const res = triageRequest(cmd, { projectName: 'alpha' });
    assert.equal(res.kind, 'admin', `expected :admin for '${cmd}'`);
    assert.equal(res.targetProject, 'alpha');
    assert.equal(res.shape, 'single');
  }
});

test('triageRequest dispatches development tasks to :dev', () => {
  const devVectors = [
    'fix the router timeout bug',
    'implement user auth endpoint',
    'refactor storage layer',
    'compile native module',
    'run test suite',
    'почини ошибку в парсере',
    'напиши код для валидации'
  ];

  for (const cmd of devVectors) {
    const res = triageRequest(cmd, { projectName: 'alpha' });
    assert.equal(res.kind, 'dev', `expected :dev for '${cmd}'`);
    assert.equal(res.targetProject, 'alpha');
  }
});

test('triageRequest dispatches single questions to :question', () => {
  const qVectors = [
    'what is the current API version?',
    'how does memory eviction work?',
    'why did the last build fail?',
    'where are the logs stored?',
    'explain the onion middleware architecture'
  ];

  for (const q of qVectors) {
    const res = triageRequest(q, { projectName: 'alpha' });
    assert.equal(res.kind, 'question', `expected :question for '${q}'`);
    assert.equal(res.targetProject, 'alpha');
    assert.equal(res.shape, 'single');
  }
});

// ==================================================================================================
// 2. MULTI-QUERY COLLAPSE INVARIANT (@pcp:d-374e)
// ==================================================================================================

test('multi-aspect question within same workspace collapses to single task frame (@pcp:d-374e)', () => {
  const multiQ = 'what is the current version and how does memory eviction work?';
  const res = triageRequest(multiQ, { projectName: 'alpha' });
  assert.equal(res.kind, 'question');
  assert.equal(res.shape, 'single');
  assert.equal(res.collapsedSingle, true, 'multi-aspect question must collapse to single task frame');
});

test('multi-aspect non-dev errand within same workspace collapses to single task frame (@pcp:d-374e)', () => {
  const multiErrand = 'check weather in Paris and summarize the README note';
  const res = triageRequest(multiErrand, { projectName: 'alpha' });
  assert.equal(res.kind, 'non-dev');
  assert.equal(res.shape, 'single');
  assert.equal(res.collapsedSingle, true, 'multi-aspect errand must collapse to single task frame');
});

test('explicit split request preserves workflow shape instead of collapsing', () => {
  const splitQ = 'what is the current version and how does memory eviction work? create separate tasks';
  const resQ = triageRequest(splitQ, { projectName: 'alpha' });
  assert.equal(resQ.kind, 'question');
  assert.equal(resQ.shape, 'workflow', 'explicit split must preserve workflow shape');
  assert.equal(resQ.collapsedSingle, false);

  const splitDev = 'fix login and refactor auth разбей на задачи';
  const resDev = triageRequest(splitDev, { projectName: 'alpha' });
  assert.equal(resDev.kind, 'dev');
  assert.equal(resDev.shape, 'workflow');
  assert.equal(resDev.collapsedSingle, false);
});

// ==================================================================================================
// 3. PARITY WITH SHRODY FRONTLINE TEST VECTORS (@pcp:d-374e & @pcp:d-1a1a)
// ==================================================================================================

test('allowedShape collapses question with shape group or workflow to single unless spanning distinct projects', () => {
  // Single repo question: collapses group to single
  const singleRepoSteps = [
    { key: 's1', text: 'why does login fail', project: 'shrody' },
    { key: 's2', text: 'why does logout fail', project: 'shrody' },
  ];
  assert.equal(
    allowedShape({ kind: 'question', shape: 'group', steps: singleRepoSteps }),
    'single',
    'same-repo question collapses group to single'
  );

  // Multi-repo question: preserves group across distinct projects
  const crossRepoSteps = [
    { key: 's1', text: 'check api in shrody', project: 'shrody' },
    { key: 's2', text: 'check frontend in agentube', project: 'agentube' },
  ];
  assert.equal(
    allowedShape({ kind: 'question', shape: 'group', steps: crossRepoSteps }),
    'group',
    'cross-project question preserves group'
  );
});

test('decideFrontline collapses non-dev parts into single task unless explicitly requesting separate tasks', () => {
  const projects = [{ name: 'shrody' }];

  // Multi-query non-dev without explicit split keyword collapses to 1 part
  const res = decideFrontline({
    disposition: 'new',
    kind: 'non-dev',
    shape: 'single',
    parts: [
      { disposition: 'new', text: 'weather in Paris' },
      { disposition: 'new', text: 'weather in London' },
      { disposition: 'new', text: 'weather in Tokyo' },
    ],
  }, {
    request: 'find weather in Paris, London and Tokyo',
    projects,
  });

  assert.equal(res.disposition, 'new');
  assert.equal(res.parts.length, 1, 'non-dev multi-query collapses to single task');
  assert.equal(res.parts[0].text, 'find weather in Paris, London and Tokyo');

  // Explicit split instruction preserves separate parts
  const explicit = decideFrontline({
    disposition: 'new',
    kind: 'non-dev',
    shape: 'single',
    parts: [
      { disposition: 'new', text: 'weather in Paris' },
      { disposition: 'new', text: 'weather in London' },
    ],
  }, {
    request: 'find weather in Paris and London, create separate tasks',
    projects,
  });

  assert.equal(explicit.parts.length, 2, 'explicit split preserves all parts');
});

test('decideFrontline setup steps workflow carries setup actions (@pcp:d-1a1a)', () => {
  const projects = [{ name: 'shrody', path: '/repos/shrody' }];
  const via = decideFrontline({
    disposition: 'new',
    kind: 'non-dev',
    shape: 'workflow',
    stop: 'run',
    steps: [
      { key: 's0', text: 'step 1', action: 'project.add' },
      { key: 's1', text: 'step 2', action: 'project.rename' },
    ],
  }, {
    request: 'rename and consolidate',
    projects,
  });

  assert.equal(via.disposition, 'new', 'filed as new work');
  assert.equal(via.shape, 'workflow', 'kept as a workflow');
  const acts = (via.routing?.steps || []).map((s) => s.action);
  assert.deepEqual(new Set(acts), new Set(['project.add', 'project.rename']), 'workflow carries setup actions');
});
