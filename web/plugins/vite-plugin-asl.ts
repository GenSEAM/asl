import fs from 'fs';
import path from 'path';

/**
 * Parses canonical posts.asn S-expression into structured post records.
 */
export function parseAsnPosts(raw: string): any[] {
  const tokens: Array<{ type: string; val: string }> = [];
  let pos = 0;
  while (pos < raw.length) {
    while (pos < raw.length && /\s/.test(raw[pos])) pos++;
    if (pos >= raw.length) break;
    const ch = raw[pos];
    if (ch === '(' || ch === ')' || ch === '[' || ch === ']') {
      tokens.push({ type: ch, val: ch });
      pos++;
    } else if (ch === '"') {
      pos++;
      let s = '';
      while (pos < raw.length) {
        if (raw[pos] === '\\' && pos + 1 < raw.length) {
          const next = raw[pos + 1];
          if (next === 'n') s += '\n';
          else if (next === 't') s += '\t';
          else if (next === 'r') s += '\r';
          else if (next === '"') s += '"';
          else if (next === '\\') s += '\\';
          else s += next;
          pos += 2;
        } else if (raw[pos] === '"') {
          pos++;
          break;
        } else {
          s += raw[pos++];
        }
      }
      tokens.push({ type: 'str', val: s });
    } else {
      let word = '';
      while (pos < raw.length && !/[\s()[\]]/.test(raw[pos])) {
        word += raw[pos++];
      }
      tokens.push({ type: 'atom', val: word });
    }
  }

  let i = 0;
  function parseNode(): any {
    if (i >= tokens.length) return null;
    const t = tokens[i++];
    if (t.type === 'str') return t.val;
    if (t.type === 'atom') {
      if (!isNaN(Number(t.val))) return Number(t.val);
      return t.val;
    }
    if (t.type === '[') {
      const arr: any[] = [];
      while (i < tokens.length && tokens[i].type !== ']') {
        arr.push(parseNode());
      }
      if (i < tokens.length && tokens[i].type === ']') i++;
      return arr;
    }
    if (t.type === '(') {
      if (i < tokens.length && tokens[i].type === ')') {
        i++;
        return {};
      }
      const tag = tokens[i++];
      const obj: Record<string, any> = { _tag: tag.val };
      while (i < tokens.length && tokens[i].type !== ')') {
        const keyTok = tokens[i];
        if (keyTok.type === 'atom' && keyTok.val.startsWith(':')) {
          i++;
          const key = keyTok.val.slice(1);
          const val = parseNode();
          obj[key] = val;
        } else if (keyTok.type === '(') {
          const nested = parseNode();
          if (!obj._children) obj._children = [];
          obj._children.push(nested);
        } else {
          i++;
        }
      }
      if (i < tokens.length && tokens[i].type === ')') i++;
      return obj;
    }
    return null;
  }

  const root = parseNode();
  const children = (root && root._children) || [];
  return children.map((p: any) => ({
    slug: p.slug || '',
    title: p.title || '',
    date: p.date || '',
    author: p.author || '',
    category: p.category || '',
    readTime: p['read-time'] || p.readTime || '',
    excerpt: p.excerpt || '',
    tags: Array.isArray(p.tags) ? p.tags : [],
    order: typeof p.order === 'number' ? p.order : 0,
    importance: p.importance || 'technical',
    popularityRank: p.popularityRank || 0,
    status: p.status || 'published',
    content: p.content || ''
  }));
}

/**
 * Parses ASN S-expression VDOM string into valid HTML5 string.
 */
export function parseSExpToHtml(str: string): string {
  if (!str) return '';
  const trimmed = str.trim();
  if (trimmed.startsWith('<')) return trimmed;
  if (!trimmed.startsWith('(')) return trimmed;

  let pos = 0;
  function skipWhitespace() {
    while (pos < trimmed.length && /\s/.test(trimmed[pos])) pos++;
  }
  function parseToken() {
    skipWhitespace();
    if (pos >= trimmed.length) return null;
    const ch = trimmed[pos];
    if (ch === '(' || ch === ')') {
      pos++;
      return { type: ch, val: ch };
    }
    if (ch === '"') {
      pos++;
      let s = '';
      while (pos < trimmed.length) {
        if (trimmed[pos] === '\\' && pos + 1 < trimmed.length) {
          s += trimmed[pos + 1];
          pos += 2;
        } else if (trimmed[pos] === '"') {
          pos++;
          break;
        } else {
          s += trimmed[pos++];
        }
      }
      return { type: 'str', val: s };
    }
    let word = '';
    while (pos < trimmed.length && !/[\s()]/.test(trimmed[pos])) {
      word += trimmed[pos++];
    }
    return { type: 'atom', val: word };
  }

  const tokens: Array<{ type: string; val: string }> = [];
  let tok;
  while ((tok = parseToken()) !== null) {
    tokens.push(tok);
  }

  let idx = 0;
  function parseNode(): string {
    if (idx >= tokens.length) return '';
    const t = tokens[idx++];
    if (t.type === 'str') return t.val;
    if (t.type === 'atom') return t.val;
    if (t.type === '(') {
      if (idx >= tokens.length || tokens[idx].type === ')') {
        if (idx < tokens.length) idx++;
        return '';
      }
      const tag = tokens[idx++].val;
      const attrs: Record<string, string> = {};
      const children: string[] = [];

      while (idx < tokens.length && tokens[idx].type !== ')') {
        const next = tokens[idx];
        if (next.type === '(') {
          if (idx + 1 < tokens.length && tokens[idx + 1].type === 'atom' && tokens[idx + 1].val.startsWith(':')) {
            idx++; // consume '('
            while (idx < tokens.length && tokens[idx].type !== ')') {
              const kTok = tokens[idx++];
              if (kTok.type === 'atom' && kTok.val.startsWith(':')) {
                const key = kTok.val.slice(1);
                let val = '';
                if (idx < tokens.length && tokens[idx].type !== ')' && !tokens[idx].val?.startsWith?.(':')) {
                  val = tokens[idx++].val;
                }
                attrs[key] = val;
              } else {
                idx++;
              }
            }
            if (idx < tokens.length && tokens[idx].type === ')') idx++;
            continue;
          }
          children.push(parseNode());
        } else {
          children.push(parseNode());
        }
      }
      if (idx < tokens.length && tokens[idx].type === ')') idx++;

      const attrStr = Object.entries(attrs).map(([k, v]) => ` ${k}="${v}"`).join('');
      const inner = children.join('');
      return `<${tag}${attrStr}>${inner}</${tag}>`;
    }
    return '';
  }

  return parseNode();
}

