import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '../..');
const blogDir = path.join(rootDir, 'docs/blog');
const outDir = path.join(rootDir, 'web/src/data/blog');

if (!fs.existsSync(outDir)) {
  fs.mkdirSync(outDir, { recursive: true });
}

const files = fs.readdirSync(blogDir).filter(f => f.endsWith('.md')).sort();

const metadataMap = {
  '01-why-llms-struggle-with-python-and-rust.md': {
    slug: 'why-llms-struggle-with-python-and-rust',
    category: 'Language Design',
    date: '2026-09-01',
    author: 'GenSEAM',
    readTime: '6 min read',
    excerpt: 'Why indentation and borrow-checked syntax cost LLMs 25% to 40% of their compute in repair loops, and what deterministic single-pass S-expressions solve.',
    tags: ['Grammars', 'LLM Autoregression', 'Syntax Repair Loop', 'S-Expressions']
  },
  '02-the-token-tax-and-interface-compression.md': {
    slug: 'the-token-tax-and-interface-compression',
    category: 'Context Architecture',
    date: '2026-09-02',
    author: 'GenSEAM',
    readTime: '5 min read',
    excerpt: 'How AST interface extraction slashes multi-agent token consumption by 78.2% and eliminates context rot across distributed agent handoffs.',
    tags: ['Context Rot', 'Token Compression', 'AST Extraction', 'Multi-Agent']
  },
  '03-from-vibe-code-to-wasm-in-0-04ms.md': {
    slug: 'from-vibe-code-to-wasm-in-0-04ms',
    category: 'Runtime & Execution',
    date: '2026-09-02',
    author: 'GenSEAM',
    readTime: '5 min read',
    excerpt: 'Replacing heavy Docker containers and microVMs with zero-overhead in-memory WebAssembly sandboxes running test suites in 0.038ms.',
    tags: ['WebAssembly', 'WASI', 'MicroVMs', 'Sub-millisecond Sandboxing']
  },
  '04-agent-script-the-optimal-agent-language.md': {
    slug: 'agent-script-the-optimal-agent-language',
    category: 'Language Theory',
    date: '2026-09-03',
    author: 'GenSEAM',
    readTime: '8 min read',
    excerpt: 'Why S-expressions, homoiconic ASTs, exhaustive pattern matching, and explicit effect boundaries are mathematically optimal for autoregressive LLMs.',
    tags: ['Homoiconicity', 'Algebraic Types', 'Exhaustive Matching', 'Deterministic AST']
  },
  '05-token-economy-and-structural-compression.md': {
    slug: 'token-economy-and-structural-compression',
    category: 'Token Optimization',
    date: '2026-09-03',
    author: 'GenSEAM',
    readTime: '8 min read',
    excerpt: 'The abbreviation fallacy under BPE tokenizers, why keyword shortening saves 0.00% tokens, and how structural compaction cuts prompt overhead by 65%.',
    tags: ['Byte-Pair Encoding', 'Structural Compaction', 'Tabular Serialization', 'Token Ceiling']
  },
  '06-inter-agent-protocols-and-wire-frames.md': {
    slug: 'inter-agent-protocols-and-wire-frames',
    category: 'Protocols & Mesh',
    date: '2026-09-04',
    author: 'GenSEAM',
    readTime: '7 min read',
    excerpt: 'Beyond conversational mesh chaos: replacing natural language chatter with typed S-expression frames, SeamBus (Simba) mesh, and zero-drift delegations.',
    tags: ['SeamBus', 'Simba', 'AgP Wire Protocol', 'Typed Frames', 'Conversational Mesh']
  },
  '07-the-agent-native-developer-cockpit.md': {
    slug: 'the-agent-native-developer-cockpit',
    category: 'Developer Tooling',
    date: '2026-09-04',
    author: 'GenSEAM',
    readTime: '9 min read',
    excerpt: 'The complete agent-native developer cockpit: sub-0.05ms LSP, AST structural clone linters, autonomous auto-fixers, and live visual observability.',
    tags: ['Language Server Protocol', 'AST Auto-Fixer', 'Observability', 'Sandboxing']
  },
  '08-multi-dimensional-observability-for-autonomous-systems.md': {
    slug: 'multi-dimensional-observability-for-autonomous-systems',
    category: 'Observability & Telemetry',
    date: '2026-09-04',
    author: 'GenSEAM',
    readTime: '7 min read',
    excerpt: 'How to govern autonomous swarms without reading raw logs: multi-dimensional AST topologies, real-time cycle guards, and jailed capability traces.',
    tags: ['Multi-Dimensional Observability', 'AST Topology', 'Token Telemetry', 'Capability Tracing']
  },
  '09-universal-cross-platform-glue-without-drift.md': {
    slug: 'universal-cross-platform-glue-without-drift',
    category: 'Cross-Platform Runtimes',
    date: '2026-09-04',
    author: 'GenSEAM',
    readTime: '8 min read',
    excerpt: 'Eliminating multi-language glue code and semantic drift: compiling pure AgentScript deterministically across WebAssembly, Rust, Go, TypeScript, and Python.',
    tags: ['Differential Verification', 'Multi-Backend', 'Cross-Platform Glue', 'Polyglot Parity']
  },
  '10-epistemic-grounding-and-anti-hallucination-firewalls.md': {
    slug: 'epistemic-grounding-and-anti-hallucination-firewalls',
    category: 'Safety & Grounding',
    date: '2026-09-04',
    author: 'GenSEAM',
    readTime: '8 min read',
    excerpt: 'Halting agent hallucinations at the AST compiler boundary with lexical closure audits, deterministic quote verification, and hardware-enforced path jailing.',
    tags: ['Epistemic Grounding', 'Anti-Hallucination', 'Closure Audit', 'Zero-Leak Jailing']
  },
  '11-zero-server-in-browser-agent-runtimes.md': {
    slug: 'zero-server-in-browser-agent-runtimes',
    category: 'Browser Technologies',
    date: '2026-09-04',
    author: 'GenSEAM',
    readTime: '7 min read',
    excerpt: 'Zero-server development inside browser tabs: booting WebAssembly sandboxes in 8ms, executing tests in 0.038ms via WASI and OPFS, with tiered local SLMs.',
    tags: ['In-Browser Dev', 'WebAssembly', 'OPFS', 'Tiered Local SLMs', 'Offline-First']
  },
  '12-cross-dialect-sql-without-hallucinations.md': {
    slug: 'cross-dialect-sql-without-hallucinations',
    category: 'Relational Data & SQL',
    date: '2026-09-04',
    author: 'GenSEAM',
    readTime: '8 min read',
    excerpt: 'Why agents writing raw SQL fail 28% of the time, and how homoiconic relational S-expressions lower deterministically to Postgres, SQLite, MySQL, and Oracle without injection risk.',
    tags: ['Cross-Dialect SQL', 'Relational Algebra', 'SQL Injection Eradication', 'Multi-Engine']
  },
  '13-git-native-agent-memory-and-vector-recall.md': {
    slug: 'git-native-agent-memory-and-vector-recall',
    category: 'Memory & Vector Systems',
    date: '2026-09-04',
    author: 'GenSEAM',
    readTime: '7 min read',
    excerpt: 'Sub-0.05ms in-memory vector recall and Git-native memory matrices: eliminating 500x cloud vector DB latency and ensuring agent episodic state never drifts from repository commits.',
    tags: ['Agent Memory', 'Vector Recall', 'Git-Native', 'In-Memory Wasm', 'Zero-Network']
  }
};

