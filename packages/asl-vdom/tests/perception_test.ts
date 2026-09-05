import assert from 'node:assert/strict';
import test from 'node:test';
import {
  fromCDPAXTree,
  fromPlaywrightSnapshot,
  serializeAXTreeToASL,
  downsampleVNode,
  serializeVNodeToASL,
  diffVNodes,
  formatDiffAsASL,
  estimateSavings,
  VNode,
  CDPAXNode
} from '../bridges/ts/perception.js';

test('AXTree: converts CDP Accessibility nodes to hierarchical AXNode with refs', () => {
  const cdpNodes: CDPAXNode[] = [
    {
      nodeId: '1',
      role: { type: 'role', value: 'RootWebArea' },
      name: { type: 'string', value: 'Dashboard' },
      childIds: ['2', '3']
    },
    {
      nodeId: '2',
      role: { type: 'role', value: 'heading' },
      name: { type: 'string', value: 'Overview' },
      childIds: []
    },
    {
      nodeId: '3',
      role: { type: 'role', value: 'button' },
      name: { type: 'string', value: 'Deploy' },
      description: { type: 'string', value: 'Triggers production rollout' },
      disabled: { type: 'boolean', value: false },
      childIds: []
    }
  ];

  const axTree = fromCDPAXTree(cdpNodes);
  assert.ok(axTree);
  assert.equal(axTree.role, 'RootWebArea');
  assert.equal(axTree.name, 'Dashboard');
  assert.equal(axTree.children?.length, 2);

  const button = axTree.children?.[1];
  assert.equal(button?.role, 'button');
  assert.equal(button?.name, 'Deploy');
  assert.equal(button?.description, 'Triggers production rollout');
  assert.ok(button?.ref.startsWith('@e'));

  const aslFrame = serializeAXTreeToASL(axTree);
  assert.ok(aslFrame.includes(':role "button"'));
  assert.ok(aslFrame.includes(':name "Deploy"'));
});

test('AXTree: converts Playwright snapshot to AXNode tree', () => {
  const snapshot = {
    role: 'WebArea',
    name: 'Settings',
    children: [
      {
        role: 'textbox',
        name: 'API Key',
        value: 'sk_live_123',
        focused: true
      }
    ]
  };

  const tree = fromPlaywrightSnapshot(snapshot);
  assert.ok(tree);
  assert.equal(tree.role, 'WebArea');
  const input = tree.children?.[0];
  assert.equal(input?.role, 'textbox');
  assert.equal(input?.name, 'API Key');
  assert.equal(input?.value, 'sk_live_123');
  assert.equal(input?.focused, true);
  assert.equal(input?.ref, '@e1');
});

test('DOM Downsampler: prunes scripts, styles, and redundant wrappers', () => {
  const noisyTree: VNode = {
    type: 'element',
    tag: 'div',
    attrs: {}, // transparent wrapper
    children: [
      {
        type: 'element',
        tag: 'span',
        attrs: {}, // second transparent wrapper
        children: [
          {
            type: 'element',
            tag: 'script',
            attrs: { src: 'bundle.js' },
            children: [{ type: 'text', content: 'alert(1);' }]
          },
          {
            type: 'element',
            tag: 'style',
            attrs: {},
            children: [{ type: 'text', content: '.btn { color: red; }' }]
          },
          {
            type: 'element',
            tag: 'button',
            attrs: {
              class: 'relative flex items-center justify-between p-4 bg-white border border-gray-200 shadow-sm',
              style: 'color: red; margin: 0;',
              'data-reactroot': 'true',
              id: 'deploy-cta',
              'aria-label': 'Trigger Deploy',
              type: 'submit'
            },
            children: [{ type: 'text', content: '  Deploy Now  ' }]
          }
        ]
      }
    ]
  };

  const cleanTree = downsampleVNode(noisyTree);
  assert.ok(cleanTree);
  assert.equal(cleanTree.type, 'element');
  // Both div and span wrappers should be collapsed down to the button
  assert.equal(cleanTree.tag, 'button');
  // Noise attributes stripped
  assert.equal(cleanTree.attrs.class, undefined);
  assert.equal(cleanTree.attrs.style, undefined);
  assert.equal(cleanTree.attrs['data-reactroot'], undefined);
  // Semantic attributes preserved
  assert.equal(cleanTree.attrs.id, 'deploy-cta');
  assert.equal(cleanTree.attrs['aria-label'], 'Trigger Deploy');
  assert.equal(cleanTree.attrs.type, 'submit');
  // Text trimmed
  assert.deepEqual(cleanTree.children, [{ type: 'text', content: 'Deploy Now' }]);

  const asl = serializeVNodeToASL(cleanTree);
  assert.ok(asl.startsWith('(button :id "deploy-cta"'));
  assert.ok(asl.includes('"Deploy Now"'));
});

