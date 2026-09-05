/**
 * Dual Perception & DOM Compaction Bridge for AgentScript (asl-vdom)
 * Converts browser DOM / CDP accessibility trees into compact ASL S-expression frames.
 * Reduces raw HTML token overhead by >= 75% (@pcp:d-676f).
 */

export interface AXNode {
  role: string;
  name: string;
  ref: string; // e.g. "@e1"
  description?: string;
  disabled?: boolean;
  focused?: boolean;
  value?: string;
  children?: AXNode[];
}

export interface CDPAXValue {
  type: string;
  value?: any;
}

export interface CDPAXProperty {
  name: string;
  value: CDPAXValue;
}

export interface CDPAXNode {
  nodeId: string;
  role?: CDPAXValue;
  name?: CDPAXValue;
  description?: CDPAXValue;
  value?: CDPAXValue;
  disabled?: CDPAXValue;
  focused?: CDPAXValue;
  properties?: CDPAXProperty[];
  childIds?: string[];
  backendDOMNodeId?: number;
  ignored?: boolean;
}

export type VNode =
  | { type: 'text'; content: string }
  | { type: 'element'; tag: string; attrs: Record<string, string>; children: VNode[] };

export type AddedRecord = { type: 'added'; target: string; node: VNode };
export type RemovedRecord = { type: 'removed'; target: string; ref: string };
export type MutatedRecord = { type: 'mutated'; target: string; key: string; newVal: string };

export type MutationRecord = AddedRecord | RemovedRecord | MutatedRecord;

export interface DomDiff {
  route: string;
  mutations: MutationRecord[];
  added: VNode[];
  removed: string[];
  mutated: MutatedRecord[];
}

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
  'data-testid',
  'disabled',
  'checked',
  'selected'
]);

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

/**
 * Normalizes an attribute string to remove excessive whitespace or line breaks.
 */
function cleanAttr(val: string): string {
  return val.replace(/\s+/g, ' ').trim();
}

/**
 * Escapes a string for inclusion in an ASL string literal.
 */
function escapeASL(str: string): string {
  return str.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, ' ');
}

// ============================================================================
// Tier 1: Accessibility Tree (AXTree) Extractor
// ============================================================================

/**
 * Converts a Chrome DevTools Protocol (CDP) Accessibility Tree into a hierarchical AXNode tree.
 */
export function fromCDPAXTree(nodes: CDPAXNode[]): AXNode | null {
  if (!nodes || nodes.length === 0) return null;

  const nodeMap = new Map<string, CDPAXNode>();
  for (const n of nodes) {
    nodeMap.set(n.nodeId, n);
  }

  // Find root node (first node or node with role WebArea/RootWebArea)
  let root = nodes.find(n => n.role?.value === 'RootWebArea' || n.role?.value === 'WebArea') || nodes[0];
  let refCounter = 1;

  function buildNode(n: CDPAXNode): AXNode | null {
    if (n.ignored) return null;

    const role = String(n.role?.value || 'generic');
    const name = cleanAttr(String(n.name?.value || ''));
    const description = n.description?.value ? cleanAttr(String(n.description.value)) : undefined;
    const disabled = Boolean(n.disabled?.value);
    const focused = Boolean(n.focused?.value);
    const value = n.value?.value ? String(n.value.value) : undefined;

    // Filter out uninformative empty generic nodes with no name and no children
    const rawChildIds = n.childIds || [];
    const children: AXNode[] = [];
    for (const cid of rawChildIds) {
      const childCDP = nodeMap.get(cid);
      if (childCDP) {
        const built = buildNode(childCDP);
        if (built) children.push(built);
      }
    }

    const isInteractive = ['button', 'link', 'checkbox', 'radio', 'combobox', 'textbox', 'searchbox', 'menuitem', 'tab'].includes(role);
    const hasInfo = name.length > 0 || isInteractive || children.length > 0;
    if (!hasInfo && role === 'generic') return null;

    const ref = isInteractive || name.length > 0 ? `@e${refCounter++}` : '';

    return {
      role,
      name,
      ref,
      description,
      disabled: disabled || undefined,
      focused: focused || undefined,
      value,
      children: children.length > 0 ? children : undefined
    };
  }

  return buildNode(root);
}

/**
 * Converts Playwright / Puppeteer accessibility snapshot to AXNode tree.
 */
