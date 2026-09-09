import { getBlogPostBySlug, getRelatedPosts, BlogPost } from '../lib/blog';

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function renderInlineMarkdown(text: string): string {
  // Inline code `code`
  let out = text.replace(/`([^`]+)`/g, (_, code) => {
    return `<code class="px-1.5 py-0.5 rounded bg-surface-2 border border-line text-signal font-mono text-xs">${escapeHtml(code)}</code>`;
  });

  // Math inline $...$
  out = out.replace(/\$([^\$]+)\$/g, (_, math) => {
    return `<span class="font-mono text-xs px-1.5 py-0.5 rounded bg-surface-2 text-cyan-300">${escapeHtml(math)}</span>`;
  });

  // Bold **text**
  out = out.replace(/\*\*([^*]+)\*\*/g, '<strong class="font-semibold text-ink">$1</strong>');

  // Italic *text*
  out = out.replace(/(?<!\*)\*([^*]+)\*(?!\*)/g, '<em class="italic text-ink-2">$1</em>');

  // Links [text](url)
  out = out.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, label, url) => {
    const isExternal = url.startsWith('http') || url.startsWith('//');
    const targetAttr = isExternal ? ' target="_blank" rel="noreferrer"' : '';
    return `<a href="${url}" class="text-signal hover:underline underline-offset-4 decoration-signal/50 font-medium transition-colors"${targetAttr}>${label}</a>`;
  });

  return out;
}

export function renderMarkdownToHtml(md: string): string {
  if (!md) return '';

  const lines = md.split('\n');
  const out: string[] = [];

  let inCodeBlock = false;
  let codeBlockLang = '';
  let codeBlockLines: string[] = [];

  let inTable = false;
  let tableHeaders: string[] = [];
  let tableRows: string[][] = [];

  let inList = false;
  let listType: 'ul' | 'ol' = 'ul';
  let listItems: string[] = [];

  let inBlockquote = false;
  let blockquoteLines: string[] = [];

  function flushList() {
    if (!inList) return;
    const tag = listType;
    const itemsHtml = listItems
      .map(item => `<li class="leading-relaxed">${renderInlineMarkdown(item)}</li>`)
      .join('\n');
    out.push(`<${tag} class="my-5 space-y-2 ${tag === 'ul' ? 'list-disc' : 'list-decimal'} list-inside text-ink-2 text-sm sm:text-base pl-2">${itemsHtml}</${tag}>`);
    inList = false;
    listItems = [];
  }

  function flushBlockquote() {
    if (!inBlockquote) return;
    const innerHtml = blockquoteLines.map(line => renderInlineMarkdown(line)).join('<br/>');
    out.push(`<blockquote class="my-6 border-l-2 border-signal pl-4 sm:pl-6 py-2 bg-signal/5 rounded-r-xl text-ink-2 italic">${innerHtml}</blockquote>`);
    inBlockquote = false;
    blockquoteLines = [];
  }

  function flushTable() {
    if (!inTable) return;
    const thead = tableHeaders.map(h => `<th class="p-3 font-semibold text-ink border-b border-line bg-surface-2/80">${renderInlineMarkdown(h)}</th>`).join('');
    const tbody = tableRows.map(row => {
      const tds = row.map(cell => `<td class="p-3 border-b border-line/60">${renderInlineMarkdown(cell)}</td>`).join('');
      return `<tr class="hover:bg-surface-2/40 transition-colors">${tds}</tr>`;
    }).join('\n');

    out.push(`
      <div class="my-8 overflow-x-auto rounded-2xl border border-line bg-surface/50 shadow-e1">
        <table class="w-full text-left border-collapse text-xs sm:text-sm font-mono">
          <thead><tr>${thead}</tr></thead>
          <tbody class="divide-y divide-line/60 text-ink-2">${tbody}</tbody>
        </table>
      </div>
    `);
    inTable = false;
    tableHeaders = [];
    tableRows = [];
  }

  // Strip leading H1 title and author line if present (since rendered in article hero)
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

    // Code block handling
    if (trimmed.startsWith('```')) {
      if (inCodeBlock) {
        // End of code block
        const escaped = escapeHtml(codeBlockLines.join('\n'));
        const badgeLang = codeBlockLang || 'code';
        out.push(`
          <div class="relative my-6 rounded-2xl border border-line bg-ground overflow-hidden shadow-e1 group">
            <div class="flex items-center justify-between px-4 py-2 bg-surface-2/60 border-b border-line text-micro font-mono text-ink-3">
              <span class="font-semibold uppercase tracking-wider text-signal">${badgeLang}</span>
              <span class="text-[10px] opacity-70">pure AST</span>
            </div>
            <pre class="p-4 sm:p-5 overflow-x-auto font-mono text-xs sm:text-sm text-ink leading-relaxed"><code>${escaped}</code></pre>
          </div>
        `);
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

    // HTML comments <!-- ... -->
    if (trimmed.startsWith('<!--') && trimmed.endsWith('-->')) {
      continue;
    }

    // Table row detection (| col | col |)
    if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
      flushList();
      flushBlockquote();
      const cells = trimmed
        .slice(1, -1)
        .split('|')
        .map(c => c.trim());

      // Check if separator row |---|---|
      const isSeparator = cells.every(c => /^:?-+:?$/.test(c));
      if (isSeparator) {
        continue;
      }

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

    // Blockquote (> ...)
    if (trimmed.startsWith('>')) {
      flushList();
      flushTable();
      inBlockquote = true;
      blockquoteLines.push(trimmed.replace(/^>\s?/, ''));
      continue;
    } else if (inBlockquote) {
      flushBlockquote();
    }

    // Empty line
    if (!trimmed) {
      flushList();
      flushBlockquote();
      flushTable();
      continue;
    }

    // Horizontal rule
    if (trimmed === '---' || trimmed === '***' || trimmed === '___') {
      flushList();
      flushBlockquote();
      flushTable();
      out.push('<hr class="my-10 border-line" />');
      continue;
    }

    // Math block $$...$$
    if (trimmed.startsWith('$$') && trimmed.endsWith('$$') && trimmed.length > 4) {
      flushList();
      flushBlockquote();
      flushTable();
      const math = trimmed.slice(2, -2).trim();
      out.push(`
        <div class="my-6 p-4 rounded-xl border border-line bg-surface/50 text-center font-mono text-sm text-cyan-300 overflow-x-auto">
          ${escapeHtml(math)}
        </div>
      `);
      continue;
    }

    // Headings
    if (trimmed.startsWith('#### ')) {
      flushList();
      flushBlockquote();
      flushTable();
      out.push(`<h4 class="text-base sm:text-lg font-bold text-ink mt-8 mb-3 tracking-tight">${renderInlineMarkdown(trimmed.slice(5))}</h4>`);
      continue;
    }
    if (trimmed.startsWith('### ')) {
      flushList();
      flushBlockquote();
      flushTable();
      out.push(`<h3 class="text-lg sm:text-xl font-bold text-ink mt-10 mb-4 tracking-tight">${renderInlineMarkdown(trimmed.slice(4))}</h3>`);
      continue;
    }
    if (trimmed.startsWith('## ')) {
      flushList();
      flushBlockquote();
      flushTable();
      out.push(`<h2 class="text-xl sm:text-2xl font-extrabold text-ink mt-14 mb-5 tracking-tight pb-3 border-b border-line">${renderInlineMarkdown(trimmed.slice(3))}</h2>`);
      continue;
    }
    if (trimmed.startsWith('# ')) {
      flushList();
      flushBlockquote();
      flushTable();
      out.push(`<h1 class="text-2xl sm:text-3xl font-extrabold text-ink mt-16 mb-6 tracking-tight">${renderInlineMarkdown(trimmed.slice(2))}</h1>`);
      continue;
    }

    // Lists (* item or - item or 1. item)
    const ulMatch = trimmed.match(/^[-*]\s+(.*)$/);
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

    const olMatch = trimmed.match(/^(\d+)\.\s+(.*)$/);
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

    // Standard paragraph
    out.push(`<p class="text-sm sm:text-base text-ink-2 leading-relaxed mb-6 font-normal">${renderInlineMarkdown(trimmed)}</p>`);
  }

  flushList();
  flushBlockquote();
  flushTable();

  return out.join('\n');
}

