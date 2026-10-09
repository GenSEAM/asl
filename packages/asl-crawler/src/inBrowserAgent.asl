(module aslCrawler/inBrowserAgent
  :x [InBrowserAgentConfig makeDefaultAgentConfig generateStealthEvasionScript generateDomDistillerScript generateKineticExecutorScript generateBehavioralNoiseScript generateInBrowserAgentBootstrap formatAgentStatusAsn]
  :i [(asl-text/escape :a esc) (asl-foreign/block :a f)])

(schema InBrowserAgentConfig
  (:f agentId Str)
  (:f version Str)
  (:f gatewayUrl Str)
  (:f stealthEvasions Bool)
  (:f kineticsEnabled Bool)
  (:f behavioralNoise Bool)
  (:f maxSnapshotNodes I64))

fn makeDefaultAgentConfig -> InBrowserAgentConfig
  (InBrowserAgentConfig
    :agentId "asl-in-page-agent"
    :version "1.0.0"
    :gatewayUrl "http://127.0.0.1:8765"
    :stealthEvasions true
    :kineticsEnabled true
    :behavioralNoise true
    :maxSnapshotNodes 100)

fn generateStealthEvasionScript -> Str
  (str (f/js "// === ASL In-Browser Stealth Evasions ===
(function() {
  try {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined, configurable: true });
    Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'], configurable: true });
    Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5], configurable: true });
    window.chrome = window.chrome || { runtime: {}, loadTimes: function() {}, csi: function() {}, app: {} };
    const origGetParameter = WebGLRenderingContext.prototype.getParameter;
    WebGLRenderingContext.prototype.getParameter = function(parameter) {
      if (parameter === 37445) return 'Apple Inc.';
      if (parameter === 37446) return 'Apple GPU';
      return origGetParameter.apply(this, arguments);
    };
    delete window.cdc_adoQpoasnfa76pfcZLmcfl_Array;
    delete window.__webdriver_evaluate;
    delete window.__selenium_evaluate;
  } catch(e) {}
})();") "\n")

fn generateDomDistillerScript maxNodes: I64 -> Str
  (str (f/js (str "// === ASL In-Situ DOM Distillation ===
function distillDomToAsn() {
  function esc(s) { return String(s || '').replace(/\\\\/g, '\\\\\\\\').replace(/\"/g, '\\\\\"').replace(/\\n/g, '\\\\n'); }
  const title = esc(document.title || 'Untitled');
  const url = esc(window.location.href);
  const selectors = 'h1, h2, h3, h4, h5, h6, p, button, a, input, textarea, select, table, video, [role=\"button\"]';
  const elements = Array.from(document.querySelectorAll(selectors));
  const nodes = [];
  let count = 0;
  for (const el of elements) {
    if (count >= " (f/jsNum maxNodes) ") break;
    if (!el.offsetParent && el.tagName !== 'BODY') continue;
    const tag = el.tagName.toLowerCase();
    let text = (el.innerText || el.value || el.getAttribute('aria-label') || el.getAttribute('placeholder') || '').trim();
    if (text.length > 200) text = text.slice(0, 200) + '...';
    if (!text && tag !== 'input' && tag !== 'video') continue;
    let sel = tag;
    if (el.id) sel += '#' + el.id;
    else if (el.className && typeof el.className === 'string') sel += '.' + el.className.trim().split(/\\s+/)[0];
    nodes.push('(:node :tag \"' + tag + '\" :text \"' + esc(text) + '\" :selector \"' + esc(sel) + '\")');
    count++;
  }
  return '(:pageSnapshot\\n  :url \"' + url + '\"\\n  :title \"' + title + '\"\\n  :nodesCount ' + nodes.length + '\\n  :nodes [' + nodes.join(' ') + ']\\n  :status :ok)';
}")) "\n")

fn generateKineticExecutorScript -> Str
  (str (f/js "// === ASL In-Situ Human Kinetics ===
function executeKineticClick(targetSelector) {
  const el = document.querySelector(targetSelector);
  if (!el) return { status: 'failed', error: 'Element not found: ' + targetSelector };
  const rect = el.getBoundingClientRect();
  const cx = rect.left + rect.width / 2;
  const cy = rect.top + rect.height / 2;
  const evInit = { bubbles: true, cancelable: true, clientX: cx, clientY: cy };
  el.dispatchEvent(new MouseEvent('mouseover', evInit));
  el.dispatchEvent(new MouseEvent('mousedown', evInit));
  el.dispatchEvent(new MouseEvent('mouseup', evInit));
  el.dispatchEvent(new MouseEvent('click', evInit));
  if (typeof el.focus === 'function') el.focus();
  return { status: 'ok', target: targetSelector };
}
function executeKineticType(targetSelector, text) {
  const el = document.querySelector(targetSelector);
  if (!el) return { status: 'failed', error: 'Element not found: ' + targetSelector };
  if (typeof el.focus === 'function') el.focus();
  el.value = (el.value || '') + text;
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  return { status: 'ok', textLength: text.length };
}
function executeKineticScroll(pixels, direction) {
  const dy = direction === 'up' ? -pixels : pixels;
  window.scrollBy({ top: dy, left: 0, behavior: 'smooth' });
  return { status: 'ok', scrolled: pixels, direction: direction };
}") "\n")

fn generateBehavioralNoiseScript -> Str
  (str (f/js "// === ASL Behavioral Entropy & Noise ===
function executeCursorTwitch(cx, cy) {
  const dx = Math.floor(Math.random() * 5) - 2;
  const dy = Math.floor(Math.random() * 5) - 2;
  const nx = (cx || 100) + dx;
  const ny = (cy || 100) + dy;
  document.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, cancelable: true, clientX: nx, clientY: ny }));
  return { status: 'ok', action: 'twitch', x: nx, y: ny };
}
function executeSafeIdleClick() {
  const body = document.body;
  if (!body) return { status: 'failed', reason: 'no-body' };
  body.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, clientX: 10, clientY: 10 }));
  return { status: 'ok', action: 'safeIdleClick', x: 10, y: 10 };
}
function executeHarmlessKey() {
  const activeEl = document.activeElement;
  if (activeEl && (activeEl.tagName === 'INPUT' || activeEl.tagName === 'TEXTAREA' || activeEl.isContentEditable)) {
    return { status: 'skipped', reason: 'input-focused' };
  }
  const keys = ['Shift', 'Alt', 'ArrowDown', 'ArrowUp'];
  const k = keys[Math.floor(Math.random() * keys.length)];
  document.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }));
  return { status: 'ok', action: 'harmlessKey', key: k };
}") "\n")