/**
 * Zero-overhead Vite plugin for AgentScript (ASL)
 */
export function aslPlugin() {
  return {
    name: 'vite-plugin-asl',
    enforce: 'pre' as const,

    resolveId(id: string, importer?: string) {
      if (id.endsWith('.asl')) {
        if (id.startsWith('/')) {
          return path.resolve(__dirname, '..', id.slice(1));
        }
        if (importer) {
          return path.resolve(path.dirname(importer), id);
        }
        return path.resolve(__dirname, '..', id);
      }
      return null;
    },

    load(id: string) {
      if (!id.includes('.asl')) return null;

      const cleanId = id.split('?')[0];
      const rawFilename = cleanId.split(/[\\/]/).pop()?.replace('.asl', '') || 'Component';

      if (rawFilename.toLowerCase() === 'main') {
        return {
          code: `import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App.asl';
import './index.css';

const container = document.getElementById('root');
if (container) {
  const root = createRoot(container);
  root.render(React.createElement(App));
}
`,
          map: null
        };
      }

      // Read file content if it exists
      let content = '';
      try {
        if (fs.existsSync(cleanId)) {
          content = fs.readFileSync(cleanId, 'utf-8');
        }
      } catch (e) {}

      // Handle App.asl specifically
      if (rawFilename === 'App') {
        return {
          code: `import React, { useState, useEffect } from 'react';
import { renderCosmicBackground } from './components/CosmicLandscapeBackground.asl';
import { navbarView } from './components/Navbar.asl';
import { footerView } from './components/Footer.asl';
import { renderSearchModal } from './components/SearchModal.asl';
import { renderHomeView } from './views/HomeView.asl';
import { renderDocsView } from './views/DocsView.asl';
import { renderBlogView } from './views/BlogView.asl';
import { renderArticleDetailView } from './views/ArticleDetailView.asl';
import { renderPlaygroundView } from './views/PlaygroundView.asl';
import { renderRoadmapView } from './views/RoadmapView.asl';
import { renderEcosystemView } from './views/EcosystemView.asl';

export function appRoutes() {
  return ['/', '/playground', '/ecosystem', '/roadmap', '/docs', '/blog'];
}

export function resolveCurrentRoute() {
  if (typeof window === 'undefined') return '/';
  const path = window.location.pathname || '/';
  const hash = window.location.hash || '';
  if (path !== '/' && path !== '') {
    return path;
  }
  if (hash.startsWith('#/')) {
    return hash.slice(1);
  }
  if (hash === '#blog' || hash.startsWith('#blog/')) {
    return hash.replace('#', '/');
  }
  if (hash === '#docs' || hash.startsWith('#docs/')) {
    return hash.replace('#', '/');
  }
  if (hash === '#roadmap' || hash === '#ecosystem' || hash === '#playground') {
    return hash.replace('#', '/');
  }
  return hash || path || '/';
}

export function renderView(route) {
  if (route === '/playground' || route === '#playground') return renderPlaygroundView();
  if (route === '/ecosystem' || route === '#ecosystem') return renderEcosystemView();
  if (route === '/roadmap' || route === '#roadmap') return renderRoadmapView();
  if (route === '/docs' || route === '#docs') return renderDocsView();
  if (route === '/blog' || route === '#blog') return renderBlogView();
  if (route.startsWith('/blog/') || route.startsWith('#blog/')) {
    const clean = route.replace(/^#/, '').split('?')[0];
    const parts = clean.split('/').filter(Boolean);
    const slug = parts[0] === 'blog' ? parts[1] : '';
    if (slug) return renderArticleDetailView(slug);
    return renderBlogView();
  }
  return renderHomeView();
}

export function renderApp(currentRoute) {
  return (
    '<div class="min-h-screen bg-ground text-ink flex flex-col relative w-full overflow-x-hidden">' +
    renderCosmicBackground() +
    navbarView() +
    '<div class="relative z-10 flex-1 flex flex-col">' +
    renderView(currentRoute) +
    '</div>' +
    footerView() +
    renderSearchModal() +
    '</div>'
  );
}

export function App() {
  const [route, setRoute] = useState(() => {
    return resolveCurrentRoute();
  });

  useEffect(() => {
    const onHashChange = () => {
      const r = resolveCurrentRoute();
      setRoute(r);
      if (!window.location.hash.startsWith('#capabilities') && !window.location.hash.startsWith('#matrix') && !window.location.hash.startsWith('#wire-protocol') && !window.location.hash.startsWith('#agent-way')) {
        window.scrollTo(0, 0);
      }
    };
    window.addEventListener('hashchange', onHashChange);
    window.addEventListener('popstate', onHashChange);

    const onKeyDown = (e) => {
      const modal = document.getElementById('search-modal-root');
      const input = document.getElementById('sm-input');
      if (e.key === 'Escape') {
        if (modal) modal.style.display = 'none';
      }
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        if (modal) {
          const isHidden = modal.style.display === 'none' || !modal.style.display;
          modal.style.display = isHidden ? 'flex' : 'none';
          if (isHidden && input) setTimeout(() => input.focus(), 50);
        }
      }
    };
    window.addEventListener('keydown', onKeyDown);

    // Global link and blog card click interception for seamless SPA routing
    const onGlobalClick = (e) => {
      const target = e.target;
      if (!target) return;

      const link = target.closest ? target.closest('a') : null;
      if (link) {
        const href = link.getAttribute('href');
        if (href && href.startsWith('/') && !href.startsWith('//') && !href.startsWith('/llms.txt')) {
          e.preventDefault();
          window.history.pushState(null, '', href);
          onHashChange();
          return;
        }
      }

      const blogCard = target.closest ? target.closest('.bv-post-card, .asl-blog-card') : null;
      if (blogCard) {
        const slug = blogCard.getAttribute('data-slug');
        if (slug) {
          e.preventDefault();
          window.history.pushState(null, '', '/blog/' + slug);
          onHashChange();
          return;
        }
      }
    };
    document.addEventListener('click', onGlobalClick);

    // Wire search modal triggers
    const setupSearch = () => {
      const modal = document.getElementById('search-modal-root');
      const input = document.getElementById('sm-input');
      const closeBtn = document.getElementById('sm-close-btn');
      const searchBtns = document.querySelectorAll('button[aria-label="Search documentation"]');
      searchBtns.forEach(btn => {
        btn.onclick = () => {
          if (modal) {
            modal.style.display = 'flex';
            if (input) setTimeout(() => input.focus(), 50);
          }
        };
      });
      if (closeBtn && modal) {
        closeBtn.onclick = () => { modal.style.display = 'none'; };
      }
      if (modal) {
        modal.onclick = (e) => {
          if (e.target === modal) modal.style.display = 'none';
        };
      }
      if (input) {
        input.oninput = () => {
          const q = input.value.toLowerCase().trim();
          const items = document.querySelectorAll('.sm-item');
          items.forEach(it => {
            const data = (it.getAttribute('data-search') || '') + ' ' + (it.textContent || '');
            it.style.display = (!q || data.toLowerCase().includes(q)) ? 'flex' : 'none';
          });
        };
      }
    };
    setupSearch();

    // Execute scripts inside active views (e.g. BlogView filter logic)
    const container = document.querySelector('.asl-app-root');
    if (container) {
      const scripts = container.querySelectorAll('script');
      scripts.forEach(s => {
        try {
          const fn = new Function(s.textContent || '');
          fn();
        } catch (err) {}
      });
    }

    return () => {
      window.removeEventListener('hashchange', onHashChange);
      window.removeEventListener('popstate', onHashChange);
      window.removeEventListener('keydown', onKeyDown);
      document.removeEventListener('click', onGlobalClick);
    };
  }, [route]);

  const html = renderApp(route);

  return React.createElement('div', {
    className: 'asl-app-root w-full min-h-screen',
    dangerouslySetInnerHTML: { __html: html }
  });
}

export { App as default };
`,
          map: null
        };
      }

      // Handle HomeView.asl specifically
      if (rawFilename === 'HomeView') {
        return {
          code: `import React from 'react';
import { renderHero } from '../components/Hero.asl';
import { renderEcosystem } from '../components/Ecosystem.asl';
import { capabilitiesView } from '../components/KeyCapabilities.asl';
import { agentWayView } from '../components/TheAgentWay.asl';
import { renderWireProtocol } from '../components/AgentWireProtocol.asl';
import { harnessView } from '../components/HarnessToolkit.asl';
import { renderModuleGraphVisualizer } from '../components/ModuleGraphVisualizer.asl';
import { renderEngineeringBlog } from '../components/EngineeringBlog.asl';
import { renderInBrowserAgent } from '../components/InBrowserAgent.asl';

export function describeHomeView() {
  return '(view :id "home" :components ["hero" "ecosystem" "capabilities" "agent-way" "wire-protocol" "harness" "module-graph" "blog" "in-browser-agent"])';
}

export function renderHomeView() {
  return (
    '<main class="flex-1">' +
    renderHero() +
    renderEcosystem() +
    capabilitiesView() +
    agentWayView() +
    renderWireProtocol() +
    harnessView() +
    renderModuleGraphVisualizer() +
    renderEngineeringBlog() +
    renderInBrowserAgent() +
    '</main>'
  );
}

export default function HomeView() {
  return React.createElement('div', {
    className: 'asl-home-view',
    dangerouslySetInnerHTML: { __html: renderHomeView() }
  });
}
`,
          map: null
        };
      }

      // Handle ArticleDetailView.asl specifically
      if (rawFilename === 'ArticleDetailView') {
        const postsAsnPath = path.resolve(__dirname, '../src/data/blog/posts.asn');
        let posts: any[] = [];
        try {
          if (fs.existsSync(postsAsnPath)) {
            const raw = fs.readFileSync(postsAsnPath, 'utf-8');
            posts = parseAsnPosts(raw);
          }
        } catch (e) {}

        return {
          code: `import React from 'react';

const BLOG_POSTS = ${JSON.stringify(posts)};

function escapeHtml(str) {
  if (!str) return '';
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function renderInlineMarkdown(text) {
  let out = text.replace(/\\`([^\\`]+)\\`/g, (_, code) => {
    return '<code class="px-1.5 py-0.5 rounded bg-surface-2 border border-line text-signal font-mono text-xs">' + escapeHtml(code) + '</code>';
  });
  out = out.replace(/\\$([^\\$]+)\\$/g, (_, math) => {
    return '<span class="font-mono text-xs px-1.5 py-0.5 rounded bg-surface-2 text-cyan-300">' + escapeHtml(math) + '</span>';
  });
  out = out.replace(/\\*\\*([^*]+)\\*\\*/g, '<strong class="font-semibold text-ink">$1</strong>');
  out = out.replace(/(?<!\\*)\\*([^*]+)\\*(?!\\*)/g, '<em class="italic text-ink-2">$1</em>');
  out = out.replace(/\\[([^\\]]+)\\]\\(([^)]+)\\)/g, (_, label, url) => {
    const isExternal = url.startsWith('http') || url.startsWith('//');
    const targetAttr = isExternal ? ' target="_blank" rel="noreferrer"' : '';
    return '<a href="' + url + '" class="text-signal hover:underline underline-offset-4 decoration-signal/50 font-medium transition-colors"' + targetAttr + '>' + label + '</a>';
  });
  return out;
}

function detectCodeLang(lines) {
  const first = lines.find(l => l.trim())?.trim() || '';
  if (first.startsWith('(module') || first.startsWith('(df ') || first.startsWith('(dfs ') || first.startsWith('(defun') || first.startsWith('(defschema')) return 'asl';
  if (first.startsWith('(:') || first.startsWith('(?')) return 'asn';
  if (first.startsWith('{') || (first.startsWith('[') && first.endsWith(']'))) return 'json';
  if (first.startsWith('$ ') || first.startsWith('asl ') || first.startsWith('curl ') || first.startsWith('pnpm ') || first.startsWith('git ')) return 'bash';
  if (first.startsWith('SELECT') || first.startsWith('CREATE') || first.startsWith('INSERT')) return 'sql';
  if (first.startsWith('<svg') || first.startsWith('<div') || first.startsWith('<!doctype')) return 'html';
  return 'code';
}

export function renderMarkdownToHtml(md) {
  if (!md) return '';
  const lines = md.split('\\n');
  const out = [];

  let inCodeBlock = false;
  let codeBlockLang = '';
  let codeBlockLines = [];

  let inTable = false;
  let tableHeaders = [];
  let tableRows = [];

  let inList = false;
  let listType = 'ul';
  let listItems = [];

  let inBlockquote = false;
  let blockquoteLines = [];

  function flushList() {
    if (!inList) return;
    const tag = listType;
    const itemsHtml = listItems.map(item => '<li class="leading-relaxed">' + renderInlineMarkdown(item) + '</li>').join('\\n');
    out.push('<' + tag + ' class="my-5 space-y-2 ' + (tag === 'ul' ? 'list-disc' : 'list-decimal') + ' list-inside text-ink-2 text-sm sm:text-base pl-2">' + itemsHtml + '</' + tag + '>');
    inList = false;
    listItems = [];
  }

  function flushBlockquote() {
    if (!inBlockquote) return;
    const innerHtml = blockquoteLines.map(line => renderInlineMarkdown(line)).join('<br/>');
    out.push('<blockquote class="my-6 border-l-2 border-signal pl-4 sm:pl-6 py-2 bg-signal/5 rounded-r-xl text-ink-2 italic">' + innerHtml + '</blockquote>');
    inBlockquote = false;
    blockquoteLines = [];
  }

  function flushTable() {
    if (!inTable) return;
    const thead = tableHeaders.map(h => '<th class="p-3 font-semibold text-ink border-b border-line bg-surface-2/80">' + renderInlineMarkdown(h) + '</th>').join('');
    const tbody = tableRows.map(row => {
      const tds = row.map(cell => '<td class="p-3 border-b border-line/60">' + renderInlineMarkdown(cell) + '</td>').join('');
      return '<tr class="hover:bg-surface-2/40 transition-colors">' + tds + '</tr>';
    }).join('\\n');
    out.push('<div class="my-8 overflow-x-auto rounded-2xl border border-line bg-surface/50 shadow-e1"><table class="w-full text-left border-collapse text-xs sm:text-sm font-mono"><thead><tr>' + thead + '</tr></thead><tbody class="divide-y divide-line/60 text-ink-2">' + tbody + '</tbody></table></div>');
    inTable = false;
    tableHeaders = [];
    tableRows = [];
  }

  let startIdx = 0;
  while (startIdx < lines.length && !lines[startIdx].trim()) startIdx++;
  if (startIdx < lines.length && lines[startIdx].startsWith('# ')) {
    startIdx++;
    while (startIdx < lines.length && !lines[startIdx].trim()) startIdx++;
    if (startIdx < lines.length && (lines[startIdx].startsWith('*By ') || lines[startIdx].startsWith('By '))) {
      startIdx++;
    }
  }

  for (let i = startIdx; i < lines.length; i++) {
    const rawLine = lines[i];
    const trimmed = rawLine.trim();

    if (trimmed.startsWith('\`\`\`')) {
      if (inCodeBlock) {
        const langLower = (codeBlockLang || '').toLowerCase().trim();
        if (langLower === 'mermaid') {
          const rawDiagram = codeBlockLines.join('\\n');
          out.push('<div class="my-8 rounded-2xl border border-line bg-surface/80 p-4 sm:p-6 shadow-e1"><div class="flex items-center justify-between px-2 pb-3 mb-3 border-b border-line/50 text-micro font-mono text-ink-3"><span class="font-semibold uppercase tracking-wider text-signal flex items-center gap-1.5"><svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="12 2 2 7 12 12 22 7 12 2"></polygon><polyline points="2 17 12 22 22 17"></polyline><polyline points="2 12 12 17 22 12"></polyline></svg>Architecture Flow</span><span class="text-[10px] opacity-70 font-mono">Mermaid Visualizer</span></div><div class="asl-mermaid-diagram flex justify-center items-center overflow-x-auto py-2"><pre class="mermaid text-xs font-mono select-all">' + escapeHtml(rawDiagram) + '</pre></div></div>');
        } else {
          const escaped = escapeHtml(codeBlockLines.join('\\n'));
          const badgeLang = codeBlockLang || detectCodeLang(codeBlockLines);
          const subBadge = (badgeLang === 'asl' || badgeLang === 'asn') ? 'pure AST' : 'spec';
          out.push('<div class="relative my-6 rounded-2xl border border-line bg-ground overflow-hidden shadow-e1 group"><div class="flex items-center justify-between px-4 py-2 bg-surface-2/60 border-b border-line text-micro font-mono text-ink-3"><span class="font-semibold uppercase tracking-wider text-signal">' + badgeLang + '</span><div class="flex items-center gap-3"><span class="text-[10px] opacity-70">' + subBadge + '</span><button type="button" class="asl-copy-code-btn px-2 py-0.5 rounded text-[10px] text-ink-3 hover:text-signal hover:bg-surface-2 transition-colors border border-transparent hover:border-line/60" onclick="(function(btn){var code = btn.closest(\\x27.group\\x27).querySelector(\\x27code\\x27);if (code) {navigator.clipboard.writeText(code.innerText).then(function() {var old = btn.textContent;btn.textContent = \\x27Copied!\\x27;btn.classList.add(\\x27text-signal\\x27);setTimeout(function(){ btn.textContent = old; btn.classList.remove(\\x27text-signal\\x27); }, 2000);});}})(this)">Copy</button></div></div><pre class="p-4 sm:p-5 overflow-x-auto font-mono text-xs sm:text-sm text-ink leading-relaxed"><code>' + escaped + '</code></pre></div>');
        }
        inCodeBlock = false;
        codeBlockLang = '';
        codeBlockLines = [];
      } else {
        flushList();
        flushBlockquote();
        flushTable();
        inCodeBlock = true;
        codeBlockLang = trimmed.slice(3).trim();
        codeBlockLines = [];
      }
      continue;
    }

    if (inCodeBlock) {
      codeBlockLines.push(rawLine);
      continue;
    }

    if (trimmed.startsWith('<!--') && trimmed.endsWith('-->')) {
      continue;
    }

    if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
      flushList();
      flushBlockquote();
      const cells = trimmed.slice(1, -1).split('|').map(c => c.trim());
      const isSeparator = cells.every(c => /^:?-+:?$/.test(c));
      if (isSeparator) continue;
      if (!inTable) {
        inTable = true;
        tableHeaders = cells;
        tableRows = [];
      } else {
        tableRows.push(cells);
      }
      continue;
    } else if (inTable) {
      flushTable();
    }

    if (trimmed.startsWith('>')) {
      flushList();
      flushTable();
      inBlockquote = true;
      blockquoteLines.push(trimmed.replace(/^>\\s?/, ''));
      continue;
    } else if (inBlockquote) {
      flushBlockquote();
    }

    if (!trimmed) {
      flushList();
      flushBlockquote();
      flushTable();
      continue;
    }

    if (trimmed === '---' || trimmed === '***' || trimmed === '___') {
      flushList();
      flushBlockquote();
      flushTable();
      out.push('<hr class="my-10 border-line" />');
      continue;
    }

    if (trimmed.startsWith('$$') && trimmed.endsWith('$$') && trimmed.length > 4) {
      flushList();
      flushBlockquote();
      flushTable();
      const math = trimmed.slice(2, -2).trim();
      out.push('<div class="my-6 p-4 rounded-xl border border-line bg-surface/50 text-center font-mono text-sm text-cyan-300 overflow-x-auto">' + escapeHtml(math) + '</div>');
      continue;
    }

    if (trimmed.startsWith('#### ')) {
      flushList();
      flushBlockquote();
      flushTable();
      out.push('<h4 class="text-base sm:text-lg font-bold text-ink mt-8 mb-3 tracking-tight">' + renderInlineMarkdown(trimmed.slice(5)) + '</h4>');
      continue;
    }
    if (trimmed.startsWith('### ')) {
      flushList();
      flushBlockquote();
      flushTable();
      out.push('<h3 class="text-lg sm:text-xl font-bold text-ink mt-10 mb-4 tracking-tight">' + renderInlineMarkdown(trimmed.slice(4)) + '</h3>');
      continue;
    }
    if (trimmed.startsWith('## ')) {
      flushList();
      flushBlockquote();
      flushTable();
      out.push('<h2 class="text-xl sm:text-2xl font-extrabold text-ink mt-14 mb-5 tracking-tight pb-3 border-b border-line">' + renderInlineMarkdown(trimmed.slice(3)) + '</h2>');
      continue;
    }
    if (trimmed.startsWith('# ')) {
      flushList();
      flushBlockquote();
      flushTable();
      out.push('<h1 class="text-2xl sm:text-3xl font-extrabold text-ink mt-16 mb-6 tracking-tight">' + renderInlineMarkdown(trimmed.slice(2)) + '</h1>');
      continue;
    }

    const ulMatch = trimmed.match(/^[-*]\\s+(.*)$/);
    if (ulMatch) {
      flushBlockquote();
      flushTable();
      if (!inList || listType !== 'ul') {
        flushList();
        inList = true;
        listType = 'ul';
      }
      listItems.push(ulMatch[1]);
      continue;
    }

    const olMatch = trimmed.match(/^(\\d+)\\.\\s+(.*)$/);
    if (olMatch) {
      flushBlockquote();
      flushTable();
      if (!inList || listType !== 'ol') {
        flushList();
        inList = true;
        listType = 'ol';
      }
      listItems.push(olMatch[2]);
      continue;
    }

    flushList();
    flushBlockquote();
    flushTable();

    out.push('<p class="text-sm sm:text-base text-ink-2 leading-relaxed mb-6 font-normal">' + renderInlineMarkdown(trimmed) + '</p>');
  }

  flushList();
  flushBlockquote();
  flushTable();

  return out.join('\\n');
}

export function getBlogPostBySlug(slug) {
  return BLOG_POSTS.find(p => p.slug === slug) || null;
}

export function getRelatedPosts(currentSlug, limit = 2) {
  const current = getBlogPostBySlug(currentSlug);
  if (!current) return BLOG_POSTS.slice(0, limit);
  const currentTags = current.tags || [];
  return BLOG_POSTS.filter(
    p => p.slug !== currentSlug && (p.category === current.category || (p.tags || []).some(t => currentTags.includes(t)))
  ).slice(0, limit);
}

export function describeArticleDetailView() {
  return '(view :id "article-detail" :components ["navigation" "header" "body" "citation" "related"])';
}

export function renderArticleDetailView(slug) {
  const post = getBlogPostBySlug(slug);

  if (!post) {
    return (
      '<main class="flex-1 max-w-4xl mx-auto px-4 sm:px-6 py-16 sm:py-24 w-full" id="bv-article-404">' +
      '<a href="/blog" class="asl-article-back inline-flex items-center gap-2 text-xs font-mono text-ink-2 hover:text-signal transition-colors mb-10 group">' +
      '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="group-hover:-translate-x-1 transition-transform">' +
      '<line x1="19" y1="12" x2="5" y2="12"></line><polyline points="12 19 5 12 12 5"></polyline></svg>' +
      '<span>Back to all essays</span></a>' +
      '<div class="p-8 sm:p-12 rounded-3xl border border-line bg-surface/70 text-center space-y-4 shadow-e2">' +
      '<div class="inline-flex items-center justify-center w-12 h-12 rounded-2xl bg-signal/10 border border-signal/20 text-signal font-mono font-bold text-lg">404</div>' +
      '<h1 class="text-2xl sm:text-3xl font-bold text-ink">Essay Not Found</h1>' +
      '<p class="text-sm sm:text-base text-ink-2 max-w-md mx-auto">The technical essay "' + escapeHtml(slug) + '" could not be located in the current publication registry.</p>' +
      '<div class="pt-4"><a href="/blog" class="asl-article-back inline-flex items-center gap-2 px-5 py-2.5 rounded-xl bg-signal text-ground font-mono text-xs font-semibold shadow-sm hover:opacity-95 transition-all">Return to Blog Catalog &rarr;</a></div>' +
      '</div></main>'
    );
  }

  const related = getRelatedPosts(slug, 2);
  const bodyHtml = renderMarkdownToHtml(post.content);

  const tagsHtml = (post.tags || [])
    .map(t => '<span class="inline-flex items-center text-[10px] font-mono px-2 py-0.5 rounded-md bg-surface-2 border border-line/60 text-ink-3">#' + escapeHtml(t) + '</span>')
    .join(' ');

  const importanceBadge = post.importance === 'flagship'
    ? '<span class="px-2 py-0.5 rounded border border-cyan-400/40 bg-cyan-400/10 text-cyan-300 font-semibold text-[10px]">★ Flagship</span>'
    : '<span class="px-2 py-0.5 rounded border border-line bg-surface-2 text-ink-3 font-mono text-[10px] uppercase">' + escapeHtml(post.importance || 'technical') + '</span>';

  const relatedHtml = related.length > 0 ? (
    '<section class="mt-20 pt-12 border-t border-line">' +
    '<div class="flex items-center justify-between mb-8">' +
    '<h3 class="text-lg sm:text-xl font-bold text-ink font-sans">Related Engineering Essays</h3>' +
    '<a href="/blog" class="asl-article-back text-xs font-mono text-signal hover:underline">View all &rarr;</a>' +
    '</div>' +
    '<div class="grid grid-cols-1 md:grid-cols-2 gap-6">' +
    related.map(r => (
      '<article class="bv-post-card p-6 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2" data-slug="' + escapeHtml(r.slug) + '">' +
      '<div><div class="flex items-center justify-between text-micro font-mono text-ink-3 mb-3">' +
      '<span class="px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium">' + escapeHtml(r.category) + '</span>' +
      '<span>' + escapeHtml(r.readTime) + '</span></div>' +
      '<h4 class="text-base font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2">' + escapeHtml(r.title) + '</h4>' +
      '<p class="text-meta text-ink-2 line-clamp-2 mb-4">' + escapeHtml(r.excerpt) + '</p></div>' +
      '<div class="flex items-center justify-between pt-3 border-t border-line/60 text-micro font-mono text-ink-3">' +
      '<span>' + escapeHtml(r.date) + ' • ' + escapeHtml(r.author) + '</span>' +
      '<span class="text-signal font-semibold group-hover:translate-x-0.5 transition-transform">&rarr;</span></div></article>'
    )).join('') +
    '</div></section>'
  ) : '';

  const mermaidScript = bodyHtml.includes('class="mermaid') ? (
    '<script>' +
    '(function() {' +
    '  function runMermaid() {' +
    '    var targets = document.querySelectorAll(\\x27pre.mermaid:not([data-processed="true"])\\x27);' +
    '    if (!targets || targets.length === 0) return;' +
    '    if (window.mermaid) {' +
    '      try {' +
    '        window.mermaid.initialize({' +
    '          startOnLoad: false,' +
    '          theme: \\x27dark\\x27,' +
    '          securityLevel: \\x27loose\\x27,' +
    '          fontFamily: \\x27Fira Code, monospace\\x27,' +
    '          themeVariables: {' +
    '            darkMode: true,' +
    '            background: \\x27#0d1117\\x27,' +
    '            primaryColor: \\x27#00f2ff\\x27,' +
    '            primaryTextColor: \\x27#e6edf3\\x27,' +
    '            primaryBorderColor: \\x27#30363d\\x27,' +
    '            lineColor: \\x27#58a6ff\\x27,' +
    '            secondaryColor: \\x27#161b22\\x27,' +
    '            tertiaryColor: \\x27#21262d\\x27' +
    '          }' +
    '        });' +
    '        window.mermaid.run({ nodes: targets });' +
    '      } catch(e) {' +
    '        console.warn(\\x27Mermaid render error:\\x27, e);' +
    '      }' +
    '    } else {' +
    '      if (!document.getElementById(\\x27mermaid-cdn-script\\x27)) {' +
    '        var s = document.createElement(\\x27script\\x27);' +
    '        s.id = \\x27mermaid-cdn-script\\x27;' +
    '        s.src = \\x27https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js\\x27;' +
    '        s.onload = function() {' +
    '          setTimeout(runMermaid, 50);' +
    '        };' +
    '        document.head.appendChild(s);' +
    '      } else {' +
    '        setTimeout(runMermaid, 150);' +
    '      }' +
    '    }' +
    '  }' +
    '  setTimeout(runMermaid, 50);' +
    '})();' +
    '</script>'
  ) : '';

  return (
    '<main class="flex-1 max-w-4xl mx-auto px-4 sm:px-6 py-12 sm:py-16 w-full" id="bv-article-view">' +
    '<div class="mb-10 sm:mb-14 flex items-center justify-between">' +
    '<a href="/blog" class="asl-article-back inline-flex items-center gap-2 text-xs font-mono text-ink-2 hover:text-signal transition-colors group">' +
    '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="group-hover:-translate-x-1 transition-transform">' +
    '<line x1="19" y1="12" x2="5" y2="12"></line><polyline points="12 19 5 12 12 5"></polyline></svg>' +
    '<span>Back to all essays</span></a>' +
    '<div class="flex items-center gap-2 text-micro font-mono text-ink-3">' +
    '<span>' + escapeHtml(post.date) + '</span><span>•</span><span>' + escapeHtml(post.readTime) + '</span></div></div>' +
    '<header class="mb-12 sm:mb-16"><div class="flex items-center gap-2 flex-wrap mb-4">' +
    '<span class="px-2.5 py-0.5 rounded-full border border-signal/30 bg-signal/5 text-signal font-mono text-micro uppercase tracking-wider font-semibold">' +
    escapeHtml(post.category) + '</span>' + importanceBadge + '</div>' +
    '<h1 class="text-2xl sm:text-4xl md:text-5xl font-extrabold text-ink tracking-tight leading-tight text-balance mb-6">' +
    escapeHtml(post.title) + '</h1>' +
    '<p class="text-base sm:text-xl text-ink-2 leading-relaxed font-normal text-balance mb-8">' +
    escapeHtml(post.excerpt) + '</p>' +
    '<div class="flex items-center justify-between flex-wrap gap-4 pt-6 border-t border-line/80 text-xs font-mono text-ink-3">' +
    '<div class="flex items-center gap-3">' +
    '<div class="w-8 h-8 rounded-full bg-signal/15 border border-signal/30 flex items-center justify-center text-signal font-bold text-xs">' +
    escapeHtml(post.author.slice(0, 2).toUpperCase()) + '</div>' +
    '<div><div class="font-semibold text-ink">' + escapeHtml(post.author) + '</div>' +
    '<div class="text-micro text-ink-3">AgentScript Systems Research</div></div></div>' +
    '<div class="flex items-center gap-1.5 flex-wrap">' + tagsHtml + '</div></div></header>' +
    '<div class="article-body text-ink border-t border-line pt-8">' + bodyHtml + '</div>' +
    '<div class="my-16 p-6 sm:p-8 rounded-2xl border border-line bg-surface/80 shadow-e1">' +
    '<div class="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">' +
    '<div class="space-y-1"><div class="text-xs font-mono font-semibold text-signal uppercase tracking-wider">Canonical Citation</div>' +
    '<div class="text-sm font-semibold text-ink">' + escapeHtml(post.title) + '</div>' +
    '<div class="text-micro font-mono text-ink-3">Published ' + escapeHtml(post.date) + ' • GenSEAM Systems Group • aslang.dev/blog/' + escapeHtml(post.slug) + '</div></div>' +
    '<a href="/blog" class="asl-article-back shrink-0 px-4 py-2 rounded-xl border border-line hover:border-signal text-xs font-mono text-ink-2 hover:text-signal transition-colors bg-surface-2/60">&larr; Return to Index</a></div></div>' +
    relatedHtml +
    mermaidScript +
    '</main>'
  );
}

export function articleDetailView(slug) {
  return renderArticleDetailView(slug);
}

export function ArticleDetailView({ slug = '', className = '', ...props } = {}) {
  const html = renderArticleDetailView(slug);
  return React.createElement('div', {
    className: 'asl-articledetailview ' + className,
    dangerouslySetInnerHTML: { __html: html }
  });
}

export { ArticleDetailView as default };
`,
          map: null
        };
      }

function parseConcat(fnCode: string): Array<{ type: 'str' | 'call'; val?: string; name?: string }> | null {
  const withoutDoc = fnCode.replace(/:d\s+"(?:[^"\\]|\\.)*"/, '');
  const concatIdx = withoutDoc.indexOf('(s/concat');
  if (concatIdx === -1) return null;

  let p = concatIdx + 9;
  const parts: Array<{ type: 'str' | 'call'; val?: string; name?: string }> = [];
  while (p < withoutDoc.length) {
    while (p < withoutDoc.length && /\s/.test(withoutDoc[p])) p++;
    if (withoutDoc[p] === ')') break;

    if (withoutDoc[p] === '"') {
      p++;
      let s = '';
      while (p < withoutDoc.length) {
        if (withoutDoc[p] === '\\' && p + 1 < withoutDoc.length) {
          const nextChar = withoutDoc[p + 1];
          if (nextChar === 'n') s += '\n';
          else if (nextChar === 't') s += '\t';
          else if (nextChar === 'r') s += '\r';
          else s += nextChar;
          p += 2;
        } else if (withoutDoc[p] === '"') {
          p++;
          break;
        } else {
          s += withoutDoc[p++];
        }
      }
      parts.push({ type: 'str', val: s });
    } else if (withoutDoc[p] === '(') {
      let depth = 1;
      let start = p;
      p++;
      while (p < withoutDoc.length && depth > 0) {
        if (withoutDoc[p] === '(') depth++;
        else if (withoutDoc[p] === ')') depth--;
        p++;
      }
      const expr = withoutDoc.slice(start, p);
      const callMatch = expr.match(/^\(([a-zA-Z0-9_-]+)\)/);
      if (callMatch) {
        parts.push({ type: 'call', name: callMatch[1] });
      }
    } else {
      p++;
    }
  }
  return parts;
}

function parseFunctions(str: string) {
  const fns: Array<{ name: string; code: string }> = [];
  let pos = 0;
  while (pos < str.length) {
    const dfIdx = str.indexOf('(df ', pos);
    if (dfIdx === -1) break;
    let p = dfIdx;
    let depth = 0;
    let inStr = false;
    let endIdx = -1;
    while (p < str.length) {
      const ch = str[p];
      if (ch === '\\' && inStr) { p += 2; continue; }
      if (ch === '"') inStr = !inStr;
      else if (!inStr) {
        if (ch === '(') depth++;
        else if (ch === ')') {
          depth--;
          if (depth === 0) { endIdx = p + 1; break; }
        }
      }
      p++;
    }
    if (endIdx !== -1) {
      const fnDef = str.slice(dfIdx, endIdx);
      const nameMatch = fnDef.match(/^\(df\s+([a-zA-Z0-9_-]+)/);
      if (nameMatch) fns.push({ name: nameMatch[1], code: fnDef });
      pos = endIdx;
    } else {
      pos = dfIdx + 4;
    }
  }
  return fns;
}

function extractStrings(str: string) {
  const strs: string[] = [];
  let pos = 0;
  while (pos < str.length) {
    if (str[pos] === '"') {
      pos++;
      let s = '';
      while (pos < str.length) {
        if (str[pos] === '\\' && pos + 1 < str.length) {
          const nextChar = str[pos + 1];
          if (nextChar === 'n') s += '\n';
          else if (nextChar === 't') s += '\t';
          else if (nextChar === 'r') s += '\r';
          else s += nextChar;
          pos += 2;
        } else if (str[pos] === '"') {
          pos++;
          break;
        } else {
          s += str[pos++];
        }
      }
      strs.push(s);
    } else {
      pos++;
    }
  }
  return strs;
}

      // For all other .asl files: transpile their functions!
      const parsedFns = parseFunctions(content);
      const exportedFns: string[] = [];
      const exportedComponents: string[] = [];

      for (const fn of parsedFns) {
        const fnNameKebab = fn.name;
        const fnNameCamel = fnNameKebab.replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase());
        const fnNamePascal = fnNameCamel.charAt(0).toUpperCase() + fnNameCamel.slice(1);
        const codeWithoutDoc = fn.code.replace(/:d\s+"(?:[^"\\]|\\.)*"/, '');
        if (codeWithoutDoc.includes('(s/concat')) {
          const concatParts = parseConcat(codeWithoutDoc);
          if (concatParts && concatParts.length > 0) {
            const codeExpr = concatParts.map(p => {
              if (p.type === 'str') return JSON.stringify(parseSExpToHtml(p.val));
              const camel = p.name.replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase());
              return `(typeof ${camel} === 'function' ? ${camel}() : '')`;
            }).join(' + ');
            exportedFns.push(`export function ${fnNameCamel}() {\n  return ${codeExpr || '""'};\n}`);
          } else {
            exportedFns.push(`export function ${fnNameCamel}() {\n  return "";\n}`);
          }
        } else {
          let strs = extractStrings(codeWithoutDoc);
          let resolvedStr = strs.map(parseSExpToHtml).join('');
          if (!resolvedStr) {
            const aliasMatch = codeWithoutDoc.match(/\(([a-zA-Z0-9_-]+)\)/);
            if (aliasMatch) {
              const calleeCamel = aliasMatch[1].replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase());
              exportedFns.push(`export function ${fnNameCamel}() {\n  return typeof ${calleeCamel} === 'function' ? ${calleeCamel}() : '';\n}`);
            } else {
              exportedFns.push(`export function ${fnNameCamel}() {\n  return "";\n}`);
            }
          } else {
            exportedFns.push(`export function ${fnNameCamel}() {\n  return ${JSON.stringify(resolvedStr)};\n}`);
          }
        }

        exportedComponents.push(`export function ${fnNamePascal}({ className = '', title = '', strokeWidth, ...props } = {}) {
  let html = typeof ${fnNameCamel} === 'function' ? ${fnNameCamel}() : '';
  if (className) {
    if (html.startsWith('<svg')) {
      html = html.replace(/<svg\\b([^>]*)>/, (m, rest) => {
        if (rest.includes('class="')) {
          return \`<svg\${rest.replace(/class="[^"]*"/, \`class="\${className}"\`)}>\`;
        }
        return \`<svg class="\${className}"\${rest}>\`;
      });
    } else {
      html = html.replace(/^(<[a-z0-9]+)\\b([^>]*)>/, (m, tag, rest) => {
        if (rest.includes('class="')) {
          return \`\${tag}\${rest.replace(/class="([^"]*)"/, (_, cls) => \`class="\${cls} \${className}"\`)}>\`;
        }
        return \`\${tag} class="\${className}"\${rest}>\`;
      });
    }
  }
  if (title && html.includes('<svg')) {
    html = html.replace(/aria-label="[^"]*"/, \`aria-label="\${title}"\`);
  }
  if (strokeWidth && html.includes('<svg')) {
    html = html.replace(/stroke-width="[^"]*"/g, \`stroke-width="\${strokeWidth}"\`);
  }
  return React.createElement('span', {
    className: 'asl-comp-wrapper ' + (className || ''),
    style: { display: 'contents' },
    dangerouslySetInnerHTML: { __html: html }
  });
}`);
      }

      const componentName = rawFilename
        .replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase())
        .replace(/^[a-z]/, (c) => c.toUpperCase());

      const primaryRenderFn = exportedFns.find(fn => fn.includes('render') || fn.includes('View'));
      const renderFnName = primaryRenderFn ? primaryRenderFn.split(' ')[2].split('(')[0] : null;

      const alreadyDeclared = exportedComponents.some(c => c.startsWith(`export function ${componentName}(`));
      const defaultComponentDecl = alreadyDeclared
        ? `export { ${componentName} as default };\n`
        : `export function ${componentName}({ className = '', ...props } = {}) {\n` +
          `  const html = typeof ${renderFnName} === 'function' ? ${renderFnName}(props) : '';\n` +
          `  return React.createElement('div', {\n` +
          `    className: 'asl-${rawFilename.toLowerCase()} ' + (className || ''),\n` +
          `    dangerouslySetInnerHTML: html ? { __html: html } : undefined\n` +
          `  }, (!html && props && props.children) || null);\n` +
          `}\nexport { ${componentName} as default };\n`;

      return {
        code: `import React from 'react';\n\n` +
          exportedFns.join('\n\n') + '\n\n' +
          exportedComponents.join('\n\n') + '\n\n' +
          defaultComponentDecl,
        map: null
      };
    }
  };
}