export function renderArticleDetailView(slug: string): string {
  const post = getBlogPostBySlug(slug);

  if (!post) {
    return `
      <main class="flex-1 max-w-4xl mx-auto px-4 sm:px-6 py-16 sm:py-24 w-full" id="bv-article-404">
        <a href="/blog" class="asl-article-back inline-flex items-center gap-2 text-xs font-mono text-ink-2 hover:text-signal transition-colors mb-10 group">
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="group-hover:-translate-x-1 transition-transform">
            <line x1="19" y1="12" x2="5" y2="12"></line>
            <polyline points="12 19 5 12 12 5"></polyline>
          </svg>
          <span>Back to all essays</span>
        </a>
        <div class="p-8 sm:p-12 rounded-3xl border border-line bg-surface/70 text-center space-y-4 shadow-e2">
          <div class="inline-flex items-center justify-center w-12 h-12 rounded-2xl bg-signal/10 border border-signal/20 text-signal font-mono font-bold text-lg">
            404
          </div>
          <h1 class="text-2xl sm:text-3xl font-bold text-ink">Essay Not Found</h1>
          <p class="text-sm sm:text-base text-ink-2 max-w-md mx-auto">
            The technical essay "${escapeHtml(slug)}" could not be located in the current publication registry.
          </p>
          <div class="pt-4">
            <a href="/blog" class="asl-article-back inline-flex items-center gap-2 px-5 py-2.5 rounded-xl bg-signal text-ground font-mono text-xs font-semibold shadow-sm hover:opacity-95 transition-all">
              Return to Blog Catalog &rarr;
            </a>
          </div>
        </div>
      </main>
    `;
  }

  const related = getRelatedPosts(slug, 2);
  const bodyHtml = renderMarkdownToHtml(post.content);

  const tagsHtml = (post.tags || [])
    .map(t => `<span class="inline-flex items-center text-[10px] font-mono px-2 py-0.5 rounded-md bg-surface-2 border border-line/60 text-ink-3">#${escapeHtml(t)}</span>`)
    .join(' ');

  const importanceBadge = post.importance === 'flagship'
    ? `<span class="px-2 py-0.5 rounded border border-cyan-400/40 bg-cyan-400/10 text-cyan-300 font-semibold text-[10px]">★ Flagship</span>`
    : `<span class="px-2 py-0.5 rounded border border-line bg-surface-2 text-ink-3 font-mono text-[10px] uppercase">${escapeHtml(post.importance || 'technical')}</span>`;

  const relatedHtml = related.length > 0 ? `
    <section class="mt-20 pt-12 border-t border-line">
      <div class="flex items-center justify-between mb-8">
        <h3 class="text-lg sm:text-xl font-bold text-ink font-sans">Related Engineering Essays</h3>
        <a href="/blog" class="asl-article-back text-xs font-mono text-signal hover:underline">View all &rarr;</a>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        ${related.map(r => `
          <article class="bv-post-card p-6 rounded-2xl border border-line bg-surface/70 hover:bg-surface hover:border-signal/60 cursor-pointer transition-all duration-200 group flex flex-col justify-between shadow-e1 hover:shadow-e2" data-slug="${escapeHtml(r.slug)}">
            <div>
              <div class="flex items-center justify-between text-micro font-mono text-ink-3 mb-3">
                <span class="px-2 py-0.5 rounded border border-signal/30 bg-signal/5 text-signal uppercase tracking-wider font-medium">${escapeHtml(r.category)}</span>
                <span>${escapeHtml(r.readTime)}</span>
              </div>
              <h4 class="text-base font-bold text-ink group-hover:text-signal transition-colors mb-2 line-clamp-2">${escapeHtml(r.title)}</h4>
              <p class="text-meta text-ink-2 line-clamp-2 mb-4">${escapeHtml(r.excerpt)}</p>
            </div>
            <div class="flex items-center justify-between pt-3 border-t border-line/60 text-micro font-mono text-ink-3">
              <span>${escapeHtml(r.date)} • ${escapeHtml(r.author)}</span>
              <span class="text-signal font-semibold group-hover:translate-x-0.5 transition-transform">&rarr;</span>
            </div>
          </article>
        `).join('')}
      </div>
    </section>
  ` : '';

  return `
    <main class="flex-1 max-w-4xl mx-auto px-4 sm:px-6 py-12 sm:py-16 w-full" id="bv-article-view">
      <!-- Top Navigation -->
      <div class="mb-10 sm:mb-14 flex items-center justify-between">
        <a href="/blog" class="asl-article-back inline-flex items-center gap-2 text-xs font-mono text-ink-2 hover:text-signal transition-colors group">
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="group-hover:-translate-x-1 transition-transform">
            <line x1="19" y1="12" x2="5" y2="12"></line>
            <polyline points="12 19 5 12 12 5"></polyline>
          </svg>
          <span>Back to all essays</span>
        </a>
        <div class="flex items-center gap-2 text-micro font-mono text-ink-3">
          <span>${escapeHtml(post.date)}</span>
          <span>•</span>
          <span>${escapeHtml(post.readTime)}</span>
        </div>
      </div>

      <!-- Article Header -->
      <header class="mb-12 sm:mb-16">
        <div class="flex items-center gap-2 flex-wrap mb-4">
          <span class="px-2.5 py-0.5 rounded-full border border-signal/30 bg-signal/5 text-signal font-mono text-micro uppercase tracking-wider font-semibold">
            ${escapeHtml(post.category)}
          </span>
          ${importanceBadge}
        </div>
        <h1 class="text-2xl sm:text-4xl md:text-5xl font-extrabold text-ink tracking-tight leading-tight text-balance mb-6">
          ${escapeHtml(post.title)}
        </h1>
        <p class="text-base sm:text-xl text-ink-2 leading-relaxed font-normal text-balance mb-8">
          ${escapeHtml(post.excerpt)}
        </p>
        <div class="flex items-center justify-between flex-wrap gap-4 pt-6 border-t border-line/80 text-xs font-mono text-ink-3">
          <div class="flex items-center gap-3">
            <div class="w-8 h-8 rounded-full bg-signal/15 border border-signal/30 flex items-center justify-center text-signal font-bold text-xs">
              ${escapeHtml(post.author.slice(0, 2).toUpperCase())}
            </div>
            <div>
              <div class="font-semibold text-ink">${escapeHtml(post.author)}</div>
              <div class="text-micro text-ink-3">AgentScript Systems Research</div>
            </div>
          </div>
          <div class="flex items-center gap-1.5 flex-wrap">
            ${tagsHtml}
          </div>
        </div>
      </header>

      <!-- Article Content -->
      <div class="article-body text-ink border-t border-line pt-8">
        ${bodyHtml}
      </div>

      <!-- Bottom Author / Citation Box -->
      <div class="my-16 p-6 sm:p-8 rounded-2xl border border-line bg-surface/80 shadow-e1">
        <div class="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
          <div class="space-y-1">
            <div class="text-xs font-mono font-semibold text-signal uppercase tracking-wider">Canonical Citation</div>
            <div class="text-sm font-semibold text-ink">${escapeHtml(post.title)}</div>
            <div class="text-micro font-mono text-ink-3">Published ${escapeHtml(post.date)} • GenSEAM Systems Group • aslang.dev/blog/${escapeHtml(post.slug)}</div>
          </div>
          <a href="/blog" class="asl-article-back shrink-0 px-4 py-2 rounded-xl border border-line hover:border-signal text-xs font-mono text-ink-2 hover:text-signal transition-colors bg-surface-2/60">
            &larr; Return to Index
          </a>
        </div>
      </div>

      <!-- Related Posts -->
      ${relatedHtml}
    </main>
  `;
}
