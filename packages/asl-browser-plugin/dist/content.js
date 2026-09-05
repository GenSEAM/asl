/**
 * ASL Content Script: Intelligent DOM Extraction, Dual Perception & Control
 * Extracts hierarchical Accessibility Tree (AXTree) with @eN refs,
 * downsamples DOM structure (D2Snap), and formats into Standard ASL frames
 * conforming to @pcp:d-596e and @pcp:d-1eed.
 */
// ============================================================================
// Element Registry: maps @eN refs to live DOM Elements
// ============================================================================
export const elementRegistry = new Map();
export const elementToRef = new Map();
let refCounter = 1;
export function resetRefRegistry() {
    elementRegistry.clear();
    elementToRef.clear();
    refCounter = 1;
}
export function registerElement(el, existingRef) {
    if (elementToRef.has(el)) {
        return elementToRef.get(el);
    }
    const ref = existingRef || `@e${refCounter++}`;
    elementRegistry.set(ref, el);
    elementToRef.set(el, ref);
    try {
        if (typeof el.setAttribute === 'function') {
            el.setAttribute('data-asl-ref', ref);
        }
    }
    catch {
        // Ignore in synthetic mock objects
    }
    return ref;
}
export function getElementByRef(ref) {
    return elementRegistry.get(ref);
}
// ============================================================================
// String & S-Expression Formatting Helpers
// ============================================================================
export function cleanAttr(val) {
    return val.replace(/\s+/g, ' ').trim();
}
export function escapeASL(str) {
    return str.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, ' ');
}
// ============================================================================
// Accessibility Tree (AXTree) Extraction
// ============================================================================
export const PRUNED_TAGS = new Set([
    'script',
    'style',
    'noscript',
    'template',
    'head',
    'meta',
    'link',
    'svg',
    'iframe'
]);
export const RETAINED_ATTRIBUTES = new Set([
    'id',
    'name',
    'role',
    'type',
    'aria-label',
    'aria-describedby',
    'aria-expanded',
    'aria-checked',
    'aria-selected',
    'aria-disabled',
    'placeholder',
    'href',
    'src',
    'value',
    'alt',
    'title',
    'ref',
    'data-asl-ref',
    'data-testid',
    'disabled',
    'checked',
    'selected'
]);
export const INTERACTIVE_ROLES = new Set([
    'button',
    'link',
    'checkbox',
    'radio',
    'combobox',
    'textbox',
    'searchbox',
    'menuitem',
    'tab',
    'switch',
    'option'
]);
export function inferRole(el) {
    const explicitRole = typeof el.getAttribute === 'function' ? el.getAttribute('role') : null;
    if (explicitRole)
        return explicitRole.toLowerCase().trim();
    const tag = el.tagName ? el.tagName.toLowerCase() : 'generic';
    switch (tag) {
        case 'a':
            return (typeof el.hasAttribute === 'function' && el.hasAttribute('href')) ? 'link' : 'generic';
        case 'button':
            return 'button';
        case 'input': {
            const type = (typeof el.getAttribute === 'function' ? el.getAttribute('type') : null) || 'text';
            const lowerType = type.toLowerCase();
            if (['button', 'submit', 'reset'].includes(lowerType))
                return 'button';
            if (lowerType === 'checkbox')
                return 'checkbox';
            if (lowerType === 'radio')
                return 'radio';
            if (lowerType === 'search')
                return 'searchbox';
            return 'textbox';
        }
        case 'textarea':
            return 'textbox';
        case 'select':
            return 'combobox';
        case 'h1':
        case 'h2':
        case 'h3':
        case 'h4':
        case 'h5':
        case 'h6':
            return 'heading';
        case 'nav':
            return 'navigation';
        case 'main':
            return 'main';
        case 'article':
            return 'article';
        case 'header':
            return 'banner';
        case 'footer':
            return 'contentinfo';
        case 'aside':
            return 'complementary';
        case 'dialog':
            return 'dialog';
        case 'ul':
        case 'ol':
            return 'list';
        case 'li':
            return 'listitem';
        case 'table':
            return 'table';
        case 'form':
            return 'form';
        default:
            return 'generic';
    }
}
export const NAME_FROM_CONTENTS_ROLES = new Set([
    'button',
    'link',
    'heading',
    'menuitem',
    'tab',
    'checkbox',
    'radio',
    'option'
]);
export function getAccessibleName(el, doc) {
    if (typeof el.getAttribute !== 'function')
        return '';
    const ariaLabel = el.getAttribute('aria-label');
    if (ariaLabel?.trim())
        return cleanAttr(ariaLabel);
    const labelledBy = el.getAttribute('aria-labelledby');
    if (labelledBy) {
        const activeDoc = doc || el.ownerDocument || (typeof document !== 'undefined' ? document : null);
        if (activeDoc && typeof activeDoc.getElementById === 'function') {
            const target = activeDoc.getElementById(labelledBy);
            if (target?.textContent?.trim())
                return cleanAttr(target.textContent);
        }
    }
    const placeholder = el.getAttribute('placeholder');
    if (placeholder?.trim())
        return cleanAttr(placeholder);
    const title = el.getAttribute('title');
    if (title?.trim())
        return cleanAttr(title);
    const alt = el.getAttribute('alt');
    if (alt?.trim())
        return cleanAttr(alt);
    const role = inferRole(el);
    const tag = el.tagName ? el.tagName.toLowerCase() : '';
    if (tag === 'input' || tag === 'textarea' || tag === 'select') {
        const val = el.value || el.getAttribute('value');
        if (val && typeof val === 'string' && val.trim())
            return cleanAttr(val);
    }
    // Only take name from text contents if role supports name from contents
    if (NAME_FROM_CONTENTS_ROLES.has(role)) {
        const text = el.textContent || el.innerText || '';
        return cleanAttr(text).slice(0, 100);
    }
    return '';
}
export function extractAXTree(root, doc) {
    if (!root)
        return null;
    const role = inferRole(root);
    const name = getAccessibleName(root, doc);
    const isInteractive = INTERACTIVE_ROLES.has(role);
    const desc = typeof root.getAttribute === 'function'
        ? (root.getAttribute('aria-description') || root.getAttribute('title') || undefined)
        : undefined;
    const disabled = typeof root.hasAttribute === 'function'
        && (root.hasAttribute('disabled') || root.getAttribute('aria-disabled') === 'true');
    const focused = (typeof document !== 'undefined' && document.activeElement === root) || undefined;
    const rawValue = root.value !== undefined ? String(root.value) : undefined;
    const children = [];
    const childNodes = Array.from(root.children || []);
    for (const child of childNodes) {
        const tag = child.tagName ? child.tagName.toLowerCase() : '';
        if (PRUNED_TAGS.has(tag))
            continue;
        const axChild = extractAXTree(child, doc);
        if (axChild) {
            children.push(axChild);
        }
    }
    const hasContent = name.length > 0 || isInteractive || children.length > 0;
    if (!hasContent && role === 'generic') {
        return null;
    }
    let ref = '';
    if (isInteractive || (name.length > 0 && role !== 'generic')) {
        ref = registerElement(root);
    }
    return {
        role,
        name,
        ref,
        description: desc ? cleanAttr(desc) : undefined,
        disabled: disabled || undefined,
        focused: focused || undefined,
        value: (isInteractive && rawValue) ? cleanAttr(rawValue) : undefined,
        children: children.length > 0 ? children : undefined
    };
}
export function serializeAXNodeToASL(node) {
    const parts = [':ax-node', `:role "${escapeASL(node.role)}"`];
    if (node.name)
        parts.push(`:name "${escapeASL(node.name)}"`);
    if (node.ref)
        parts.push(`:ref "${escapeASL(node.ref)}"`);
    if (node.description)
        parts.push(`:desc "${escapeASL(node.description)}"`);
    if (node.disabled)
        parts.push(':disabled true');
    if (node.focused)
        parts.push(':focused true');
    if (node.value)
        parts.push(`:value "${escapeASL(node.value)}"`);
    if (node.children && node.children.length > 0) {
        const childStrs = node.children.map(c => serializeAXNodeToASL(c)).join(' ');
        parts.push(childStrs);
    }
    return `(${parts.join(' ')})`;
}
// ============================================================================
// D2Snap: Structural DOM Downsampler
// ============================================================================
export function elementToVNode(el) {
    const tag = el.tagName ? el.tagName.toLowerCase() : 'div';
    if (PRUNED_TAGS.has(tag))
        return null;
    const attrs = {};
    if (typeof el.getAttributeNames === 'function') {
        for (const attrName of el.getAttributeNames()) {
            const lower = attrName.toLowerCase();
            if (RETAINED_ATTRIBUTES.has(lower)) {
                const val = el.getAttribute(attrName);
                if (val)
                    attrs[lower] = cleanAttr(val);
            }
        }
    }
    else if (el.attributes) {
        for (const attr of Array.from(el.attributes)) {
            const lower = attr.name.toLowerCase();
            if (RETAINED_ATTRIBUTES.has(lower) && attr.value) {
                attrs[lower] = cleanAttr(attr.value);
            }
        }
    }
    const children = [];
    const childNodes = Array.from(el.childNodes || el.children || []);
    for (const child of childNodes) {
        if (child.nodeType === 3 /* TEXT_NODE */) {
            const text = cleanAttr(child.textContent || '');
            if (text)
                children.push({ type: 'text', content: text });
        }
        else if (child.nodeType === 1 /* ELEMENT_NODE */ || child.tagName) {
            const vchild = elementToVNode(child);
            if (vchild)
                children.push(vchild);
        }
    }
    const isWrapper = (tag === 'div' || tag === 'span' || tag === 'section') && Object.keys(attrs).length === 0;
    if (isWrapper && children.length === 1 && children[0].type === 'element') {
        return children[0];
    }
    return { type: 'element', tag, attrs, children };
}
export function serializeVNodeToASL(node) {
    if (node.type === 'text') {
        return `"${escapeASL(node.content)}"`;
    }
    const parts = [node.tag];
    for (const [k, v] of Object.entries(node.attrs)) {
        parts.push(`:${k} "${escapeASL(v)}"`);
    }
    for (const child of node.children) {
        parts.push(serializeVNodeToASL(child));
    }
    return `(${parts.join(' ')})`;
}
// ============================================================================
// Standard ASL Formatting (@pcp:d-1eed)
// Enforces dfs, :f, Str, I64, :d, :x
// ============================================================================
export function formatStandardASL(params) {
    const escTitle = escapeASL(params.title);
    const escUrl = escapeASL(params.url);
    return `(module browser/page
  :d "Extracted DOM context for ${escTitle}"
  :x [PageContext PageAction AXNodeFrame]

  (dfs PageContext
    (:f url Str)
    (:f title Str)
    (:f elements_count I64)
    (:f savings_pct I64))

  (dfs PageAction
    (:f action Str)
    (:f target Str)
    (:f value Str))

  (dfs AXNodeFrame
    (:f role Str)
    (:f name Str)
    (:f ref Str))

  (:ax-state
    :url "${escUrl}"
    :title "${escTitle}"
    :elements_count ${params.elementsCount}
    :savings_pct ${params.savingsPercent}
    :tree ${params.axTreeAsl}))`;
}
// ============================================================================
// Context Extraction & Token Economy
// ============================================================================
export function extractPageContext(customDoc) {
    resetRefRegistry();
    const doc = customDoc || (typeof document !== 'undefined' ? document : null);
    const url = (typeof window !== 'undefined' && window.location?.href) || 'https://browser.agent/local';
    const title = doc?.title || 'Active Page';
    const rootEl = doc?.body || doc?.documentElement || null;
    const rawHtml = rootEl ? (rootEl.outerHTML || '') : '';
    const rawLength = rawHtml.length || 1000;
    // Extract clean article text from semantic containers
    let articleText = '';
    if (doc) {
        const mainEl = typeof doc.querySelector === 'function'
            ? doc.querySelector('main, article, #content, .content, body')
            : null;
        const rawText = mainEl?.innerText || mainEl?.textContent || rootEl?.innerText || rootEl?.textContent || '';
        articleText = rawText.split('\n').map((l) => l.trim()).filter(Boolean).slice(0, 40).join('\n');
    }
    // Extract AXTree
    const axTree = rootEl ? extractAXTree(rootEl, doc || undefined) : null;
    const axTreeAsl = axTree ? serializeAXNodeToASL(axTree) : '(:ax-node :role "generic" :name "Empty")';
    // Extract D2Snap downsampled DOM
    const vnode = rootEl ? elementToVNode(rootEl) : null;
    const downsampledAsl = vnode ? serializeVNodeToASL(vnode) : '()';
    // Interactive elements list
    const interactiveList = [];
    for (const [ref, el] of elementRegistry.entries()) {
        const role = inferRole(el);
        const tag = el.tagName ? el.tagName.toLowerCase() : 'element';
        const text = getAccessibleName(el, doc || undefined);
        const id = el.id ? `#${el.id}` : '';
        const className = el.className && typeof el.className === 'string'
            ? `.${el.className.trim().split(/\s+/)[0]}`
            : '';
        const selector = id || className || tag;
        interactiveList.push({
            tag,
            text,
            selector,
            ref,
            role
        });
    }
    // Token economy calculation
    const compressedLength = axTreeAsl.length;
    const tokenSavingsPercent = rawLength > 0
        ? Math.max(0, Math.min(99, Math.round(((rawLength - compressedLength) / rawLength) * 100)))
        : 78;
    const aslSExpression = formatStandardASL({
        url,
        title,
        elementsCount: interactiveList.length,
        savingsPercent: tokenSavingsPercent,
        axTreeAsl,
        d2snapAsl: downsampledAsl
    });
    return {
        url,
        title,
        articleText,
        interactiveElements: interactiveList,
        axTree,
        axTreeAsl,
        downsampledAsl,
        aslSExpression,
        rawOuterHtmlLength: rawLength,
        compressedLength,
        tokenSavingsPercent
    };
}
// ============================================================================
// Page Action Dispatching & Target Resolution (Resolves by @eN Ref and Selector)
// ============================================================================
export function resolveElement(target, customDoc) {
    if (!target)
        return null;
    const cleanTarget = target.trim();
    // 1. If starts with '@', resolve by ref directly from registry
    if (cleanTarget.startsWith('@')) {
        const found = elementRegistry.get(cleanTarget);
        if (found)
            return found;
        // Fallback: check DOM attribute data-asl-ref
        const doc = customDoc || (typeof document !== 'undefined' ? document : null);
        if (doc && typeof doc.querySelector === 'function') {
            try {
                const byAttr = doc.querySelector(`[data-asl-ref="${cleanTarget}"]`);
                if (byAttr)
                    return byAttr;
            }
            catch {
                // Ignore querySelector error
            }
        }
    }
    // 2. Check if cleanTarget matches key in elementRegistry directly
    if (elementRegistry.has(cleanTarget)) {
        return elementRegistry.get(cleanTarget);
    }
    // 3. Resolve by CSS selector
    const doc = customDoc || (typeof document !== 'undefined' ? document : null);
    if (doc && typeof doc.querySelector === 'function') {
        try {
            const el = doc.querySelector(cleanTarget);
            if (el)
                return el;
        }
        catch {
            // Ignore CSS selector parse error
        }
    }
    return null;
}
export function performPageAction(action, params, customDoc) {
    const target = String(params.ref || params.selector || params.target || '').trim();
    const el = resolveElement(target, customDoc);
    const ref = el ? (elementToRef.get(el) || (typeof el.getAttribute === 'function' ? el.getAttribute('data-asl-ref') : undefined) || undefined) : undefined;
    const selector = params.selector || (el?.id ? `#${el.id}` : target);
    try {
        const actUpper = action.toUpperCase();
        if (actUpper === 'CLICK') {
            if (!el)
                return { ok: false, message: `Element not found: ${target}` };
            if (typeof el.scrollIntoView === 'function') {
                el.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
            if (el.style) {
                const prevOutline = el.style.outline;
                el.style.outline = '2px solid #38bdf8';
                setTimeout(() => {
                    try {
                        el.style.outline = prevOutline;
                    }
                    catch { }
                }, 800);
            }
            if (typeof el.click === 'function') {
                el.click();
            }
            return { ok: true, message: `Clicked element: ${target}`, ref, selector };
        }
        if (actUpper === 'FILL') {
            if (!el)
                return { ok: false, message: `Input element not found: ${target}` };
            if (typeof el.focus === 'function') {
                el.focus();
            }
            const textToFill = params.text !== undefined
                ? String(params.text)
                : (params.value !== undefined ? String(params.value) : '');
            el.value = textToFill;
            if (typeof el.dispatchEvent === 'function' && typeof Event !== 'undefined') {
                try {
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                    el.dispatchEvent(new Event('change', { bubbles: true }));
                }
                catch {
                    // Ignore event dispatch failure in custom mocks
                }
            }
            return { ok: true, message: `Filled input ${target} with "${textToFill}"`, ref, selector };
        }
        if (actUpper === 'SCROLL') {
            if (el && typeof el.scrollIntoView === 'function') {
                el.scrollIntoView({ behavior: 'smooth', block: 'center' });
                return { ok: true, message: `Scrolled element ${target} into view`, ref, selector };
            }
            const delta = params.direction === 'up' ? -(params.amount || 400) : (params.amount || 400);
            if (typeof window !== 'undefined' && typeof window.scrollBy === 'function') {
                window.scrollBy({ top: delta, behavior: 'smooth' });
            }
            return { ok: true, message: `Scrolled window by ${delta}px` };
        }
        return { ok: false, message: `Unknown action: ${action}` };
    }
    catch (err) {
        return { ok: false, message: `Action error: ${err.message}` };
    }
}
// ============================================================================
// Runtime Message Listener
// ============================================================================
if (typeof chrome !== 'undefined' && chrome?.runtime?.onMessage?.addListener) {
    chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
        if (msg.type === 'EXTRACT_DOM') {
            sendResponse(extractPageContext());
        }
        else if (msg.type === 'PAGE_ACTION') {
            const result = performPageAction(msg.action, msg.params || {});
            sendResponse(result);
        }
    });
}
