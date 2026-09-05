import test from 'node:test';
import assert from 'node:assert/strict';

import {
  extractAXTree,
  serializeAXNodeToASL,
  elementToVNode,
  serializeVNodeToASL,
  formatStandardASL,
  extractPageContext,
  resolveElement,
  performPageAction,
  resetRefRegistry,
  elementRegistry,
  inferRole,
  getAccessibleName
} from '../src/content.js';

import {
  WasiPreview1Runner,
  executeWasiPreview1,
  parseA2AFrame,
  serializeA2AFrame,
  A2AMeshBus,
  handleBackgroundMessage
} from '../src/background.js';

// ============================================================================
// Synthetic DOM Fixture for Node Test Environment
// ============================================================================

class MockNode {
  public nodeType: number;
  public parentNode: MockElement | null = null;

  constructor(nodeType: number) {
    this.nodeType = nodeType;
  }
}

class MockTextNode extends MockNode {
  public textContent: string;

  constructor(text: string) {
    super(3);
    this.textContent = text;
  }
}

class MockElement extends MockNode {
  public tagName: string;
  public id: string = '';
  public className: string = '';
  public attributes: Map<string, string> = new Map();
  public children: MockElement[] = [];
  public childNodes: (MockElement | MockTextNode)[] = [];
  public ownerDocument?: MockDocument;
  public style: Record<string, string> = { outline: '' };
  public value: string = '';
  public disabled: boolean = false;
  public clickCount: number = 0;
  public focused: boolean = false;
  public scrolledIntoView: boolean = false;
  public eventListeners: Map<string, Array<(e: any) => void>> = new Map();

  constructor(tagName: string, attrs: Record<string, string> = {}) {
    super(1);
    this.tagName = tagName.toUpperCase();
    for (const [k, v] of Object.entries(attrs)) {
      this.setAttribute(k, v);
    }
  }

  public getAttribute(name: string): string | null {
    return this.attributes.get(name.toLowerCase()) ?? null;
  }

  public setAttribute(name: string, value: string): void {
    const lower = name.toLowerCase();
    this.attributes.set(lower, value);
    if (lower === 'id') this.id = value;
    if (lower === 'class') this.className = value;
    if (lower === 'disabled') this.disabled = true;
    if (lower === 'value') this.value = value;
  }

  public hasAttribute(name: string): boolean {
    return this.attributes.has(name.toLowerCase());
  }

  public getAttributeNames(): string[] {
    return Array.from(this.attributes.keys());
  }

  public appendChild<T extends MockNode>(child: T): T {
    child.parentNode = this;
    if (child instanceof MockElement) {
      this.children.push(child);
      child.ownerDocument = this.ownerDocument;
    }
    this.childNodes.push(child as any);
    return child;
  }

  public get textContent(): string {
    let result = '';
    for (const child of this.childNodes) {
      if (child instanceof MockTextNode) {
        result += child.textContent;
      } else if (child instanceof MockElement) {
        result += child.textContent;
      }
    }
    return result;
  }

  public set textContent(val: string) {
    this.childNodes = [new MockTextNode(val)];
    this.children = [];
  }

  public get innerText(): string {
    return this.textContent;
  }

  public get outerHTML(): string {
    const tag = this.tagName.toLowerCase();
    const attrsStr = Array.from(this.attributes.entries())
      .map(([k, v]) => ` ${k}="${v}"`)
      .join('');
    let inner = '';
    for (const child of this.childNodes) {
      if (child instanceof MockTextNode) {
        inner += child.textContent;
      } else if (child instanceof MockElement) {
        inner += child.outerHTML;
      }
    }
    return `<${tag}${attrsStr}>${inner}</${tag}>`;
  }

  public querySelector(selector: string): MockElement | null {
    const all = this.querySelectorAll(selector);
    return all.length > 0 ? all[0] : null;
  }