test('Incremental Diff: computes atomic mutations and emits compact diff frame', () => {
  const oldTree: VNode = {
    type: 'element',
    tag: 'section',
    attrs: { id: 'user-profile' },
    children: [
      {
        type: 'element',
        tag: 'h2',
        attrs: {},
        children: [{ type: 'text', content: 'Alice' }]
      }
    ]
  };

  const newTree: VNode = {
    type: 'element',
    tag: 'section',
    attrs: { id: 'user-profile', 'data-status': 'active' },
    children: [
      {
        type: 'element',
        tag: 'h2',
        attrs: {},
        children: [{ type: 'text', content: 'Alice Cooper' }]
      },
      {
        type: 'element',
        tag: 'badge',
        attrs: { id: 'verified' },
        children: [{ type: 'text', content: 'Pro' }]
      }
    ]
  };

  const diff = diffVNodes(oldTree, newTree, '/users/alice');
  assert.equal(diff.route, '/users/alice');
  assert.equal(diff.added.length, 1);
  assert.ok(diff.mutated.length >= 1);

  const diffFrame = formatDiffAsASL(diff);
  assert.ok(diffFrame.startsWith('(! dom/diff :route "/users/alice"'));
  assert.ok(diffFrame.includes(':added ['));
  assert.ok(diffFrame.includes('badge'));
});

test('Token Economy: achieves >= 75% byte / token reduction over raw HTML', () => {
  const rawHTML = `
    <div class="min-h-screen bg-gray-50 flex flex-col justify-center py-12 sm:px-6 lg:px-8">
      <div class="sm:mx-auto sm:w-full sm:max-w-md">
        <script src="/static/analytics.js"></script>
        <style>.btn-primary { background-color: #3b82f6; }</style>
        <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900 tracking-tight" id="login-title">
          Sign in to your account
        </h2>
      </div>
      <div class="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
        <div class="bg-white py-8 px-4 shadow sm:rounded-lg sm:px-10">
          <form class="space-y-6" id="login-form" action="/login" method="POST">
            <div>
              <label for="email" class="block text-sm font-medium text-gray-700">Email address</label>
              <input id="email" name="email" type="email" autocomplete="email" required placeholder="user@example.com" class="appearance-none block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500" />
            </div>
            <div>
              <button type="submit" id="submit-btn" class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2">
                Sign in
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  `;

  // Emulate downsampled tree representing the functional elements of the form
  const downsampled: VNode = {
    type: 'element',
    tag: 'form',
    attrs: { id: 'login-form' },
    children: [
      {
        type: 'element',
        tag: 'h2',
        attrs: { id: 'login-title' },
        children: [{ type: 'text', content: 'Sign in to your account' }]
      },
      {
        type: 'element',
        tag: 'input',
        attrs: { id: 'email', name: 'email', type: 'email', placeholder: 'user@example.com' },
        children: []
      },
      {
        type: 'element',
        tag: 'button',
        attrs: { id: 'submit-btn', type: 'submit' },
        children: [{ type: 'text', content: 'Sign in' }]
      }
    ]
  };

  const asl = serializeVNodeToASL(downsampled);
  const metrics = estimateSavings(rawHTML, asl);

  assert.ok(
    metrics.savingsPercent >= 75,
    `Savings must be >= 75%, got ${metrics.savingsPercent}% (raw: ${metrics.rawBytes} bytes, asl: ${metrics.compressedBytes} bytes)`
  );
});