export function fromPlaywrightSnapshot(snapshot: any, counter = { val: 1 }): AXNode | null {
  if (!snapshot) return null;

  const role = String(snapshot.role || 'generic');
  const name = cleanAttr(String(snapshot.name || ''));
  const description = snapshot.description ? cleanAttr(String(snapshot.description)) : undefined;
  const disabled = Boolean(snapshot.disabled);
  const focused = Boolean(snapshot.focused);
  const value = snapshot.value !== undefined ? String(snapshot.value) : undefined;

  const children: AXNode[] = [];
  if (Array.isArray(snapshot.children)) {
    for (const ch of snapshot.children) {
      const childNode = fromPlaywrightSnapshot(ch, counter);
      if (childNode) children.push(childNode);
    }
  }

  const isInteractive = ['button', 'link', 'checkbox', 'radio', 'combobox', 'textbox', 'searchbox', 'menuitem', 'tab'].includes(role);
  const ref = isInteractive || name.length > 0 ? `@e${counter.val++}` : '';

  return {
    role,
    name,
    ref,
    description,
    disabled: disabled || undefined,
    focused: focused || undefined,
    value,
    children: children.length > 0 ? children : undefined
  };
}

/**
 * Serializes an AXNode tree into compact ASL S-expression frame.
 */
export function serializeAXTreeToASL(node: AXNode): string {
  const parts: string[] = ['ax-node'];

  parts.push(`:role "${escapeASL(node.role)}"`);
  if (node.name) parts.push(`:name "${escapeASL(node.name)}"`);
  if (node.ref) parts.push(`:ref "${escapeASL(node.ref)}"`);
  if (node.description) parts.push(`:desc "${escapeASL(node.description)}"`);
  if (node.disabled) parts.push(':disabled true');
  if (node.focused) parts.push(':focused true');
  if (node.value) parts.push(`:value "${escapeASL(node.value)}"`);

  if (node.children && node.children.length > 0) {
    const childFrames = node.children.map(c => serializeAXTreeToASL(c)).join(' ');
    parts.push(childFrames);
  }

  return `(${parts.join(' ')})`;
}

// ============================================================================
// Tier 2: Structural DOM Downsampler (D2Snap)
// ============================================================================

/**
 * Filters and downsamples a VNode tree:
 * 1. Discards script/style/svg/meta tags
 * 2. Strips class soup and inline styles, keeping only semantic attributes
 * 3. Collapses single-child transparent wrappers (e.g. <div><span><button> -> <button>)
 * 4. Collapses repeated identical sibling items into compact summaries
 */
export function downsampleVNode(node: VNode): VNode | null {
  if (node.type === 'text') {
    const trimmed = cleanAttr(node.content);
    return trimmed.length > 0 ? { type: 'text', content: trimmed } : null;
  }

  const tag = node.tag.toLowerCase();
  if (PRUNED_TAGS.has(tag)) return null;

  // Filter attributes
  const filteredAttrs: Record<string, string> = {};
  for (const [k, v] of Object.entries(node.attrs)) {
    const lowerKey = k.toLowerCase();
    if (RETAINED_ATTRIBUTES.has(lowerKey)) {
      const cleanedVal = cleanAttr(v);
      if (cleanedVal.length > 0) {
        filteredAttrs[lowerKey] = cleanedVal;
      }
    }
  }

  // Recursively downsample children
  const downsampledChildren: VNode[] = [];
  for (const child of node.children) {
    const processed = downsampleVNode(child);
    if (processed) downsampledChildren.push(processed);
  }

  // Collapse redundant single-child wrappers
  const hasNoSemanticAttrs = Object.keys(filteredAttrs).length === 0;
  const isWrapperTag = tag === 'div' || tag === 'span' || tag === 'section';
  if (isWrapperTag && hasNoSemanticAttrs && downsampledChildren.length === 1) {
    return downsampledChildren[0];
  }

  // Collapse repeated sibling items (e.g. lists of 10 items collapsed to 3 + :repeat 7)
  const collapsedChildren = collapseRepeatedSiblings(downsampledChildren);

  return {
    type: 'element',
    tag,
    attrs: filteredAttrs,
    children: collapsedChildren
  };
}

/**
 * Collapses long sequences of structurally identical sibling nodes.
 */
function collapseRepeatedSiblings(children: VNode[]): VNode[] {
  if (children.length <= 4) return children;

  const result: VNode[] = [];
  let i = 0;

  while (i < children.length) {
    const current = children[i];
    if (current.type === 'element') {
      let run = 1;
      while (i + run < children.length) {
        const next = children[i + run];
        if (next.type === 'element' && next.tag === current.tag) {
          run++;
        } else {
          break;
        }
      }

      if (run > 4) {
        // Keep first 2, add repeat marker, keep last 1
        result.push(current);
        result.push(children[i + 1]);
        result.push({
          type: 'element',
          tag: current.tag,
          attrs: { ':repeat': String(run - 3) },
          children: [{ type: 'text', content: `... ${run - 3} more ${current.tag} items ...` }]
        });
        result.push(children[i + run - 1]);
        i += run;
        continue;
      }
    }

    result.push(current);
    i++;
  }

  return result;
}

/**
 * Serializes a VNode into compact S-expression representation.
 */