  public querySelectorAll(selector: string): MockElement[] {
    const results: MockElement[] = [];
    const sel = selector.trim();

    const matches = (el: MockElement): boolean => {
      if (sel.startsWith('#')) {
        return el.id === sel.slice(1);
      }
      if (sel.startsWith('.')) {
        return el.className.split(/\s+/).includes(sel.slice(1));
      }
      if (sel.startsWith('[') && sel.endsWith(']')) {
        const inner = sel.slice(1, -1);
        if (inner.includes('=')) {
          const [attr, val] = inner.split('=').map(s => s.trim().replace(/^["']|["']$/g, ''));
          return el.getAttribute(attr) === val;
        }
        return el.hasAttribute(inner);
      }
      if (sel.includes(',')) {
        return sel.split(',').some(part => el.querySelector(part.trim()) !== null || matchesSelector(el, part.trim()));
      }
      return el.tagName.toLowerCase() === sel.toLowerCase();
    };

    const matchesSelector = (el: MockElement, s: string): boolean => {
      if (s.startsWith('#')) return el.id === s.slice(1);
      if (s.startsWith('.')) return el.className.split(/\s+/).includes(s.slice(1));
      return el.tagName.toLowerCase() === s.toLowerCase();
    };

    const walk = (el: MockElement) => {
      for (const child of el.children) {
        if (matches(child)) {
          results.push(child);
        }
        walk(child);
      }
    };

    walk(this);
    return results;
  }

  public addEventListener(event: string, callback: (e: any) => void): void {
    const list = this.eventListeners.get(event) || [];
    list.push(callback);
    this.eventListeners.set(event, list);
  }

  public dispatchEvent(event: any): boolean {
    const eventType = typeof event === 'string' ? event : event.type;
    const list = this.eventListeners.get(eventType) || [];
    for (const cb of list) {
      cb(event);
    }
    return true;
  }

  public click(): void {
    this.clickCount++;
    this.dispatchEvent({ type: 'click' });
  }

  public focus(): void {
    this.focused = true;
    this.dispatchEvent({ type: 'focus' });
  }

  public scrollIntoView(): void {
    this.scrolledIntoView = true;
  }
}

class MockDocument {
  public title: string = 'AgentScript Showcase Application';
  public body: MockElement;
  public documentElement: MockElement;

  constructor() {
    this.documentElement = new MockElement('html');
    this.documentElement.ownerDocument = this;
    this.body = new MockElement('body');
    this.body.ownerDocument = this;
    this.documentElement.appendChild(this.body);
  }

  public getElementById(id: string): MockElement | null {
    return this.documentElement.querySelector(`#${id}`);
  }

  public querySelector(selector: string): MockElement | null {
    return this.documentElement.querySelector(selector);
  }

  public querySelectorAll(selector: string): MockElement[] {
    return this.documentElement.querySelectorAll(selector);
  }
}

function buildSyntheticDOM(): MockDocument {
  const doc = new MockDocument();
  const body = doc.body;

  // Header with nav and links
  const header = new MockElement('header', { class: 'navbar bg-slate-900 border-b p-4' });
  const nav = new MockElement('nav', { 'aria-label': 'Main Navigation' });
  const linkHome = new MockElement('a', { href: '/', class: 'nav-link' });
  linkHome.textContent = 'Home';
  const linkDocs = new MockElement('a', { href: '/docs', class: 'nav-link' });
  linkDocs.textContent = 'Documentation';
  nav.appendChild(linkHome);
  nav.appendChild(linkDocs);
  header.appendChild(nav);
  body.appendChild(header);

  // Main container
  const main = new MockElement('main', { id: 'content', class: 'container mx-auto p-8' });
  const article = new MockElement('article', { class: 'card shadow-xl rounded-2xl p-6' });

  const h1 = new MockElement('h1', { class: 'text-3xl font-bold tracking-tight' });
  h1.textContent = 'ASL In-Browser Autonomous Agent';
  article.appendChild(h1);

  const p = new MockElement('p', { class: 'text-slate-400 mt-2 leading-relaxed' });
  p.textContent = 'Autonomous multi-agent copilot utilizing dual perception and zero-leak sandboxing.';
  article.appendChild(p);

  // Form elements
  const form = new MockElement('form', { id: 'search-form', class: 'flex gap-4 mt-6' });
  const input = new MockElement('input', {
    id: 'query-input',
    type: 'text',
    placeholder: 'Search modules or schemas...',
    class: 'input input-bordered px-4 py-2'
  });
  const submitBtn = new MockElement('button', {
    id: 'btn-search',
    type: 'button',
    role: 'button',
    'aria-label': 'Search Query',
    class: 'btn btn-primary bg-purple-600 text-white font-semibold px-4 py-2 rounded-xl'
  });
  submitBtn.textContent = 'Search';

  const resetBtn = new MockElement('button', {
    id: 'btn-reset',
    type: 'button',
    class: 'btn btn-secondary text-slate-300'
  });
  resetBtn.textContent = 'Reset';

  form.appendChild(input);
  form.appendChild(submitBtn);
  form.appendChild(resetBtn);
  article.appendChild(form);

  // Repeated list items to test compression and downsampling
  const ul = new MockElement('ul', { class: 'list-disc pl-5 mt-4' });
  for (let i = 1; i <= 6; i++) {
    const li = new MockElement('li', { class: 'py-1 text-sm' });
    li.textContent = `Module Item ${i}: asl-core v${i}.0`;
    ul.appendChild(li);
  }
  article.appendChild(ul);

  // Ignored tags & bloat: script, style, and SVG icons that raw outerHTML contains
  const script = new MockElement('script');
  script.textContent = `
    window.__ASL_INITIAL_STATE__ = {
      user: { id: "u_98492842", role: "admin", permissions: ["deploy", "audit", "transcode"], preferences: { theme: "dark", telemetry: true } },
      session: { token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...", expires: 1757039200 },
      routes: [ { path: "/", component: "Dashboard" }, { path: "/docs", component: "DocsView" }, { path: "/settings", component: "SettingsModal" } ]
    };
    (function initAnalytics(){ console.log("Initializing telemetry trackers..."); })();
  `;

  const style = new MockElement('style');
  style.textContent = `
    @tailwind base; @tailwind components; @tailwind utilities;
    :root { --primary-rgb: 147, 51, 234; --signal-rgb: 56, 189, 248; }
    .card { background: rgba(15, 23, 42, 0.8); backdrop-filter: blur(16px); border: 1px solid rgba(255,255,255,0.1); border-radius: 1rem; box-shadow: 0 20px 25px -5px rgb(0 0 0 / 0.1); }
    .btn-primary { background: linear-gradient(135deg, #9333ea, #6366f1); transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1); }
    .btn-primary:hover { transform: translateY(-1px); box-shadow: 0 10px 15px -3px rgba(147, 51, 234, 0.3); }
    .input-bordered { border-color: rgba(255, 255, 255, 0.2); background: rgba(0, 0, 0, 0.2); }
  `;

  const svgIcon = new MockElement('svg', {
    xmlns: 'http://www.w3.org/2000/svg',
    viewBox: '0 0 24 24',
    fill: 'currentColor',
    class: 'w-6 h-6 text-purple-400'
  });
  const svgPath = new MockElement('path', {
    d: 'M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5'
  });
  svgIcon.appendChild(svgPath);
  header.appendChild(svgIcon);

  body.appendChild(script);
  body.appendChild(style);

  // Footer with copyright & telemetry
  const footer = new MockElement('footer', { class: 'footer mt-12 py-8 border-t border-slate-800 text-slate-500 text-xs text-center' });
  const footerText = new MockElement('p');
  footerText.textContent = 'AgentScript Autonomous Web Runtime © 2026 GenSEAM. Licensed under MIT.';
  footer.appendChild(footerText);
  body.appendChild(footer);

  main.appendChild(article);
  body.appendChild(main);

  return doc;
}

// ============================================================================
// Unit Tests: Dual Perception & AXTree Extraction
// ============================================================================

test('1. AXTree extraction extracts semantic hierarchy and assigns @eN refs', () => {
  resetRefRegistry();
  const doc = buildSyntheticDOM();
  const axTree = extractAXTree(doc.body as any, doc as any);

  assert.ok(axTree, 'AXTree must be extracted from synthetic DOM');
  assert.equal(axTree.role, 'generic');

  // Verify interactive elements received @eN refs in registry
  assert.ok(elementRegistry.size >= 4, `Expected at least 4 registered interactive elements, got ${elementRegistry.size}`);
  assert.ok(elementRegistry.has('@e1'), 'Expected @e1 to be registered');
  assert.ok(elementRegistry.has('@e2'), 'Expected @e2 to be registered');

  // Check roles inferred
  const searchBtn = doc.getElementById('btn-search');
  assert.ok(searchBtn);
  assert.equal(inferRole(searchBtn as any), 'button');

  const queryInput = doc.getElementById('query-input');
  assert.ok(queryInput);
  assert.equal(inferRole(queryInput as any), 'textbox');
  assert.equal(getAccessibleName(queryInput as any, doc as any), 'Search modules or schemas...');

  // Serialize to ASL
  const aslStr = serializeAXNodeToASL(axTree);
  assert.ok(aslStr.startsWith('(:ax-node'), 'Serialized ASL frame should begin with (:ax-node');
  assert.ok(aslStr.includes(':role "button"'), 'ASL frame must include button role');
  assert.ok(aslStr.includes(':role "textbox"'), 'ASL frame must include textbox role');
  assert.ok(aslStr.includes(':ref "@e'), 'ASL frame must include @eN refs');
});

// ============================================================================
// Unit Tests: Standard ASL Formatting (@pcp:d-1eed)
// ============================================================================

test('2. Standard ASL format strictly uses dfs, :f, Str, I64, :d, :x', () => {
  const asl = formatStandardASL({
    url: 'https://asl.dev/test',
    title: 'Test Suite',
    elementsCount: 5,
    savingsPercent: 82,
    axTreeAsl: '(:ax-node :role "button" :name "Go" :ref "@e1")'
  });

  // Verify Standard ASL required identifiers
  assert.ok(asl.includes('dfs PageContext'), 'Must use dfs for schema definition');
  assert.ok(asl.includes('(:f url Str)'), 'Must use :f and Str');
  assert.ok(asl.includes('(:f title Str)'), 'Must use :f and Str');
  assert.ok(asl.includes('(:f elements_count I64)'), 'Must use :f and I64');
  assert.ok(asl.includes('(:f savings_pct I64)'), 'Must use :f and I64');
  assert.ok(asl.includes(':d "Extracted DOM context for Test Suite"'), 'Must use :d for doc');
  assert.ok(asl.includes(':x [PageContext PageAction AXNodeFrame]'), 'Must use :x for export');
});

// ============================================================================
// Unit Tests: Token Economy Verification (>= 70% Reduction vs outerHTML)
// ============================================================================

test('3. Token economy verifies >= 70% reduction vs raw outerHTML', () => {
  const doc = buildSyntheticDOM();
  const context = extractPageContext(doc as any);

  assert.ok(context.rawOuterHtmlLength > 500, `Raw HTML should be substantial, got ${context.rawOuterHtmlLength}`);
  assert.ok(context.compressedLength < context.rawOuterHtmlLength, 'Compressed ASL length should be smaller');

  // Strict token economy threshold assertion
  assert.ok(
    context.tokenSavingsPercent >= 70,
    `Token savings (${context.tokenSavingsPercent}%) must be >= 70% vs raw outerHTML`
  );

  // Context structure verification
  assert.equal(context.title, 'AgentScript Showcase Application');
  assert.ok(context.interactiveElements.length >= 4);
  assert.ok(context.aslSExpression.includes('(module browser/page'));
});

// ============================================================================
// Unit Tests: Page Action Dispatching & Ref / Selector Resolution
// ============================================================================

test('4. Page action dispatching resolves by both @eN ref and selector', () => {
  const doc = buildSyntheticDOM();
  extractPageContext(doc as any);

  const searchBtn = doc.getElementById('btn-search');
  assert.ok(searchBtn);
  const btnRef = searchBtn.getAttribute('data-asl-ref');
  assert.ok(btnRef, 'Search button should have data-asl-ref assigned');

  // 1. Resolve & Click by @eN ref
  const clickByRefResult = performPageAction('CLICK', { ref: btnRef }, doc as any);
  assert.equal(clickByRefResult.ok, true);
  assert.equal(searchBtn.clickCount, 1, 'Button click count should be 1 after click by ref');

  // 2. Resolve & Click by CSS selector
  const clickBySelectorResult = performPageAction('CLICK', { selector: '#btn-search' }, doc as any);
  assert.equal(clickBySelectorResult.ok, true);
  assert.equal(searchBtn.clickCount, 2, 'Button click count should be 2 after click by selector');

  // 3. Resolve & Fill by @eN ref
  const inputEl = doc.getElementById('query-input');
  assert.ok(inputEl);
  const inputRef = inputEl.getAttribute('data-asl-ref');
  assert.ok(inputRef, 'Input should have data-asl-ref assigned');

  let inputEventFired = false;
  inputEl.addEventListener('input', () => { inputEventFired = true; });

  const fillByRefResult = performPageAction('FILL', { ref: inputRef, text: 'AgentScript/VDOM' }, doc as any);
  assert.equal(fillByRefResult.ok, true);
  assert.equal(inputEl.value, 'AgentScript/VDOM');
  assert.equal(inputEventFired, true, 'Input event must be dispatched upon fill');

  // 4. Resolve & Fill by selector
  const fillBySelectorResult = performPageAction('FILL', { selector: '#query-input', text: 'wasi-preview1' }, doc as any);
  assert.equal(fillBySelectorResult.ok, true);
  assert.equal(inputEl.value, 'wasi-preview1');

  // 5. Scroll action
  const scrollResult = performPageAction('SCROLL', { target: '#content' }, doc as any);
  assert.equal(scrollResult.ok, true);

  // 6. Error handling for non-existent target
  const invalidResult = performPageAction('CLICK', { ref: '@e99999' }, doc as any);
  assert.equal(invalidResult.ok, false);
  assert.ok(invalidResult.message.includes('not found'));

  // 7. Error handling for unknown action
  const unknownResult = performPageAction('DRAG_AND_DROP', { ref: btnRef }, doc as any);
  assert.equal(unknownResult.ok, false);
  assert.ok(unknownResult.message.includes('Unknown action'));
});

// ============================================================================
// Unit Tests: In-Memory WASI Preview1 Execution
// ============================================================================

test('5. In-memory WASI preview1 execution executes simulated and real WebAssembly binaries', async () => {
  // Test fallback simulated execution
  const simResult = await executeWasiPreview1({});
  assert.equal(simResult.success, true);
  assert.equal(simResult.exitCode, 0);
  assert.ok(simResult.stdout.includes('Hello from ASL WebAssembly Browser Worker'));
  assert.ok(simResult.durationMs >= 0);

  // Test real 36-byte valid WebAssembly module exporting _start
  const wasmBytes = new Uint8Array([
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, // \0asm v1
    0x01, 0x04, 0x01, 0x60, 0x00, 0x00,             // Type: () -> ()
    0x03, 0x02, 0x01, 0x00,                         // Func: 0
    0x07, 0x0a, 0x01, 0x06, 0x5f, 0x73, 0x74, 0x61, 0x72, 0x74, 0x00, 0x00, // Export "_start"
    0x0a, 0x04, 0x01, 0x02, 0x00, 0x0b              // Code: nop, end
  ]);

  const runner = new WasiPreview1Runner({ args: ['asl', 'eval'] });
  const realResult = await runner.execute(wasmBytes);
  assert.equal(realResult.success, true);
  assert.equal(realResult.exitCode, 0);
  assert.ok(realResult.durationMs >= 0);
});

// ============================================================================
// Unit Tests: A2A Mesh Bus Connectivity & Frame Serialization
// ============================================================================

test('6. A2A Mesh Bus parses, serializes, and routes structured agent frames', async () => {
  const meshBus = new A2AMeshBus();
  await meshBus.connect('ws://127.0.0.1:9090/asl-mesh');
  assert.equal(meshBus.isConnected(), true);

  // Parse Query Frame
  const queryFrame = parseA2AFrame('(? ui/click :ref "@e1" :timeout 2000)');
  assert.equal(queryFrame.type, 'query');
  assert.equal(queryFrame.action, 'ui/click');
  assert.equal(queryFrame.params?.ref, '@e1');
  assert.equal(queryFrame.params?.timeout, 2000);

  // Parse Ack Frame
  const ackFrame = parseA2AFrame('(! ui/ack :status :ok :ref "@e1")');
  assert.equal(ackFrame.type, 'ack');
  assert.equal(ackFrame.action, 'ui/ack');
  assert.equal(ackFrame.params?.status, ':ok');

  // Parse Error Frame
  const errFrame = parseA2AFrame('(:error :code 404 :msg "Element not found")');
  assert.equal(errFrame.type, 'error');
  assert.equal(errFrame.params?.code, 404);

  // Serialize Frame to ASL
  const serializedQuery = serializeA2AFrame(queryFrame);
  assert.ok(serializedQuery.startsWith('(? ui/click'));
  assert.ok(serializedQuery.includes(':ref @e1'));

  // Subscribe & Receive Frames
  let receivedFrame: any = null;
  const unsubscribe = meshBus.subscribe((frame) => {
    receivedFrame = frame;
  });

  meshBus.send(queryFrame);
  assert.ok(receivedFrame);
  assert.equal(receivedFrame.action, 'ui/click');

  unsubscribe();
  meshBus.disconnect();
  assert.equal(meshBus.isConnected(), false);
});

// ============================================================================
// Unit Tests: Background Service Worker Message Routing
// ============================================================================

test('7. Background service worker message router handles PING, EVAL_WASM, and A2A', async () => {
  // PING
  const pingRes = await handleBackgroundMessage({ type: 'PING' });
  assert.equal(pingRes.status, 'PONG');
  assert.equal(pingRes.runtime, 'ASL-WASI-Worker-1.0');

  // EVAL_WASM
  const wasmRes = await handleBackgroundMessage({ type: 'EVAL_WASM' });
  assert.equal(wasmRes.success, true);
  assert.equal(wasmRes.exitCode, 0);

  // A2A Connect & Send
  const connRes = await handleBackgroundMessage({ type: 'A2A_CONNECT', endpoint: 'ws://mesh.asl:8080' });
  assert.equal(connRes.ok, true);
  assert.equal(connRes.connected, true);

  const sendRes = await handleBackgroundMessage({
    type: 'A2A_SEND',
    frame: '(? ui/fill :ref "@e2" :text "hello")'
  });
  assert.equal(sendRes.ok, true);
  assert.equal(sendRes.sent.action, 'ui/fill');

  // Unknown message
  const unknownRes = await handleBackgroundMessage({ type: 'NON_EXISTENT' });
  assert.equal(unknownRes.ok, false);
});
