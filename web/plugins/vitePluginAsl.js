import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Parses canonical posts.asn S-expression into structured post records.
 */
export function parseAsnPosts(raw) {
  const tokens = [];
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
  function parseNode() {
    if (i >= tokens.length) return null;
    const t = tokens[i++];
    if (t.type === 'str') return t.val;
    if (t.type === 'atom') {
      if (!isNaN(Number(t.val))) return Number(t.val);
      return t.val;
    }
    if (t.type === '[') {
      const arr = [];
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
      const obj = { _tag: tag.val };
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
  return children.map((p) => ({
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
export function parseSExpToHtml(str) {
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

  const tokens = [];
  let tok;
  while ((tok = parseToken()) !== null) {
    tokens.push(tok);
  }

  let idx = 0;
  function parseNode() {
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
      const attrs = {};
      const children = [];

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
 * Escapes characters for strict XML validity.
 */
export function escapeXml(unsafe) {
  if (!unsafe) return '';
  return String(unsafe)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

/**
 * Formats YYYY-MM-DD string into RFC-822 / RFC-1123 date string for RSS.
 */
export function formatRssDate(dateStr) {
  if (!dateStr) return new Date().toUTCString();
  const d = new Date(dateStr + 'T00:00:00Z');
  return isNaN(d.getTime()) ? new Date().toUTCString() : d.toUTCString();
}

/**
 * Returns sitemap metadata (priority, changefreq) for standard routes.
 */
export function getRouteMetadata(route) {
  switch (route) {
    case '/':
      return { priority: '1.0', changefreq: 'daily' };
    case '/blog':
      return { priority: '0.95', changefreq: 'daily' };
    case '/docs':
      return { priority: '0.9', changefreq: 'weekly' };
    case '/llms.txt':
    case '/llms-full.txt':
      return { priority: '0.95', changefreq: 'weekly' };
    case '/roadmap':
    case '/playground':
    case '/ecosystem':
      return { priority: '0.8', changefreq: 'weekly' };
    default:
      return { priority: '0.7', changefreq: 'weekly' };
  }
}

/**
 * Generates canonical RSS 2.0 XML from posts catalog.
 */
export function generateRssXml(posts) {
  const latestDate = posts.map(p => p.date).filter(Boolean).sort().reverse()[0];
  const lastBuild = latestDate ? formatRssDate(latestDate) : new Date().toUTCString();

  const itemsXml = posts.map(p => {
    const title = escapeXml(p.title);
    const link = `https://aslang.dev/blog/${escapeXml(p.slug)}`;
    const desc = escapeXml(p.excerpt);
    const pubDate = formatRssDate(p.date);
    const author = escapeXml(p.author ? `${p.author} (GenSEAM)` : 'dev@aslang.dev (GenSEAM)');
    const category = escapeXml(p.category || 'Engineering');
    return `    <item>
      <title>${title}</title>
      <link>${link}</link>
      <guid isPermaLink="true">${link}</guid>
      <pubDate>${pubDate}</pubDate>
      <author>${author}</author>
      <category>${category}</category>
      <description>${desc}</description>
    </item>`;
  }).join('\n');

  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>AgentScript (ASL) — Engineering &amp; Systems Blog</title>
    <link>https://aslang.dev/blog</link>
    <description>Technical essays, architecture deep-dives, and compiler benchmarks for the AgentScript language and GenSEAM ecosystem.</description>
    <language>en-us</language>
    <lastBuildDate>${lastBuild}</lastBuildDate>
    <atom:link href="https://aslang.dev/rss.xml" rel="self" type="application/rss+xml" />
${itemsXml}
  </channel>
</rss>
`;
}

/**
 * Generates canonical Sitemap XML from router pages and blog catalog.
 */
export function generateSitemapXml(routes, posts) {
  const baseUrl = 'https://aslang.dev';
  const latestDate = posts.map(p => p.date).filter(Boolean).sort().reverse()[0] || new Date().toISOString().split('T')[0];

  const allStaticRoutes = Array.from(new Set([...routes, '/llms.txt', '/llms-full.txt']));

  const staticUrls = allStaticRoutes.map(r => {
    const meta = getRouteMetadata(r);
    const loc = r === '/' ? `${baseUrl}/` : `${baseUrl}${r}`;
    return `  <url>
    <loc>${loc}</loc>
    <lastmod>${latestDate}</lastmod>
    <changefreq>${meta.changefreq}</changefreq>
    <priority>${meta.priority}</priority>
  </url>`;
  });

  const postUrls = posts.map(p => {
    const loc = `${baseUrl}/blog/${p.slug}`;
    const lastmod = p.date || latestDate;
    const priority = p.importance === 'flagship' ? '0.9' : '0.8';
    return `  <url>
    <loc>${loc}</loc>
    <lastmod>${lastmod}</lastmod>
    <changefreq>monthly</changefreq>
    <priority>${priority}</priority>
  </url>`;
  });

  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://www.sitemaps.org/schemas/sitemap/0.9
        http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd">
${staticUrls.join('\n\n')}

${postUrls.join('\n\n')}
</urlset>
`;
}

/**
 * Synchronizes generated RSS and Sitemap to public and dist directories.
 */
export function syncRssAndSitemap() {
  try {
    const postsAsnPath = path.resolve(__dirname, '../src/data/blog/posts.asn');
    if (!fs.existsSync(postsAsnPath)) return;
    const raw = fs.readFileSync(postsAsnPath, 'utf-8');
    const posts = parseAsnPosts(raw);
    const routes = ['/', '/blog', '/docs', '/roadmap', '/playground', '/ecosystem'];

    const rssXml = generateRssXml(posts);
    const sitemapXml = generateSitemapXml(routes, posts);

    const publicDir = path.resolve(__dirname, '../public');
    if (fs.existsSync(publicDir)) {
      fs.writeFileSync(path.join(publicDir, 'rss.xml'), rssXml, 'utf-8');
      fs.writeFileSync(path.join(publicDir, 'sitemap.xml'), sitemapXml, 'utf-8');
    }

    const distDir = path.resolve(__dirname, '../dist');
    if (fs.existsSync(distDir)) {
      fs.writeFileSync(path.join(distDir, 'rss.xml'), rssXml, 'utf-8');
      fs.writeFileSync(path.join(distDir, 'sitemap.xml'), sitemapXml, 'utf-8');
    }
  } catch (e) {
    console.warn('[vite-plugin-asl] Failed to sync RSS and Sitemap:', e);
  }
}

/**
 * Zero-overhead Vite plugin for AgentScript (ASL)
 */
export function aslPlugin() {
  return {
    name: 'vite-plugin-asl',
    enforce: 'pre',

    buildStart() {
      syncRssAndSitemap();
    },

    configureServer(server) {
      syncRssAndSitemap();
      const postsAsnPath = path.resolve(__dirname, '../src/data/blog/posts.asn');
      server.watcher.add(postsAsnPath);
      server.watcher.on('change', (file) => {
        if (file === postsAsnPath) {
          syncRssAndSitemap();
        }
      });
    },

    closeBundle() {
      syncRssAndSitemap();
    },

    resolveId(id, importer) {
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

    load(id) {
      if (!id.includes('.asl')) return null;

      const cleanId = id.split('?')[0];
      const rawFilename = cleanId.split(/[\\/]/).pop()?.replace('.asl', '') || 'Component';

      if (rawFilename.toLowerCase() === 'main') {
        return {
          code: `import './index.css';
import { mountApp } from './App.asl';

mountApp();
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
          code: `import { renderCosmicBackground } from './components/CosmicLandscapeBackground.asl';
import { renderNavbar } from './components/Navbar.asl';
import { renderHomeView } from './views/HomeView.asl';
import { renderDocsView } from './views/DocsView.asl';
import { renderBlogView } from './views/BlogView.asl';
import { renderRoadmapView } from './views/RoadmapView.asl';
import { renderMascotLabView } from './views/MascotLabView.asl';
import { renderFooter } from './components/Footer.asl';

function initLeftStream() {
  var items = [
    { bx: 130, br: 35, svg: "<rect x='-8' y='-30' width='16' height='60' fill='#3b0764' fill-opacity='0.25' stroke-width='1.2' /><line x1='-8' y1='-20' x2='0' y2='-20' stroke-width='0.8' /><line x1='-8' y1='-10' x2='-3' y2='-10' stroke-width='0.6' /><line x1='-8' y1='0' x2='0' y2='0' stroke-width='0.8' /><line x1='-8' y1='10' x2='-3' y2='10' stroke-width='0.6' /><line x1='-8' y1='20' x2='0' y2='20' stroke-width='0.8' /><path d='M 8,-30 L 26,-30 L 26,-18 L 12,-12 L 8,-12' fill='#581c87' fill-opacity='0.3' stroke-width='1.2' /><path d='M 8,18 L 14,18 L 28,32 L 28,40 L 8,40' fill='#581c87' fill-opacity='0.3' stroke-width='1.2' /><rect x='16' y='-28' width='10' height='46' stroke='#fbbf24' stroke-width='1.0' stroke-dasharray='2 2' fill='#fbbf24' fill-opacity='0.1' /><g font-family='monospace' font-size='6' fill='#c084fc' opacity='0.85'><text x='-6' y='36'>PS-01 · Ø16</text></g>" },
    { bx: 40, br: -15, svg: "<circle cx='0' cy='0' r='24' fill='#3b0764' fill-opacity='0.25' stroke-width='1.3' /><circle cx='0' cy='0' r='20' stroke-dasharray='2 2' stroke-width='0.7' opacity='0.6' /><line x1='0' y1='-20' x2='0' y2='-15' stroke-width='1.0' /><line x1='20' y1='0' x2='15' y2='0' stroke-width='1.0' /><line x1='0' y1='20' x2='0' y2='15' stroke-width='1.0' /><line x1='-20' y1='0' x2='-15' y2='0' stroke-width='1.0' /><line x1='0' y1='0' x2='12' y2='-13' stroke='#f43f5e' stroke-width='1.4' stroke-linecap='round' /><circle cx='0' cy='0' r='2.5' fill='#f43f5e' /><rect x='-2.5' y='24' width='5' height='16' fill='#3b0764' fill-opacity='0.3' stroke-width='1.0' /><circle cx='0' cy='42' r='2' fill='#c084fc' /><g font-family='monospace' font-size='6' fill='#c084fc' opacity='0.8'><text x='-16' y='12'>V-12 · 0.01</text></g>" },
    { bx: 120, br: 15, svg: "<rect x='-50' y='-10' width='100' height='20' rx='2' fill='#3b0764' fill-opacity='0.2' /><line x1='-30' y1='-10' x2='-30' y2='10' /><line x1='-10' y1='-10' x2='-10' y2='10' /><line x1='10' y1='-10' x2='10' y2='10' /><line x1='30' y1='-10' x2='30' y2='10' /><path d='M 0,-16 L 0,-10 M -3,-13 L 0,-10 L 3,-13' stroke-width='1.4' /><g font-family='monospace' font-size='7' fill='currentColor' opacity='0.8'><text x='-44' y='4'>1</text><text x='-24' y='4'>0</text><text x='-4' y='4' fill='#4ade80'>1</text><text x='16' y='4'>1</text><text x='36' y='4'>0</text></g>" },
    { bx: 45, br: -30, svg: "<line x1='-35' y1='0' x2='40' y2='0' stroke='#818cf8' stroke-width='0.7' stroke-dasharray='4 2' opacity='0.6' /><path d='M 0,-24 C 12,-14 12,14 0,24 C -12,14 -12,-14 0,-24 Z' fill='#3b0764' fill-opacity='0.25' stroke-width='1.3' /><path d='M -30,-15 L 0,-15 L 26,0' stroke='#c084fc' stroke-width='1.0' fill='none' /><path d='M -30,15 L 0,15 L 26,0' stroke='#c084fc' stroke-width='1.0' fill='none' /><circle cx='26' cy='0' r='2' fill='#fbbf24' /><g font-family='monospace' font-size='6' fill='#c084fc' opacity='0.75'><text x='12' y='-6'>F=26mm</text></g>" },
    { bx: 135, br: 25, svg: "<polygon points='0,0 55,0 60,5 60,65 0,65' fill='#3b0764' fill-opacity='0.25' stroke-width='1.2' /><rect x='11' y='0' width='28' height='24' rx='2' fill='#581c87' fill-opacity='0.35' /><circle cx='28' cy='42' r='10' stroke-dasharray='2 2' opacity='0.5' /><circle cx='28' cy='42' r='3' fill='currentColor' opacity='0.5' /><g font-family='monospace' font-size='6.5' fill='currentColor' opacity='0.85'><text x='8' y='58'>ROM-144 · CAD</text></g>" },
    { bx: 50, br: -12, svg: "<line x1='-28' y1='16' x2='32' y2='16' stroke-width='1.0' /><line x1='-28' y1='16' x2='-28' y2='-18' stroke-width='1.0' /><line x1='-28' y1='4' x2='28' y2='4' stroke-width='0.5' stroke-dasharray='2 2' opacity='0.3' /><path d='M -28,-12 C -10,-10 0,6 28,12' stroke='#c084fc' stroke-width='1.6' fill='none' /><path d='M -28,-12 C -10,-10 0,6 28,12 L 28,16 L -28,16 Z' fill='#7e22ce' fill-opacity='0.2' /><circle cx='28' cy='12' r='2.5' fill='#4ade80' /><g font-family='monospace' font-size='6.5' fill='currentColor' opacity='0.85'><text x='-24' y='-10' fill='#4ade80'>-80% TOK</text></g>" },
    { bx: 125, br: -20, svg: "<rect x='-35' y='-20' width='70' height='40' rx='2' fill='#181327' fill-opacity='0.6' stroke-width='1.1' /><line x1='-15' y1='-20' x2='-15' y2='20' stroke='#818cf8' stroke-width='0.5' stroke-dasharray='2 2' opacity='0.3' /><line x1='10' y1='-20' x2='10' y2='20' stroke='#818cf8' stroke-width='0.5' stroke-dasharray='2 2' opacity='0.3' /><path d='M -30,-12 L -20,-12 L -20,-16 L -10,-16 L -10,-12 L 0,-12 L 0,-16 L 10,-16 L 10,-12 L 20,-12 L 20,-16 L 30,-16' stroke='#a855f7' stroke-width='1.1' fill='none' /><path d='M -30,2 L -12,2 L -6,-4 L 14,-4 L 20,2 L 30,2' stroke='#c084fc' stroke-width='1.1' fill='none' /><path d='M -30,-4 L -12,-4 L -6,2 L 14,2 L 20,-4 L 30,-4' stroke='#c084fc' stroke-width='1.1' fill='none' /><g font-family='monospace' font-size='5.5' fill='#c084fc' opacity='0.75'><text x='-28' y='14'>CLK/BUS · 100MHz</text></g>" },
    { bx: 40, br: 45, svg: "<polygon points='0,-22 19,-11 19,11 0,22 -19,11 -19,-11' fill='#3b0764' fill-opacity='0.3' stroke-width='1.3' /><circle cx='0' cy='0' r='8' stroke-dasharray='2 2' stroke-width='0.8' /><line x1='-19' y1='0' x2='-26' y2='0' stroke-width='1.2' /><line x1='19' y1='0' x2='26' y2='0' stroke-width='1.2' /><line x1='-10' y1='-17' x2='-14' y2='-23' stroke-width='1.2' /><line x1='10' y1='17' x2='14' y2='23' stroke-width='1.2' /><g font-family='monospace' font-size='6.5' fill='currentColor' opacity='0.8'><text x='-10' y='3'>WASM</text></g>" },
    { bx: 125, br: -25, svg: "<path d='M -14,0 A 14 14 0 0 1 14,0 Z' fill='#3b0764' fill-opacity='0.3' stroke-width='1.5' /><line x1='-8' y1='0' x2='-8' y2='24' /><line x1='0' y1='0' x2='0' y2='28' /><line x1='8' y1='0' x2='8' y2='24' /><circle cx='0' cy='-4' r='18' stroke-dasharray='3 2' stroke-width='0.6' opacity='0.4' /><g font-family='monospace' font-size='6.5' fill='currentColor' opacity='0.7'><text x='18' y='12'>2N3904</text></g>" },
    { bx: 50, br: -22, svg: "<circle cx='0' cy='0' r='24' stroke-dasharray='3 2' stroke-width='0.7' opacity='0.5' /><circle cx='0' cy='0' r='20' fill='#3b0764' fill-opacity='0.25' stroke-width='1.1' /><circle cx='0' cy='0' r='8' fill='#581c87' fill-opacity='0.4' stroke-width='1.0' /><circle cx='0' cy='-14' r='5' fill='#581c87' fill-opacity='0.35' stroke-width='0.9' /><circle cx='12' cy='7' r='5' fill='#581c87' fill-opacity='0.35' stroke-width='0.9' /><circle cx='-12' cy='7' r='5' fill='#581c87' fill-opacity='0.35' stroke-width='0.9' /><g font-family='monospace' font-size='5.5' fill='#c084fc' opacity='0.75'><text x='-14' y='18'>MOD 0.5</text></g>" }
  ];
  var container = document.getElementById('left-stream-items');
  var svg = document.getElementById('left-deflecting-svg');
  if (!container || !svg) return;

  var ticking = false;
  function update() {
    ticking = false;
    var scrollY = window.scrollY || window.pageYOffset || 0;
    var vh = window.innerHeight || 900;
    var docH = document.documentElement.scrollHeight || 12000;
    svg.setAttribute('viewBox', '0 0 180 ' + vh);

    var STEP = 280;
    var START_Y = 520;
    var maxK = Math.max(0, Math.floor((docH - START_Y - 200) / STEP));
    var minK = Math.max(0, Math.floor((scrollY - 100 - START_Y) / STEP));
    var endK = Math.min(maxK, Math.ceil((scrollY + vh + 100 - START_Y) / STEP));

    var html = '';
    for (var k = minK; k <= endK; k++) {
      var docY = START_Y + k * STEP;
      var viewY = docY - scrollY;
      if (viewY < -100 || viewY > vh + 100) continue;

      var item = items[k % items.length];
      var xOff = 0;
      var extraRot = 0;
      var opacity = 0.85;

      if (viewY <= 560) {
        var t = Math.max(0, Math.min(1, (560 - viewY) / 420));
        var ease = t * t * (3 - 2 * t);
        xOff = -ease * 260;
        extraRot = -ease * 42;
        opacity = Math.max(0, 0.85 * (1 - Math.pow(t, 1.3)));
      }

      var x = item.bx + xOff;
      var rot = item.br + extraRot;
      html += '<g transform="translate(' + x.toFixed(1) + ', ' + viewY.toFixed(1) + ') rotate(' + rot.toFixed(1) + ')" stroke="url(#leftBioGrad)" stroke-width="1.2" opacity="' + opacity.toFixed(3) + '" style="transition:transform 0.08s ease-out,opacity 0.08s ease-out">' + item.svg + '</g>';
    }
    container.innerHTML = html;
  }

  window.addEventListener('scroll', function() {
    if (!ticking) {
      window.requestAnimationFrame(update);
      ticking = true;
    }
  }, { passive: true });
  window.addEventListener('resize', update);
  update();
}

// --- Chameleon Tail Morphing Engine (Phase 3) ---
var SP_BASE_D = "M 288.20 40.00 L 287.11 39.31 L 285.56 38.34 L 284.00 37.40 L 282.57 36.61 L 281.14 35.85 L 279.70 35.10 L 278.27 34.35 L 276.84 33.61 L 275.40 32.90 L 273.94 32.24 L 272.47 31.61 L 271.00 31.00 L 269.54 30.38 L 268.07 29.77 L 266.60 29.20 L 265.11 28.67 L 263.60 28.18 L 262.10 27.70 L 260.60 27.21 L 259.11 26.74 L 257.60 26.30 L 256.07 25.91 L 254.54 25.55 L 253.00 25.20 L 251.46 24.85 L 249.93 24.51 L 248.40 24.20 L 246.90 23.91 L 245.41 23.64 L 243.90 23.40 L 242.34 23.21 L 240.77 23.06 L 239.20 22.90 L 237.66 22.72 L 236.13 22.54 L 234.60 22.40 L 233.07 22.30 L 231.54 22.24 L 230.00 22.20 L 228.44 22.18 L 226.86 22.19 L 225.30 22.20 L 223.76 22.22 L 222.23 22.25 L 220.70 22.30 L 219.17 22.38 L 217.63 22.49 L 216.10 22.60 L 214.57 22.71 L 213.03 22.84 L 211.50 23.00 L 209.97 23.21 L 208.43 23.45 L 206.90 23.70 L 205.36 23.96 L 203.83 24.22 L 202.30 24.50 L 200.79 24.79 L 199.30 25.08 L 197.80 25.40 L 196.30 25.74 L 194.80 26.11 L 193.30 26.50 L 191.80 26.91 L 190.29 27.35 L 188.80 27.80 L 187.33 28.25 L 185.86 28.71 L 184.40 29.20 L 182.93 29.71 L 181.46 30.25 L 180.00 30.80 L 178.56 31.36 L 177.13 31.92 L 175.70 32.50 L 174.26 33.09 L 172.83 33.68 L 171.40 34.30 L 169.99 34.95 L 168.59 35.62 L 167.20 36.30 L 165.82 36.99 L 164.46 37.68 L 163.10 38.40 L 161.76 39.15 L 160.43 39.92 L 159.10 40.70 L 157.76 41.49 L 156.43 42.29 L 155.10 43.10 L 153.79 43.92 L 152.49 44.75 L 151.20 45.60 L 149.92 46.49 L 148.66 47.39 L 147.40 48.30 L 146.16 49.19 L 144.92 50.09 L 143.70 51.00 L 142.49 51.95 L 141.29 52.92 L 140.10 53.90 L 138.92 54.89 L 137.75 55.88 L 136.60 56.90 L 135.49 57.95 L 134.39 59.03 L 133.30 60.10 L 132.19 61.16 L 131.09 62.22 L 130.00 63.30 L 128.95 64.42 L 127.92 65.56 L 126.90 66.70 L 125.89 67.83 L 124.89 68.95 L 123.90 70.10 L 122.92 71.29 L 121.96 72.49 L 121.00 73.70 L 120.05 74.89 L 119.11 76.09 L 118.20 77.30 L 117.31 78.55 L 116.44 79.82 L 115.60 81.10 L 114.78 82.39 L 113.99 83.70 L 113.20 85.00 L 112.42 86.30 L 111.66 87.59 L 110.90 88.90 L 110.15 90.22 L 109.41 91.55 L 108.70 92.90 L 108.01 94.29 L 107.34 95.70 L 106.70 97.10 L 106.08 98.47 L 105.49 99.82 L 104.90 101.20 L 104.32 102.62 L 103.75 104.06 L 103.20 105.50 L 102.68 106.93 L 102.19 108.36 L 101.70 109.80 L 101.22 111.26 L 100.76 112.72 L 100.30 114.20 L 99.85 115.69 L 99.41 117.20 L 99.00 118.70 L 98.61 120.20 L 98.25 121.70 L 97.90 123.20 L 97.55 124.70 L 97.21 126.19 L 96.90 127.70 L 96.61 129.22 L 96.35 130.76 L 96.10 132.30 L 95.85 133.86 L 95.61 135.44 L 95.40 137.00 L 95.21 138.54 L 95.05 140.06 L 94.90 141.60 L 94.75 143.16 L 94.61 144.73 L 94.50 146.30 L 94.42 147.87 L 94.36 149.43 L 94.30 151.00 L 94.22 152.57 L 94.14 154.13 L 94.10 155.70 L 94.11 157.26 L 94.16 158.83 L 94.20 160.40 L 94.23 162.00 L 94.25 163.60 L 94.30 165.20 L 94.38 166.77 L 94.49 168.34 L 94.60 169.90 L 94.72 171.47 L 94.85 173.03 L 95.00 174.60 L 95.18 176.17 L 95.39 177.73 L 95.60 179.30 L 95.82 180.87 L 96.06 182.44 L 96.30 184.00 L 96.56 185.54 L 96.82 187.06 L 97.10 188.60 L 97.39 190.16 L 97.68 191.74 L 98.00 193.30 L 98.35 194.84 L 98.72 196.38 L 99.10 197.90 L 99.49 199.40 L 99.89 200.90 L 100.30 202.40 L 100.72 203.93 L 101.15 205.48 L 101.60 207.00 L 102.09 208.48 L 102.59 209.94 L 103.10 211.40 L 103.59 212.87 L 104.09 214.33 L 104.60 215.80 L 105.15 217.27 L 105.72 218.74 L 106.30 220.20";
var BL_BASE_D = "M 150.00 159.50 L 149.55 160.12 L 148.91 161.00 L 148.30 161.90 L 147.78 162.72 L 147.29 163.56 L 146.80 164.40 L 146.32 165.25 L 145.85 166.11 L 145.40 167.00 L 144.98 167.91 L 144.59 168.85 L 144.20 169.80 L 143.82 170.76 L 143.45 171.72 L 143.10 172.70 L 142.78 173.69 L 142.49 174.69 L 142.20 175.70 L 141.92 176.73 L 141.65 177.76 L 141.40 178.80 L 141.18 179.83 L 140.98 180.86 L 140.80 181.90 L 140.65 182.96 L 140.52 184.02 L 140.40 185.10 L 140.29 186.19 L 140.18 187.30 L 140.10 188.40 L 140.05 189.50 L 140.02 190.59 L 140.00 191.70 L 139.99 192.83 L 139.99 193.97 L 140.00 195.10 L 140.02 196.20 L 140.05 197.30 L 140.10 198.40 L 140.18 199.53 L 140.28 200.66 L 140.40 201.80 L 140.55 202.93 L 140.73 204.07 L 140.90 205.20 L 141.06 206.34 L 141.21 207.47 L 141.40 208.60 L 141.64 209.70 L 141.92 210.80 L 142.20 211.90 L 142.46 213.03 L 142.71 214.18 L 143.00 215.30 L 143.34 216.38 L 143.72 217.43 L 144.10 218.50 L 144.46 219.60 L 144.82 220.70";

var U03_SP = [106.3, 220.2, 104.3, 223.3, 102.3, 226.4, 100.3, 229.5, 98.2, 232.5, 96.0, 235.5, 93.6, 238.3, 91.0, 240.9, 88.2, 243.3, 85.3, 245.6, 82.2, 247.6, 79.0, 249.5, 75.7, 251.0, 72.1, 252.0, 68.4, 252.4, 64.8, 252.4, 61.1, 252.0, 57.5, 251.3, 54.0, 250.0, 50.7, 248.4, 47.7, 246.3, 44.9, 243.8, 42.4, 241.1, 40.2, 238.2, 38.2, 235.1, 36.5, 231.8, 35.2, 228.4, 34.1, 224.9, 33.3, 221.3, 32.6, 217.6, 32.2, 214.0, 31.8, 210.3, 31.6, 206.6, 31.6, 202.9, 31.7, 199.2, 32.0, 195.6, 32.5, 191.9, 33.1, 188.3, 33.9, 184.7, 35.0, 181.2, 36.3, 177.7, 37.8, 174.3, 39.6, 171.1, 41.8, 168.2, 44.6, 165.8, 47.7, 163.8, 51.1, 162.3, 54.6, 161.1, 58.1, 160.2, 61.8, 159.8, 65.5, 160.2, 68.8, 161.7, 71.6, 164.0, 74.0, 166.8, 76.0, 169.9, 77.5, 173.3, 78.1, 176.9, 77.9, 180.6, 77.1, 184.1, 75.9, 187.6, 74.4, 191.0, 72.5, 194.2, 70.1, 196.9, 66.8, 198.7, 63.3, 199.8, 59.7, 200.2, 56.2, 199.1, 53.8, 196.3, 51.9, 193.2, 50.0, 190.0];
var R_SP   = [106.3, 220.2, 104.6, 223.1, 102.9, 226.1, 101.2, 229.0, 99.5, 231.9, 97.7, 234.9, 96.1, 237.8, 94.4, 240.8, 92.7, 243.7, 91.0, 246.7, 89.3, 249.6, 87.6, 252.6, 85.9, 255.5, 84.2, 258.5, 82.7, 261.5, 81.3, 264.6, 80.1, 267.7, 79.1, 271.0, 78.4, 274.3, 77.7, 277.7, 77.4, 281.0, 77.3, 284.4, 77.6, 287.8, 78.3, 291.1, 79.6, 294.2, 81.3, 297.2, 83.4, 299.9, 85.9, 302.2, 88.6, 304.2, 91.6, 305.8, 94.8, 307.0, 98.0, 308.0, 101.3, 308.7, 104.7, 309.3, 108.1, 309.7, 111.5, 309.9, 114.8, 310.0, 118.2, 309.9, 121.6, 309.7, 125.0, 309.4, 128.4, 309.0, 131.7, 308.4, 135.1, 307.8, 138.4, 307.0, 141.6, 306.1, 144.9, 305.0, 148.0, 303.8, 151.1, 302.4, 154.2, 300.9, 157.1, 299.2, 160.0, 297.4, 162.9, 295.6, 165.6, 293.6, 168.3, 291.5, 170.8, 289.2, 173.3, 286.9, 175.5, 284.3, 177.7, 281.7, 179.6, 278.9, 181.5, 276.1, 183.2, 273.1, 184.9, 270.2, 186.4, 267.2, 187.8, 264.1, 189.1, 260.9, 190.4, 257.8, 191.5, 254.6, 192.7, 251.4, 193.8, 248.2, 195.0, 245.0];
var A01_SP = [106.9, 221.6, 109.1, 226.7, 111.6, 231.6, 114.2, 236.5, 117.0, 241.2, 120.1, 245.8, 123.3, 250.3, 126.9, 254.5, 130.6, 258.6, 134.6, 262.3, 138.7, 265.9, 143.1, 269.3, 147.7, 272.3, 152.5, 275.1, 157.4, 277.6, 162.3, 280.1, 167.2, 282.6, 172.3, 284.7, 177.5, 286.5, 182.9, 287.5, 188.4, 287.7, 193.9, 287.2, 199.3, 285.8, 204.4, 283.8, 209.2, 281.1, 213.9, 278.2, 218.4, 275.1, 222.7, 271.6, 226.6, 267.7, 230.1, 263.4, 233.2, 258.9, 235.9, 254.1, 238.2, 249.1, 240.2, 243.9, 241.6, 238.6, 242.5, 233.2, 243.0, 227.7, 242.9, 222.2, 242.3, 216.7, 241.1, 211.3, 239.2, 206.2, 236.5, 201.4, 233.1, 197.0, 229.2, 193.2, 224.6, 190.1, 219.8, 187.4, 214.7, 185.5, 209.3, 184.1, 203.8, 183.5, 198.3, 183.7, 193.0, 184.8, 188.1, 187.4, 183.8, 190.9, 180.4, 195.1, 177.8, 200.0, 176.2, 205.2, 175.7, 210.7, 176.5, 216.2, 178.6, 221.3, 181.8, 225.7, 186.1, 229.1, 191.3, 231.1, 196.7, 231.4, 202.0, 229.9, 206.3, 226.6, 208.9, 221.8, 209.1, 216.3, 206.5, 211.5, 201.7, 209.1, 196.5, 210.6];

var U03_BL = [144.8, 220.7, 140.5, 225.7, 136.3, 230.7, 131.8, 235.6, 127.1, 240.2, 122.0, 244.3, 116.7, 248.2, 111.1, 251.8, 105.4, 254.9, 99.3, 257.5, 93.0, 259.4, 86.5, 260.7, 80.0, 261.4, 73.4, 261.2, 67.1, 259.6, 61.3, 256.4, 56.3, 252.1, 52.1, 247.0, 48.7, 241.4, 46.4, 235.3, 45.3, 228.8, 44.7, 222.2, 44.7, 215.6, 44.9, 209.1, 45.8, 202.5, 47.4, 196.1, 49.7, 190.0, 52.6, 184.1, 56.8, 179.1, 62.0, 175.0];
var R_BL   = [144.8, 220.7, 141.9, 224.3, 138.9, 227.8, 135.9, 231.3, 133.0, 234.9, 130.0, 238.5, 127.2, 242.1, 124.4, 245.8, 121.7, 249.6, 119.0, 253.4, 116.4, 257.2, 113.9, 261.1, 111.5, 265.1, 109.4, 269.2, 107.5, 273.4, 105.8, 277.7, 104.9, 282.2, 105.5, 286.8, 108.0, 290.6, 111.7, 293.5, 115.9, 295.3, 120.5, 296.1, 125.1, 296.2, 129.7, 295.9, 134.3, 295.2, 138.7, 293.7, 142.9, 291.8, 147.0, 289.6, 151.0, 287.3, 155.0, 285.0];
var A01_BL = [145.2, 221.8, 147.6, 227.5, 150.5, 232.9, 153.8, 238.1, 157.6, 243.0, 161.9, 247.4, 166.7, 251.2, 172.0, 254.4, 177.6, 256.9, 183.2, 259.5, 189.2, 261.1, 195.3, 260.7, 201.0, 258.5, 206.3, 255.3, 211.4, 251.8, 215.7, 247.4, 219.3, 242.4, 221.9, 236.9, 223.6, 230.9, 224.5, 224.8, 224.2, 218.7, 222.8, 212.7, 219.7, 207.4, 215.0, 203.4, 209.3, 201.1, 203.2, 201.0, 197.3, 202.7, 192.4, 206.3, 189.4, 211.6, 188.4, 217.7];

function interpolateFlatPoints(p0, p1, t) {
  var len = p0.length;
  var d = '';
  for (var i = 0; i < len; i += 2) {
    var x = p0[i] + t * (p1[i] - p0[i]);
    var y = p0[i + 1] + t * (p1[i + 1] - p0[i + 1]);
    d += ' L ' + x.toFixed(1) + ' ' + y.toFixed(1);
  }
  return d;
}

function getMorphedTailPaths(p) {
  var t = Math.min(1, Math.max(0, p));
  var tSplit = 0.35;
  var tailSpD = '';
  var tailBlD = '';

  if (t <= tSplit) {
    var subT = t / tSplit;
    var ease = subT * subT * (3 - 2 * subT);
    tailSpD = interpolateFlatPoints(U03_SP, R_SP, ease);
    tailBlD = interpolateFlatPoints(U03_BL, R_BL, ease);
  } else {
    var subT = (t - tSplit) / (1 - tSplit);
    var ease = subT * subT * (3 - 2 * subT);
    tailSpD = interpolateFlatPoints(R_SP, A01_SP, ease);
    tailBlD = interpolateFlatPoints(R_BL, A01_BL, ease);
  }

  return {
    spine: SP_BASE_D + tailSpD,
    belly: BL_BASE_D + tailBlD
  };
}

function initMascotScroll() {
  var mascot = document.getElementById('hero-chameleon-svg');
  if (!mascot) return;
  var ticking = false;

  var spineEl = document.getElementById('chameleon-tail-spine');
  var bellyEl = document.getElementById('chameleon-tail-belly');
  var vineEl = document.getElementById('hero-cyber-liana');
  var bodyEl = document.getElementById('hero-chameleon-body');

  function updateMascot() {
    ticking = false;
    var scrollY = window.scrollY || window.pageYOffset || 0;
    var p = Math.min(1, Math.max(0, scrollY / 300));

    // 1. Dynamic 2-Stage Biological Tail Morphing (Unhook -> Curl)
    if (spineEl && bellyEl) {
      var morphed = getMorphedTailPaths(p);
      spineEl.setAttribute('d', morphed.spine);
      bellyEl.setAttribute('d', morphed.belly);
    }

    // 2. Cyber-Liana dynamic reaction (gentle release sway and fade)
    if (vineEl) {
      var vFade = Math.max(0, 1 - p * 1.8);
      var vSway = (1 - p) * -2 + (p > 0.05 && p < 0.65 ? Math.sin(p * Math.PI) * 3.5 : 0);
      vineEl.style.opacity = vFade.toFixed(3);
      vineEl.style.transform = 'translate(10px, 32px) scale(0.48) translate(-34px, -4px) rotate(' + vSway.toFixed(1) + 'deg)';
    }

    // 3. Chameleon Body sliding descent along vine
    if (bodyEl) {
      var dropY = p * 42;
      var driftX = p * -6;
      var rot = (1 - p) * -4 + p * 6;
      bodyEl.style.transform = 'translate(' + (10 + driftX).toFixed(1) + 'px, ' + (32 + dropY).toFixed(1) + 'px) scale(0.48) translate(-34px, -4px) rotate(' + rot.toFixed(1) + 'deg)';
    }

    // 4. Container perspective floating
    var offsetX = (1 - p) * 16;
    var offsetY = (1 - p) * -24;
    var scale = 1 + (1 - p) * 0.05;
    mascot.style.transform = 'translate3d(' + offsetX.toFixed(1) + 'px, ' + offsetY.toFixed(1) + 'px, 0) scale(' + scale.toFixed(3) + ')';
  }

  window.addEventListener('scroll', function() {
    if (!ticking) {
      window.requestAnimationFrame(updateMascot);
      ticking = true;
    }
  }, { passive: true });
  updateMascot();
}

function getRouteContent(route) {
  var path = (route || window.location.pathname || '/').toLowerCase();
  if (path.startsWith('/docs')) {
    return typeof renderDocsView === 'function' ? renderDocsView() : '';
  }
  if (path.startsWith('/blog')) {
    return typeof renderBlogView === 'function' ? renderBlogView() : '';
  }
  if (path.startsWith('/roadmap')) {
    return typeof renderRoadmapView === 'function' ? renderRoadmapView() : '';
  }
  if (path.startsWith('/lab') || path.startsWith('/variants') || path.startsWith('/mascot')) {
    return typeof renderMascotLabView === 'function' ? renderMascotLabView() : '';
  }
  return typeof renderHomeView === 'function' ? renderHomeView() : '';
}

export function renderApp(route = '/') {
  return '<div class="min-h-screen bg-ground text-ink flex flex-col relative w-full max-w-[100vw] overflow-x-hidden">' +
    (typeof renderCosmicBackground === 'function' ? renderCosmicBackground() : '') +
    (typeof renderNavbar === 'function' ? renderNavbar() : '') +
    '<div class="asl-app-root relative z-10 flex-1 flex flex-col pt-16">' + getRouteContent(route) + '</div>' +
    (typeof renderFooter === 'function' ? renderFooter() : '') +
    '</div>';
}

export function mountApp(route) {
  var root = document.getElementById('root');
  if (!root) return;

  function navigate(path) {
    root.innerHTML = renderApp(path);
    setTimeout(function() {
      initLeftStream();
      initMascotScroll();
    }, 50);
  }

  document.addEventListener('click', function(e) {
    var a = e.target.closest('a');
    if (!a) return;
    var href = a.getAttribute('href');
    if (!href || href.startsWith('http') || href.startsWith('//') || href.startsWith('#') || href.startsWith('mailto:') || a.target === '_blank') {
      return;
    }
    e.preventDefault();
    if (window.location.pathname !== href) {
      window.history.pushState({}, '', href);
      navigate(href);
      window.scrollTo(0, 0);
    }
  });

  window.addEventListener('popstate', function() {
    navigate(window.location.pathname);
  });

  navigate(route || window.location.pathname);
}

export { mountApp as default, mountApp as App };
`,
          map: null
        };
      }

      // Handle Navbar.asl specifically
      if (rawFilename === 'Navbar') {
        return {
          code: `export function checkKonamiSequence(keys = []) {
  const len = keys.length;
  if (len >= 10) {
    const k = keys.slice(len - 10);
    if (k[0] === 'ArrowUp' && k[1] === 'ArrowUp' && k[2] === 'ArrowDown' && k[3] === 'ArrowDown' &&
        k[4] === 'ArrowLeft' && k[5] === 'ArrowRight' && k[6] === 'ArrowLeft' && k[7] === 'ArrowRight' &&
        k[8] === 'b' && k[9] === 'a') {
      return { unlocked: true, theme: 'crt-amber' };
    }
  }
  return { unlocked: false, theme: 'none' };
}

export function renderNavbar() {
  return '<div class="fixed top-2 sm:top-3 left-0 right-0 z-50 flex justify-center px-2 sm:px-4 pointer-events-none w-full max-w-[100vw]">' +
    '<div class="relative pointer-events-auto max-w-shell w-full">' +
      '<header class="relative z-10 w-full rounded-full border border-line/80 bg-surface/90 backdrop-blur-2xl px-3 sm:px-4 h-12 sm:h-14 flex items-center justify-between shadow-sm transition-colors">' +
        '<div class="flex items-center gap-2 sm:gap-3 shrink-0">' +
          '<a href="/" class="rounded-full shrink-0 flex items-center gap-2 group" title="aslang.dev home">' +
            '<div class="asl-navbar-logo inline-flex items-center gap-2.5" aria-label="aslang.dev">' +
              '<span class="w-7 h-7 sm:w-8 sm:h-8 inline-flex items-center justify-center shrink-0 hover:scale-110 transition-transform duration-200">' +
                '<svg viewBox="0 0 160 160" fill="none" xmlns="http://www.w3.org/2000/svg" class="asl-canonical-logo w-full h-full" role="img" aria-label="ASL Chameleon Mascot Canonical Logo">' +
                  '<defs><filter id="asl-nav-glow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur in="SourceGraphic" stdDeviation="2.2" result="blur1"/><feGaussianBlur in="SourceGraphic" stdDeviation="0.6" result="blur2"/><feMerge><feMergeNode in="blur1"/><feMergeNode in="blur2"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>' +
                  '<g transform="translate(-122.2, -170.3) scale(1.062)" stroke="#C084FC" stroke-width="2.64" stroke-linecap="round" stroke-linejoin="round" fill="none" filter="url(#asl-nav-glow)">' +
                    '<path d="M 137.60 265.00 L 138.53 265.76 L 139.85 266.84 L 141.20 267.90 L 142.44 268.82 L 143.71 269.72 L 145.00 270.60 L 146.31 271.45 L 147.65 272.28 L 149.00 273.10 L 150.36 273.92 L 151.72 274.73 L 153.10 275.50 L 154.51 276.23 L 155.94 276.93 L 157.30 277.60 L 158.55 278.26 L 159.74 278.89 L 160.95 279.50 L 162.19 280.07 L 163.44 280.62 L 164.70 281.20 L 165.94 281.85 L 167.18 282.53 L 168.45 283.17 L 169.76 283.74 L 171.09 284.29 L 172.42 284.80 L 173.71 285.29 L 174.99 285.76 L 176.29 286.17 L 177.61 286.52 L 178.95 286.80 L 180.28 287.06 L 181.62 287.29 L 182.95 287.50 L 184.29 287.64 L 185.63 287.71 L 186.97 287.72 L 188.32 287.70 L 189.67 287.66 L 191.02 287.58 L 192.37 287.44 L 193.70 287.23 L 195.02 286.97 L 196.35 286.66 L 197.68 286.31 L 199.02 285.92 L 200.35 285.47 L 201.67 284.96 L 202.98 284.40 L 204.29 283.80 L 205.59 283.16 L 206.88 282.48 L 208.15 281.77 L 209.40 281.00 L 210.62 280.20 L 211.85 279.40 L 213.11 278.64 L 214.36 277.88 L 215.59 277.10 L 216.78 276.29 L 217.93 275.46 L 219.07 274.60 L 220.19 273.70 L 221.29 272.77 L 222.38 271.80 L 223.49 270.80 L 224.58 269.76 L 225.64 268.70 L 226.64 267.63 L 227.59 266.54 L 228.54 265.40 L 229.51 264.20 L 230.47 262.96 L 231.39 261.70 L 232.25 260.45 L 233.08 259.19 L 233.88 257.90 L 234.65 256.56 L 235.40 255.19 L 236.11 253.80 L 236.80 252.39 L 237.46 250.96 L 238.09 249.50 L 238.70 248.02 L 239.28 246.51 L 239.82 245.00 L 240.33 243.48 L 240.79 241.95 L 241.20 240.40 L 241.55 238.82 L 241.85 237.21 L 242.12 235.60 L 242.38 233.97 L 242.61 232.33 L 242.79 230.70 L 242.91 229.09 L 242.98 227.50 L 243.01 225.90 L 243.01 224.30 L 242.97 222.69 L 242.88 221.10 L 242.73 219.52 L 242.53 217.96 L 242.29 216.40 L 241.99 214.85 L 241.64 213.31 L 241.24 211.80 L 240.79 210.31 L 240.29 208.84 L 239.74 207.40 L 239.14 206.00 L 238.50 204.63 L 237.78 203.30 L 237.00 202.03 L 236.16 200.80 L 235.27 199.60 L 234.32 198.40 L 233.33 197.23 L 232.29 196.10 L 231.22 195.02 L 230.11 193.98 L 228.95 193.00 L 227.73 192.09 L 226.45 191.23 L 225.15 190.40 L 223.85 189.60 L 222.53 188.83 L 221.19 188.10 L 219.80 187.41 L 218.38 186.77 L 216.95 186.20 L 215.52 185.71 L 214.09 185.29 L 212.65 184.90 L 211.19 184.52 L 209.72 184.18 L 208.27 183.90 L 206.84 183.71 L 205.43 183.58 L 204.02 183.50 L 202.60 183.45 L 201.18 183.44 L 199.79 183.50 L 198.43 183.64 L 197.09 183.84 L 195.78 184.10 L 194.55 184.36 L 193.35 184.67 L 191.99 185.20 L 190.24 186.12 L 188.33 187.26 L 186.81 188.22 L 185.98 188.81 L 185.55 189.21 L 185.13 189.63 L 184.60 190.13 L 184.08 190.63 L 183.58 191.14 L 183.10 191.66 L 182.63 192.18 L 182.17 192.72 L 181.73 193.26 L 181.31 193.81 L 180.90 194.36 L 180.51 194.93 L 180.13 195.49 L 179.77 196.07 L 179.42 196.64 L 179.09 197.22 L 178.78 197.81 L 178.48 198.40 L 178.20 198.99 L 177.93 199.59 L 177.68 200.18 L 177.44 200.79 L 177.22 201.39 L 177.02 201.99 L 176.83 202.59 L 176.65 203.20 L 176.49 203.80 L 176.35 204.41 L 176.22 205.01 L 176.11 205.62 L 176.01 206.22 L 175.93 206.82 L 175.86 207.42 L 175.80 208.02 L 175.76 208.61 L 175.74 209.20 L 175.72 209.79 L 175.73 210.38 L 175.74 210.96 L 175.77 211.54 L 175.81 212.11 L 175.87 212.68 L 175.94 213.24 L 176.02 213.80 L 176.11 214.35 L 176.22 214.90 L 176.34 215.44 L 176.47 215.97 L 176.61 216.50 L 176.76 217.02 L 176.93 217.54 L 177.10 218.05 L 177.29 218.55 L 177.49 219.04 L 177.69 219.53 L 177.91 220.00 L 178.14 220.47 L 178.38 220.93 L 178.62 221.39 L 178.88 221.83 L 179.14 222.27 L 179.41 222.69 L 179.69 223.11 L 179.98 223.52 L 180.28 223.91 L 180.58 224.30 L 180.89 224.68 L 181.21 225.05 L 181.54 225.41 L 181.87 225.76 L 182.21 226.10 L 182.55 226.43 L 182.90 226.75 L 183.25 227.06 L 183.61 227.36 L 183.98 227.65 L 184.34 227.93 L 184.72 228.20 L 185.09 228.45 L 185.47 228.70 L 185.86 228.94 L 186.24 229.16 L 186.63 229.38 L 187.02 229.59 L 187.42 229.78 L 187.81 229.96 L 188.21 230.14 L 188.61 230.30 L 189.01 230.46 L 189.42 230.60 L 189.82 230.73 L 190.22 230.85 L 190.63 230.96 L 191.03 231.07 L 191.43 231.16 L 191.84 231.24 L 192.24 231.31 L 192.64 231.37 L 193.04 231.42 L 193.44 231.47 L 193.84 231.50 L 194.24 231.52 L 194.63 231.53 L 195.02 231.54 L 195.41 231.53 L 195.80 231.52 L 196.18 231.50 L 196.56 231.46 L 196.94 231.42 L 197.32 231.37 L 197.69 231.32 L 198.05 231.25 L 198.42 231.18 L 198.78 231.09 L 199.13 231.00 L 199.48 230.91 L 199.83 230.80 L 200.17 230.69 L 200.51 230.57 L 200.84 230.44 L 201.17 230.30 L 201.49 230.16 L 201.81 230.01 L 202.12 229.86 L 202.42 229.70 L 202.72 229.53 L 203.02 229.36 L 203.30 229.18 L 203.59 229.00 L 203.86 228.81 L 204.13 228.61 L 204.39 228.41 L 204.65 228.21 L 204.90 228.00 L 205.15 227.78 L 205.38 227.56 L 205.61 227.34 L 205.84 227.11 L 206.06 226.88 L 206.27 226.65 L 206.47 226.41 L 206.67 226.17 L 206.86 225.93 L 207.04 225.68 L 207.22 225.43 L 207.38 225.18 L 207.55 224.92 L 207.70 224.67 L 207.85 224.41 L 207.99 224.15 L 208.13 223.88 L 208.25 223.62 L 208.37 223.35 L 208.49 223.09 L 208.59 222.82 L 208.69 222.55 L 208.78 222.28 L 208.87 222.01 L 208.95 221.75 L 209.02 221.48 L 209.08 221.21 L 209.14 220.94 L 209.19 220.67 L 209.24 220.40 L 209.28 220.13 L 209.31 219.86 L 209.33 219.60 L 209.35 219.33 L 209.37 219.07 L 209.37 218.81 L 209.37 218.55 L 209.37 218.29 L 209.35 218.03 L 209.34 217.77 L 209.31 217.52 L 209.28 217.27 L 209.25 217.02 L 209.21 216.77 L 209.16 216.53 L 209.11 216.29 L 209.05 216.05 L 208.99 215.81 L 208.92 215.58 L 208.85 215.35 L 208.77 215.12 L 208.69 214.90 L 208.60 214.68 L 208.51 214.46 L 208.41 214.25 L 208.31 214.04 L 208.21 213.83 L 208.10 213.63 L 207.99 213.43 L 207.87 213.24 L 207.75 213.05 L 207.62 212.86 L 207.49 212.68 L 207.36 212.50 L 207.23 212.33 L 207.09 212.16 L 206.95 211.99 L 206.80 211.83 L 206.66 211.67 L 206.51 211.52 L 206.35 211.37 L 206.20 211.23 L 206.04 211.09 L 205.88 210.96 L 205.72 210.83 L 205.56 210.70 L 205.39 210.58 L 205.22 210.47 L 205.05 210.36 L 204.88 210.25 L 204.71 210.15 L 204.54 210.05 L 204.36 209.96 L 204.19 209.87 L 204.01 209.79 L 203.83 209.71 L 203.66 209.64 L 203.48 209.57 L 203.30 209.50 L 203.12 209.44 L 202.94 209.39 L 202.76 209.34 L 202.58 209.29 L 202.40 209.25 L 202.22 209.21 L 202.04 209.18 L 201.86 209.15 L 201.68 209.13 L 201.50 209.11 L 201.33 209.10 L 201.15 209.08 L 200.97 209.08 L 200.80 209.08 L 200.63 209.08 L 200.45 209.08 L 200.28 209.09 L 200.11 209.11 L 199.94 209.12 L 199.78 209.14 L 199.61 209.17 L 199.45 209.20 L 199.28 209.23 L 199.12 209.27 L 198.96 209.31 L 198.81 209.35 L 198.65 209.40 L 198.50 209.45 L 198.35 209.50 L 198.20 209.56 L 198.06 209.62 L 197.91 209.68 L 197.77 209.74 L 197.63 209.81 L 197.50 209.88 L 197.36 209.96 L 197.23 210.03 L 197.10 210.11 L 196.98 210.20 L 196.85 210.28 L 196.72 210.38 L 196.59 210.48 L 196.50 210.55" />' +
                    '<path d="M 169.10 252.80 L 169.82 253.22 L 170.86 253.82 L 171.90 254.40 L 172.86 254.89 L 173.82 255.36 L 174.80 255.80 L 175.82 256.22 L 176.85 256.62 L 177.80 257.00 L 178.60 257.34 L 179.31 257.66 L 180.04 258.00 L 180.84 258.38 L 181.67 258.78 L 182.49 259.16 L 183.27 259.53 L 184.05 259.88 L 184.85 260.18 L 185.69 260.43 L 186.56 260.64 L 187.43 260.81 L 188.27 260.95 L 189.10 261.06 L 189.93 261.13 L 190.77 261.16 L 191.62 261.15 L 192.48 261.10 L 193.37 261.01 L 194.27 260.89 L 195.16 260.73 L 196.01 260.53 L 196.84 260.29 L 197.68 260.01 L 198.54 259.68 L 199.40 259.30 L 200.26 258.88 L 201.11 258.44 L 201.95 257.96 L 202.79 257.46 L 203.63 256.95 L 204.46 256.42 L 205.29 255.90 L 206.12 255.40 L 206.94 254.91 L 207.75 254.40 L 208.53 253.88 L 209.30 253.35 L 210.07 252.80 L 210.85 252.23 L 211.62 251.63 L 212.37 251.00 L 213.08 250.33 L 213.77 249.63 L 214.44 248.90 L 215.10 248.15 L 215.75 247.38 L 216.39 246.60 L 217.01 245.82 L 217.62 245.03 L 218.21 244.20 L 218.76 243.30 L 219.29 242.36 L 219.81 241.40 L 220.32 240.45 L 220.82 239.49 L 221.29 238.50 L 221.70 237.49 L 222.08 236.46 L 222.44 235.40 L 222.78 234.29 L 223.09 233.14 L 223.37 232.00 L 223.63 230.87 L 223.87 229.74 L 224.07 228.60 L 224.23 227.44 L 224.36 226.26 L 224.45 225.10 L 224.50 223.96 L 224.51 222.83 L 224.49 221.70 L 224.43 220.56 L 224.33 219.42 L 224.19 218.30 L 224.02 217.21 L 223.81 216.14 L 223.56 215.10 L 223.28 214.07 L 222.96 213.07 L 222.58 212.10 L 222.15 211.16 L 221.68 210.26 L 221.16 209.40 L 220.60 208.59 L 220.00 207.83 L 219.38 207.10 L 218.72 206.40 L 218.04 205.73 L 217.33 205.10 L 216.59 204.49 L 215.82 203.92 L 215.03 203.40 L 214.21 202.95 L 213.38 202.56 L 212.55 202.20 L 211.73 201.86 L 210.92 201.56 L 210.09 201.30 L 209.21 201.09 L 208.31 200.91 L 207.44 200.80 L 206.64 200.75 L 205.87 200.75 L 205.00 200.80 L 203.95 200.89 L 202.81 201.01 L 201.70 201.20 L 200.67 201.45 L 199.67 201.75 L 198.70 202.10 L 197.74 202.49 L 196.80 202.91 L 195.90 203.40 L 195.03 203.94 L 194.19 204.54 L 193.40 205.20 L 192.68 205.94 L 192.02 206.75 L 191.40 207.60 L 190.81 208.48 L 190.27 209.41 L 189.80 210.40 L 189.40 211.47 L 189.07 212.61 L 188.80 213.80 L 188.61 215.21 L 188.48 216.67 L 188.40 217.70" />' +
                  '</g>' +
                '</svg>' +
              '</span>' +
              '<span class="font-mono font-bold tracking-tight text-ink text-base sm:text-lg">aslang<span class="text-signal font-normal">.dev</span></span>' +
            '</div>' +
          '</a>' +
          '<a href="/mascot" class="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-[11px] font-mono font-semibold bg-signal/15 text-signal border border-signal/30 hover:bg-signal/25 transition-all shadow-[0_0_10px_rgba(176,96,255,0.2)]" title="Mascot Development Preview">' +
            '<span class="w-1.5 h-1.5 rounded-full bg-signal animate-pulse"></span>' +
            'Mascot' +
          '</a>' +
        '</div>' +
        '<nav class="flex items-center gap-1 sm:gap-2 shrink-0">' +
          '<a href="/" class="px-3 py-1 rounded-full font-mono text-sm text-ink hover:text-signal hover:bg-surface-2 transition-colors">Home</a>' +
          '<a href="/docs" class="px-3 py-1 rounded-full font-mono text-sm text-ink-muted hover:text-ink hover:bg-surface-2 transition-colors">Docs</a>' +
          '<a href="/blog" class="px-3 py-1 rounded-full font-mono text-sm text-ink-muted hover:text-ink hover:bg-surface-2 transition-colors">Blog</a>' +
          '<a href="https://github.com/genseam/asl" target="_blank" rel="noreferrer" class="px-3 py-1 rounded-full font-mono text-sm text-ink-muted hover:text-ink hover:bg-surface-2 transition-colors flex items-center gap-1">GitHub</a>' +
        '</nav>' +
        '<div class="flex items-center gap-2 shrink-0">' +
          '<button type="button" aria-label="Toggle theme" class="asl-theme-toggle p-2 rounded-full border border-line text-ink-muted hover:text-signal hover:border-signal/50 transition-colors flex items-center justify-center" onclick="(function(){var cur=localStorage.getItem(\\'asl-theme\\')||\\'dark\\';var next=cur===\\'dark\\'?\\'light\\':\\'dark\\';localStorage.setItem(\\'asl-theme\\',next);document.documentElement.classList.remove(cur);document.documentElement.classList.add(next);})()">' +
            '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="dark:hidden"><circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/></svg>' +
            '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="hidden dark:block"><path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/></svg>' +
          '</button>' +
        '</div>' +
      '</header>' +
    '</div>' +
  '</div>';
}

export { renderNavbar as navbar, renderNavbar as navbarView, renderNavbar as default };
`,
          map: null
        };
      }

      // Handle Hero.asl specifically
      if (rawFilename === 'Hero') {
        return {
          code: `import { viewChameleon } from './Mascot.asl';

export function renderHero() {
  const chameleonSvg = typeof viewChameleon === 'function' ? viewChameleon() : '';
  return '<section id="top" class="relative pt-24 pb-16 sm:pt-28 sm:pb-20 overflow-hidden ambient-top-light">' +
    '<div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10 space-y-12">' +
      '<div class="grid grid-cols-1 lg:grid-cols-12 gap-8 lg:gap-12 items-center">' +
        '<div class="lg:col-span-5 flex flex-col justify-center items-center relative py-4">' +
          '<div class="absolute inset-0 bg-signal/20 blur-3xl rounded-full pointer-events-none scale-110"></div>' +
          '<div class="neon-svg-glow transition-transform duration-300 hover:scale-105">' +
            chameleonSvg +
          '</div>' +
          '<div class="mt-2 font-mono text-[11px] text-ink-3 tracking-wider uppercase text-center">AX-4 Chameleon · Sovereign Agent Substrate</div>' +
        '</div>' +
        '<div class="lg:col-span-7 space-y-5 text-left">' +
          '<div class="flex items-center gap-2 flex-wrap">' +
            '<span class="font-mono text-xs px-3 py-1 rounded-full bg-signal/15 text-signal border border-signal/30 font-semibold shadow-[0_0_12px_rgba(176,96,255,0.25)]">v0.4.1 [clean-break]</span>' +
            '<span class="font-mono text-xs px-3 py-1 rounded-full bg-surface text-ink-2 border border-line">Universal Multi-Target</span>' +
            '<span class="font-mono text-xs px-3 py-1 rounded-full bg-surface text-signal border border-line font-medium">~68% Token Savings</span>' +
            '<span class="font-mono text-xs px-3 py-1 rounded-full bg-surface text-ink-2 border border-line">Self-Hosted & Portable</span>' +
          '</div>' +
          '<h1 class="text-display font-bold text-ink tracking-tight text-3xl sm:text-4xl lg:text-5xl leading-[1.1] neon-title-gradient">' +
            'The Universal Polyglot Substrate for <span class="text-signal neon-text-glow">Autonomous Agents</span>' +
          '</h1>' +
          '<p class="text-lead text-ink-2 leading-relaxed text-base sm:text-lg">' +
            'Engineered for autonomous models: impossible to write bad code, balanced single-pass S-expressions, average 68% token reduction, and clean ahead-of-time transpilation into C99, WebAssembly, Python, and TypeScript.' +
          '</p>' +
        '</div>' +
      '</div>' +
      '<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">' +
        '<div class="p-5 rounded-2xl neon-card flex flex-col justify-between">' +
          '<div class="flex items-center gap-2 mb-2">' +
            '<span class="w-2.5 h-2.5 rounded-full bg-signal shadow-[0_0_8px_#B060FF]"></span>' +
            '<h3 class="font-bold text-ink text-sm font-sans tracking-tight">Multi-Target Transpilation</h3>' +
          '</div>' +
          '<p class="text-xs text-ink-3 leading-relaxed font-sans">Clean ahead-of-time emission into C99, WASM, Python, and TypeScript with zero runtime baggage and ~68% token reduction.</p>' +
        '</div>' +
        '<div class="p-5 rounded-2xl neon-card flex flex-col justify-between">' +
          '<div class="flex items-center gap-2 mb-2">' +
            '<span class="w-2.5 h-2.5 rounded-full bg-signal shadow-[0_0_8px_#B060FF]"></span>' +
            '<h3 class="font-bold text-ink text-sm font-sans tracking-tight">Global Agent Toolbelt</h3>' +
          '</div>' +
          '<p class="text-xs text-ink-3 leading-relaxed font-sans">1-command global injection via asl toolbelt across Claude Code, Cursor, Windsurf, Antigravity, Factory Droid, and Codex.</p>' +
        '</div>' +
        '<div class="p-5 rounded-2xl neon-card flex flex-col justify-between">' +
          '<div class="flex items-center gap-2 mb-2">' +
            '<span class="w-2.5 h-2.5 rounded-full bg-signal shadow-[0_0_8px_#B060FF]"></span>' +
            '<h3 class="font-bold text-ink text-sm font-sans tracking-tight">Autonomous Subagents & Harness</h3>' +
          '</div>' +
          '<p class="text-xs text-ink-3 leading-relaxed font-sans">Enforce correct-by-construction code, scoped permissions, and custom system prompt overrides (asl launch) with deterministic receipts.</p>' +
        '</div>' +
        '<div class="p-5 rounded-2xl neon-card flex flex-col justify-between">' +
          '<div class="flex items-center gap-2 mb-2">' +
            '<span class="w-2.5 h-2.5 rounded-full bg-signal shadow-[0_0_8px_#B060FF]"></span>' +
            '<h3 class="font-bold text-ink text-sm font-sans tracking-tight">In-Memory VFS & State</h3>' +
          '</div>' +
          '<p class="text-xs text-ink-3 leading-relaxed font-sans">Sub-15ms BM25 vector queries, staged RAM buffer edits (asl mem), and stateless 9-syscall isolation across any host.</p>' +
        '</div>' +
      '</div>' +
      '<div class="max-w-2xl mx-auto flex flex-col items-center gap-3.5 w-full pt-4">' +
        '<div class="install-terminal asl-install-bar neon-glow-pill p-4 rounded-2xl font-mono text-sm flex items-center justify-between w-full transition-transform duration-200 hover:scale-[1.01]">' +
          '<div class="flex items-center gap-2.5">' +
            '<span class="text-signal text-xs font-bold">&gt;_</span>' +
            '<span class="text-ink font-medium">curl -fsSL https://aslang.dev/install.sh | sh</span>' +
          '</div>' +
          '<span class="text-signal text-xs font-semibold px-3 py-1 rounded-lg bg-signal/15 border border-signal/30 cursor-pointer copy-btn hover:bg-signal/25 transition-colors" onclick="(function(btn){navigator.clipboard.writeText(\\'curl -fsSL https://aslang.dev/install.sh | sh\\').then(function(){var o=btn.textContent;btn.textContent=\\'COPIED!\\';setTimeout(function(){btn.textContent=o;},2000);});})(this)">COPY</span>' +
        '</div>' +
        '<div class="p-3 rounded-xl bg-surface/60 border border-line/60 font-mono text-xs flex items-center justify-between w-full max-w-xl">' +
          '<div class="flex items-center gap-2">' +
            '<span class="text-signal font-semibold">AGENTS</span>' +
            '<span class="text-ink-2">asl toolbelt install --all</span>' +
          '</div>' +
          '<span class="text-ink-3 hover:text-signal cursor-pointer copy-btn font-medium" onclick="(function(btn){navigator.clipboard.writeText(\\'asl toolbelt install --all\\').then(function(){var o=btn.textContent;btn.textContent=\\'COPIED!\\';setTimeout(function(){btn.textContent=o;},2000);});})(this)">COPY</span>' +
        '</div>' +
      '</div>' +
    '</div>' +
  '</section>';
}

export { renderHero as viewHero, renderHero as heroView, renderHero as default };
`,
          map: null
        };
      }

      // Handle Footer.asl specifically
      if (rawFilename === 'Footer') {
        return {
          code: `export function renderFooter() {
  return '<footer class="relative pt-12 pb-14 border-t border-line bg-surface/50 mt-16">' +
    '<div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 mb-8 flex flex-col items-center justify-center">' +
      '<div class="group relative flex flex-col items-center cursor-pointer" title="Leon the Chameleon">' +
        '<div class="opacity-0 group-hover:opacity-100 transition-opacity duration-300 transform translate-y-1 group-hover:translate-y-0 mb-3 px-3.5 py-1.5 rounded-2xl bg-surface/95 backdrop-blur-xl border border-line shadow-e2 text-micro font-mono text-ink flex items-center gap-2 pointer-events-none">' +
          '<span class="w-1.5 h-1.5 rounded-full bg-signal animate-pulse shrink-0"></span>' +
          '<span>Formally verified from head to tail!</span>' +
        '</div>' +
        '<div class="relative">' +
          '<div class="absolute inset-0 rounded-full bg-signal/15 blur-2xl group-hover:bg-signal/30 transition-opacity scale-125 pointer-events-none"></div>' +
          '<img src="/chameleon.png" alt="Leon the Chameleon" class="relative z-10 w-24 sm:w-28 h-auto select-none transition-transform duration-300 transform group-hover:scale-105 group-active:scale-95 drop-shadow-[0_0_15px_rgba(192,132,252,0.35)]" />' +
        '</div>' +
        '<span class="mt-2 font-mono text-2xs uppercase tracking-widest text-ink-3 group-hover:text-signal transition-colors">Leon the Chameleon</span>' +
      '</div>' +
    '</div>' +
    '<div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 flex flex-col md:flex-row md:items-center justify-between gap-6">' +
      '<div class="flex items-center gap-3">' +
        '<svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg" class="w-6 h-6">' +
          '<polygon points="16,2 28,9 28,23 16,30 4,23 4,9" stroke="#5E4B7C" stroke-width="1.5" fill="#181327" />' +
          '<circle cx="16" cy="16" r="8" stroke="#B060FF" stroke-width="1.5" />' +
          '<circle cx="16" cy="16" r="3" fill="#C084FC" />' +
        '</svg>' +
        '<span class="font-sans font-semibold text-ink text-brand">aslang<span class="text-signal">.dev</span></span>' +
      '</div>' +
      '<nav class="flex flex-wrap items-center gap-6 font-mono text-xs text-ink-2">' +
        '<a href="/docs" class="hover:text-signal transition-colors">Documentation</a>' +
        '<a href="/blog" class="hover:text-signal transition-colors">Blog</a>' +
        '<a href="https://github.com/genseam/asl" target="_blank" rel="noreferrer" class="hover:text-signal transition-colors">GitHub</a>' +
        '<a href="/llms.txt" class="text-signal hover:underline">Agent Spec (llms.txt)</a>' +
      '</nav>' +
    '</div>' +
    '<div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 mt-6 pt-6 border-t border-line/40 flex flex-col sm:flex-row items-center justify-between gap-4 font-mono text-micro text-ink-3">' +
      '<p>MIT Licensed. Single-pass S-expression language and wire protocol for autonomous AI agents.</p>' +
      '<p>Ahead-of-time compiled to pure ANSI C99.</p>' +
    '</div>' +
  '</footer>';
}

export { renderFooter as footerView, renderFooter as footer, renderFooter as default };
`,
          map: null
        };
      }

      // Handle Mascot.asl specifically
      if (rawFilename === 'Mascot') {
        const mascotPath = path.resolve(__dirname, '../src/components/Mascot.asl');
        let mascotContent = '';
        try {
          if (fs.existsSync(mascotPath)) {
            mascotContent = fs.readFileSync(mascotPath, 'utf-8');
          }
        } catch (e) {}
        const strs = extractStrings(mascotContent);
        const chameleonSvg = strs.find(s => s.includes('<svg') && s.includes('asl-mascot')) || '';
        return {
          code: `export function chameleonApertureIris() {
  return '<g class="aperture-eye"><circle cx="351" cy="65" r="23.5" stroke="#A855F7" stroke-width="2.8" fill="#181327" /><circle cx="351" cy="65" r="8.5" stroke="#f5d0fe" stroke-width="2" fill="none" /></g>';
}

export function viewChameleon() {
  return ${JSON.stringify(chameleonSvg)};
}

export { viewChameleon as default };
`,
          map: null
        };
      }

      // Handle MascotLabView.asl specifically
      if (rawFilename === 'MascotLabView') {
        const mascotLabPath = path.resolve(__dirname, '../src/views/MascotLabView.asl');
        let labContent = '';
        try {
          if (fs.existsSync(mascotLabPath)) {
            labContent = fs.readFileSync(mascotLabPath, 'utf-8');
          }
        } catch (e) {}
        const strs = extractStrings(labContent);
        const htmlStr = strs.find(s => s.includes('<div') && (s.includes('R-01') || s.includes('Mascot'))) || strs.find(s => s.includes('<div')) || '';
        return {
          code: `export function renderMascotLabView() {
  return ${JSON.stringify(htmlStr)};
}
export { renderMascotLabView as mascotLabView, renderMascotLabView as default };
`,
          map: null
        };
      }

      // Handle HomeView.asl specifically
      if (rawFilename === 'HomeView') {
        return {
          code: `import { renderHero } from '../components/Hero.asl';
import { renderArchitecture } from '../components/ArchitecturePipeline.asl';
import { renderEcosystem } from '../components/Ecosystem.asl';
import { capabilitiesView } from '../components/KeyCapabilities.asl';
import { agentWayView } from '../components/TheAgentWay.asl';
import { renderWireProtocol } from '../components/AgentWireProtocol.asl';
import { harnessView } from '../components/HarnessToolkit.asl';
import { renderModuleGraphVisualizer } from '../components/ModuleGraphVisualizer.asl';
import { renderEngineeringBlog } from '../components/EngineeringBlog.asl';
import { renderInBrowserAgent } from '../components/InBrowserAgent.asl';

export function describeHomeView() {
  return '(view :id "home" :components ["hero" "architecture" "ecosystem" "capabilities" "agent-way" "wire-protocol" "harness" "module-graph" "blog" "in-browser-agent"])';
}

export function renderHomeView() {
  return (
    '<main class="flex-1">' +
    renderHero() +
    renderArchitecture() +
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
  return renderHomeView();
}
`,
          map: null
        };
      }

      // Handle ArticleDetailView.asl specifically
      if (rawFilename === 'ArticleDetailView') {
        const postsAsnPath = path.resolve(__dirname, '../src/data/blog/posts.asn');
        let posts = [];
        try {
          if (fs.existsSync(postsAsnPath)) {
            const raw = fs.readFileSync(postsAsnPath, 'utf-8');
            posts = parseAsnPosts(raw);
          }
        } catch (e) {}

        return {
          code: `const BLOG_POSTS = ${JSON.stringify(posts)};

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
  let out = text.replace(new RegExp(String.fromCharCode(96) + '([^' + String.fromCharCode(96) + ']+)' + String.fromCharCode(96), 'g'), (_, code) => {
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

    if (trimmed.startsWith(String.fromCharCode(96, 96, 96))) {
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

export function ArticleDetailView({ slug = '' } = {}) {
  return renderArticleDetailView(slug);
}

export { ArticleDetailView as default };
`,
          map: null
        };
      }

function parseConcat(fnCode) {
  const withoutDoc = fnCode.replace(/:d\s+"(?:[^"\\]|\\.)*"/, '');
  const concatIdx = withoutDoc.indexOf('(s/concat');
  if (concatIdx === -1) return null;

  let p = concatIdx + 9;
  const parts = [];
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

function parseFunctions(str) {
  const fns = [];
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

function extractStrings(str) {
  const strs = [];
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

function transpileVNodeHtml(code) {
  if (!code.includes('(h/vnodeToHtml')) return null;

  let tag = 'div';
  const tagMatch = code.match(/\(h\/(sec|footer|main|header|nav|aside|div|section)\b/);
  if (tagMatch) {
    tag = tagMatch[1] === 'sec' ? 'section' : tagMatch[1];
  }

  const attrs = [];
  const idMatch = code.match(/\(h\/attrId\s+"([^"]+)"\)/);
  if (idMatch) attrs.push(`id="${idMatch[1]}"`);

  const classMatch = code.match(/\(h\/attrClass\s+"([^"]+)"\)/);
  if (classMatch) attrs.push(`class="${classMatch[1]}"`);

  const customAttrRegex = /\(h\/attr\s+"([^"]+)"\s+"([^"]+)"\)/g;
  let customMatch;
  while ((customMatch = customAttrRegex.exec(code)) !== null) {
    attrs.push(`${customMatch[1]}="${customMatch[2]}"`);
  }

  const attrStr = attrs.length > 0 ? ' ' + attrs.join(' ') : '';

  let innerHtml = '';
  let rawIdx = 0;
  while ((rawIdx = code.indexOf('(h/raw', rawIdx)) !== -1) {
    const firstQuote = code.indexOf('"', rawIdx);
    if (firstQuote === -1) break;
    let pos = firstQuote + 1;
    let rawStr = '';
    while (pos < code.length) {
      if (code[pos] === '\\' && pos + 1 < code.length) {
        const next = code[pos + 1];
        if (next === 'n') rawStr += '\n';
        else if (next === 't') rawStr += '\t';
        else if (next === 'r') rawStr += '\r';
        else if (next === '"') rawStr += '"';
        else if (next === '\\') rawStr += '\\';
        else rawStr += next;
        pos += 2;
      } else if (code[pos] === '"') {
        pos++;
        break;
      } else {
        rawStr += code[pos++];
      }
    }
    innerHtml += rawStr;
    rawIdx = pos;
  }

  if (innerHtml) {
    return `<${tag}${attrStr}>${innerHtml}</${tag}>`;
  }

  return null;
}

      // For all other .asl files: transpile their functions!
      const parsedFns = parseFunctions(content);
      const exportedFns = [];
      const exportedComponents = [];

      for (const fn of parsedFns) {
        const fnNameKebab = fn.name;
        const fnNameCamel = fnNameKebab.replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase());
        const fnNamePascal = fnNameCamel.charAt(0).toUpperCase() + fnNameCamel.slice(1);
        const codeWithoutDoc = fn.code.replace(/:d\s+"(?:[^"\\]|\\.)*"/, '');
        const vnodeHtml = transpileVNodeHtml(codeWithoutDoc);
        if (vnodeHtml) {
          exportedFns.push(`export function ${fnNameCamel}() {\n  return ${JSON.stringify(vnodeHtml)};\n}`);
        } else if (codeWithoutDoc.includes('(s/concat')) {
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
  return html;
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
          `  return typeof ${renderFnName} === 'function' ? ${renderFnName}(props) : '';\n` +
          `}\nexport { ${componentName} as default };\n`;

      return {
        code: exportedFns.join('\n\n') + '\n\n' +
          exportedComponents.join('\n\n') + '\n\n' +
          defaultComponentDecl,
        map: null
      };
    }
  };
}