const posts = files.map(filename => {
  const fullPath = path.join(blogDir, filename);
  const rawContent = fs.readFileSync(fullPath, 'utf8');
  
  // Extract title from first # Header
  const titleMatch = rawContent.match(/^#\s+(.+)$/m);
  const title = titleMatch ? titleMatch[1].trim() : filename.replace(/\.md$/, '');
  
  const meta = metadataMap[filename] || {
    slug: filename.replace(/^\d+-/, '').replace(/\.md$/, ''),
    category: 'Engineering',
    date: '2026-09-04',
    author: 'ASL Engineering Team',
    readTime: '5 min read',
    excerpt: 'Technical insights from the AgentScript compiler and runtime team.',
    tags: ['AgentScript', 'Engineering']
  };

  const order = parseInt(filename.split('-')[0], 10) || 0;

  return {
    ...meta,
    order,
    title,
    content: rawContent
  };
});

// Sort posts descending (newest first by date and order)
posts.sort((a, b) => {
  const dateDiff = new Date(b.date).getTime() - new Date(a.date).getTime();
  if (dateDiff !== 0) return dateDiff;
  return (b.order || 0) - (a.order || 0);
});

const tsContent = `// Generated automatically by scripts/sync-blog.mjs - DO NOT EDIT DIRECTLY
export interface BlogPost {
  slug: string;
  title: string;
  date: string;
  author: string;
  category: string;
  readTime: string;
  excerpt: string;
  tags: string[];
  order?: number;
  content: string;
}

export const BLOG_POSTS: BlogPost[] = ${JSON.stringify(posts, null, 2)};

export const getBlogPostBySlug = (slug: string): BlogPost | undefined => {
  return BLOG_POSTS.find(p => p.slug === slug);
};

export const getFeaturedBlogPosts = (limit: number = 4): BlogPost[] => {
  return BLOG_POSTS.slice(0, limit);
};
`;

fs.writeFileSync(path.join(outDir, 'posts.ts'), tsContent, 'utf8');
console.log(`Successfully synced ${posts.length} blog posts into web/src/data/blog/posts.ts`);

// Generate RSS 2.0 Feed
const buildRssDate = (dateStr) => {
  const d = new Date(dateStr);
  return d.toUTCString();
};

const escapeXml = (unsafe) => {
  return unsafe.replace(/[<>&'"]/g, (c) => {
    switch (c) {
      case '<': return '&lt;';
      case '>': return '&gt;';
      case '&': return '&amp;';
      case '\'': return '&apos;';
      case '"': return '&quot;';
    }
  });
};

const rssItemsXml = posts.map(post => `    <item>
      <title>${escapeXml(post.title)}</title>
      <link>https://aslang.dev/blog/${post.slug}</link>
      <guid isPermaLink="true">https://aslang.dev/blog/${post.slug}</guid>
      <pubDate>${buildRssDate(post.date)}</pubDate>
      <author>dev@aslang.dev (${escapeXml(post.author)})</author>
      <category>${escapeXml(post.category)}</category>
      <description>${escapeXml(post.excerpt)}</description>
    </item>`).join('\n');

const rssXml = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>AgentScript (ASL) — Engineering &amp; Systems Blog</title>
    <link>https://aslang.dev/blog</link>
    <description>Technical essays, architecture deep-dives, and compiler benchmarks for the AgentScript language and GenSEAM ecosystem.</description>
    <language>en-us</language>
    <lastBuildDate>${new Date().toUTCString()}</lastBuildDate>
    <atom:link href="https://aslang.dev/rss.xml" rel="self" type="application/rss+xml" />
${rssItemsXml}
  </channel>
</rss>
`;

const publicDir = path.join(rootDir, 'web/public');
fs.writeFileSync(path.join(publicDir, 'rss.xml'), rssXml, 'utf8');
console.log(`Generated RSS 2.0 feed with ${posts.length} items at web/public/rss.xml`);