fn generateInBrowserAgentBootstrap cfg: InBrowserAgentConfig -> Str
  (let [(evasions (if cfg.stealthEvasions (generateStealthEvasionScript) ""))
        (distiller (generateDomDistillerScript cfg.maxSnapshotNodes))
        (kinetics (if cfg.kineticsEnabled (generateKineticExecutorScript) ""))
        (noise (if cfg.behavioralNoise (generateBehavioralNoiseScript) ""))
        (agentId cfg.agentId)
        (ver cfg.version)]
    (str (f/js (str "(function() {
  if (window.__aslAgentActive) return;
  window.__aslAgentActive = true;
  window.__aslAgentVersion = '" (f/jsStr ver) "';
  window.__aslAgentId = '" (f/jsStr agentId) "';
"))
      evasions
      distiller
      kinetics
      noise
      (f/js (str "  window.__aslAgent = {
    id: '" (f/jsStr agentId) "',
    version: '" (f/jsStr ver) "',
    distill: distillDomToAsn,
    click: typeof executeKineticClick === 'function' ? executeKineticClick : null,
    type: typeof executeKineticType === 'function' ? executeKineticType : null,
    scroll: typeof executeKineticScroll === 'function' ? executeKineticScroll : null,
    twitch: typeof executeCursorTwitch === 'function' ? executeCursorTwitch : null,
    safeClick: typeof executeSafeIdleClick === 'function' ? executeSafeIdleClick : null,
    harmlessKey: typeof executeHarmlessKey === 'function' ? executeHarmlessKey : null,
    exec: function(action) {
      const op = action.op || 'snapshot';
      if (op === 'snapshot') return distillDomToAsn();
      if (op === 'click') return JSON.stringify(executeKineticClick(action.target));
      if (op === 'type') return JSON.stringify(executeKineticType(action.target, action.value));
      if (op === 'scroll') return JSON.stringify(executeKineticScroll(action.pixels || 300, action.direction || 'down'));
      if (op === 'twitch') return JSON.stringify(executeCursorTwitch(action.x, action.y));
      if (op === 'safeClick') return JSON.stringify(executeSafeIdleClick());
      if (op === 'harmlessKey') return JSON.stringify(executeHarmlessKey());
      return '(:error \"Unknown in-page action op\")';
    }
  };
  console.log('[ASL Agent] In-browser resident agent initialized (' + window.__aslAgentVersion + ')');
})();")) "\n"))

fn formatAgentStatusAsn cfg: InBrowserAgentConfig -> Str
  (str "(:inBrowserAgent"
       " :agentId \"" (esc/escapeAsnStr cfg.agentId) "\""
       " :version \"" (esc/escapeAsnStr cfg.version) "\""
       " :stealthEvasions " (if cfg.stealthEvasions "true" "false")
       " :kineticsEnabled " (if cfg.kineticsEnabled "true" "false")
       " :behavioralNoise " (if cfg.behavioralNoise "true" "false")
       " :maxSnapshotNodes " (stringFromInt64 cfg.maxSnapshotNodes)
       " :status :ready)")
