import fs from 'fs';
import path from 'path';

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
import { renderHomeView } from './views/HomeView.asl';
import { renderDocsView } from './views/DocsView.asl';
import { renderBlogView } from './views/BlogView.asl';
import { renderStudioView } from './views/StudioView.asl';
import { renderPlaygroundView } from './views/PlaygroundView.asl';
import { renderRoadmapView } from './views/RoadmapView.asl';
import { renderEcosystemView } from './views/EcosystemView.asl';

export function appRoutes() {
  return ['/', '/studio', '/playground', '/ecosystem', '/roadmap', '/docs', '/blog'];
}

export function renderView(route) {
  if (route === '/studio' || route === '#studio') return renderStudioView();
  if (route === '/playground' || route === '#playground') return renderPlaygroundView();
  if (route === '/ecosystem' || route === '#ecosystem') return renderEcosystemView();
  if (route === '/roadmap' || route === '#roadmap') return renderRoadmapView();
  if (route === '/docs' || route === '#docs') return renderDocsView();
  if (route === '/blog' || route === '#blog') return renderBlogView();
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
    '</div>'
  );
}

export function App() {
  const [route, setRoute] = useState(() => {
    if (typeof window !== 'undefined') {
      return window.location.hash || window.location.pathname || '/';
    }
    return '/';
  });

  useEffect(() => {
    const onHashChange = () => {
      const r = window.location.hash || window.location.pathname || '/';
      setRoute(r);
      if (!window.location.hash.startsWith('#capabilities') && !window.location.hash.startsWith('#matrix') && !window.location.hash.startsWith('#wire-protocol')) {
        window.scrollTo(0, 0);
      }
    };
    window.addEventListener('hashchange', onHashChange);
    window.addEventListener('popstate', onHashChange);
    return () => {
      window.removeEventListener('hashchange', onHashChange);
      window.removeEventListener('popstate', onHashChange);
    };
  }, []);

  const html = renderApp(route);

  return React.createElement('div', {
    className: 'asl-app-root w-full min-h-screen',
    dangerouslySetInnerHTML: { __html: html }
  });
}

export default App;
`,
          map: null
        };
      }

      // Handle HomeView.asl specifically
      if (rawFilename === 'HomeView') {
        return {
          code: `import React from 'react';
import { renderHero } from '../components/Hero.asl';
import { capabilitiesView } from '../components/KeyCapabilities.asl';
import { agentWayView } from '../components/TheAgentWay.asl';
import { renderWireProtocol } from '../components/AgentWireProtocol.asl';
import { harnessView } from '../components/HarnessToolkit.asl';
import { renderPackageMatrix } from '../components/UnifiedPackageMatrix.asl';
import { renderEngineeringBlog } from '../components/EngineeringBlog.asl';

export function describeHomeView() {
  return '(view :id "home" :components ["hero" "capabilities" "agent-way" "wire-protocol" "harness" "matrix" "blog"])';
}

export function renderHomeView() {
  return (
    '<main class="flex-1">' +
    renderHero() +
    capabilitiesView() +
    agentWayView() +
    renderWireProtocol() +
    harnessView() +
    renderPackageMatrix() +
    renderEngineeringBlog() +
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
          s += str[pos + 1];
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

        exportedComponents.push(`export const ${fnNamePascal} = ({ className = '', title = '', strokeWidth, ...props } = {}) => {
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
};`);
      }

      const componentName = rawFilename
        .replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase())
        .replace(/^[a-z]/, (c) => c.toUpperCase());

      const primaryRenderFn = exportedFns.find(fn => fn.includes('render') || fn.includes('View'));
      const renderFnName = primaryRenderFn ? primaryRenderFn.split(' ')[2].split('(')[0] : null;

      const alreadyDeclared = exportedComponents.some(c => c.startsWith(`export const ${componentName} =`));
      const defaultComponentDecl = alreadyDeclared
        ? ''
        : `export const ${componentName} = ({ className = '', ...props } = {}) => {\n` +
          `  const html = typeof ${renderFnName} === 'function' ? ${renderFnName}(props) : '';\n` +
          `  return React.createElement('div', {\n` +
          `    className: 'asl-${rawFilename.toLowerCase()} ' + (className || ''),\n` +
          `    dangerouslySetInnerHTML: html ? { __html: html } : undefined\n` +
          `  }, (!html && props && props.children) || null);\n` +
          `};\n\n`;

      return {
        code: `import React from 'react';\n\n` +
          exportedFns.join('\n\n') + '\n\n' +
          exportedComponents.join('\n\n') + '\n\n' +
          defaultComponentDecl +
          `export default ${componentName};\n`,
        map: null
      };
    }
  };
}