export function serializeVNodeToASL(node: VNode): string {
  if (node.type === 'text') {
    return `"${escapeASL(node.content)}"`;
  }

  const parts: string[] = [node.tag];

  // Serialize attributes
  for (const [k, v] of Object.entries(node.attrs)) {
    if (k.startsWith(':')) {
      parts.push(`${k} ${v}`);
    } else {
      parts.push(`:${k} "${escapeASL(v)}"`);
    }
  }

  // Serialize children
  for (const child of node.children) {
    parts.push(serializeVNodeToASL(child));
  }

  return `(${parts.join(' ')})`;
}

// ============================================================================
// Incremental DOM Diffing
// ============================================================================

/**
 * Computes atomic mutations between two VNode trees.
 */
export function diffVNodes(oldTree: VNode, newTree: VNode, route = '/'): DomDiff {
  const mutations: MutationRecord[] = [];

  function diff(n1: VNode, n2: VNode, path: string) {
    if (n1.type === 'text' && n2.type === 'text') {
      if (n1.content !== n2.content) {
        mutations.push({ type: 'mutated', target: path, key: 'text', newVal: n2.content });
      }
      return;
    }

    if (n1.type !== n2.type) {
      mutations.push({ type: 'removed', target: path, ref: n1.type });
      mutations.push({ type: 'added', target: path, node: n2 });
      return;
    }

    if (n1.type === 'element' && n2.type === 'element') {
      if (n1.tag !== n2.tag) {
        mutations.push({ type: 'removed', target: path, ref: n1.tag });
        mutations.push({ type: 'added', target: path, node: n2 });
        return;
      }

      // Diff attributes
      const allKeys = Array.from(new Set([...Object.keys(n1.attrs), ...Object.keys(n2.attrs)]));
      for (const k of allKeys) {
        const v1 = n1.attrs[k];
        const v2 = n2.attrs[k];
        if (v1 === undefined && v2 !== undefined) {
          mutations.push({ type: 'mutated', target: path, key: k, newVal: v2 });
        } else if (v1 !== undefined && v2 === undefined) {
          mutations.push({ type: 'mutated', target: path, key: k, newVal: '' });
        } else if (v1 !== v2) {
          mutations.push({ type: 'mutated', target: path, key: k, newVal: v2 });
        }
      }

      // Diff children
      const maxLen = Math.max(n1.children.length, n2.children.length);
      for (let i = 0; i < maxLen; i++) {
        const childPath = `${path}/${i}`;
        const c1 = n1.children[i];
        const c2 = n2.children[i];
        if (c1 && !c2) {
          mutations.push({ type: 'removed', target: childPath, ref: String(i) });
        } else if (!c1 && c2) {
          mutations.push({ type: 'added', target: childPath, node: c2 });
        } else if (c1 && c2) {
          diff(c1, c2, childPath);
        }
      }
    }
  }

  diff(oldTree, newTree, 'root');

  const added: VNode[] = [];
  const removed: string[] = [];
  const mutated: MutatedRecord[] = [];

  for (const m of mutations) {
    if (m.type === 'added') added.push(m.node);
    else if (m.type === 'removed') removed.push(`${m.target}:${m.ref}`);
    else if (m.type === 'mutated') mutated.push(m);
  }

  return { route, mutations, added, removed, mutated };
}

/**
 * Formats a DomDiff into a standard ASL S-expression frame:
 * (! dom/diff :route r :added [...] :removed [...] :mutated [...])
 */
export function formatDiffAsASL(diff: DomDiff): string {
  const addedASL = diff.added.map(n => serializeVNodeToASL(n)).join(' ');
  const removedASL = diff.removed.map(r => `"${escapeASL(r)}"`).join(' ');
  const mutatedASL = diff.mutated.map(m => `(:target "${escapeASL(m.target)}" :key "${escapeASL(m.key)}" :val "${escapeASL(m.newVal)}")`).join(' ');

  return `(! dom/diff :route "${escapeASL(diff.route)}" :added [${addedASL}] :removed [${removedASL}] :mutated [${mutatedASL}])`;
}

// ============================================================================
// Token Savings & Compaction Metrics
// ============================================================================

/**
 * Measures token and byte savings between raw HTML and compressed ASL S-expression.
 */
export function estimateSavings(rawHTML: string, compressedASL: string): {
  rawBytes: number;
  compressedBytes: number;
  estimatedRawTokens: number;
  estimatedCompressedTokens: number;
  savingsPercent: number;
} {
  const rawBytes = new TextEncoder().encode(rawHTML).length;
  const compressedBytes = new TextEncoder().encode(compressedASL).length;

  // Approximate 4 chars per token for general text/code
  const estimatedRawTokens = Math.ceil(rawHTML.length / 4);
  const estimatedCompressedTokens = Math.ceil(compressedASL.length / 4);
  const savingsPercent = rawBytes > 0 ? Math.round(((rawBytes - compressedBytes) / rawBytes) * 1000) / 10 : 0;

  return {
    rawBytes,
    compressedBytes,
    estimatedRawTokens,
    estimatedCompressedTokens,
    savingsPercent
  };
}
