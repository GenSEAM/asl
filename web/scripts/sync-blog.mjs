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
    author: 'ASL Engineering Team',
    readTime: '6 min read',
    excerpt: 'Why indentation and borrow-checked syntax cost LLMs 25% to 40% of their compute in repair loops, and what deterministic single-pass S-expressions solve.',
    tags: ['Grammars', 'LLM Autoregression', 'Syntax Repair Loop', 'S-Expressions']
  },
  '02-the-token-tax-and-interface-compression.md': {
    slug: 'the-token-tax-and-interface-compression',
    category: 'Context Architecture',
    date: '2026-09-02',
    author: 'ASL Systems Group',
    readTime: '5 min read',
    excerpt: 'How AST interface extraction slashes multi-agent token consumption by 78.2% and eliminates context rot across distributed agent handoffs.',
    tags: ['Context Rot', 'Token Compression', 'AST Extraction', 'Multi-Agent']
  },
  '03-from-vibe-code-to-wasm-in-0-04ms.md': {
    slug: 'from-vibe-code-to-wasm-in-0-04ms',
    category: 'Runtime & Execution',
    date: '2026-09-02',
    author: 'ASL Systems Group',
    readTime: '5 min read',
    excerpt: 'Replacing heavy Docker containers and microVMs with zero-overhead in-memory WebAssembly sandboxes running test suites in 0.038ms.',
    tags: ['WebAssembly', 'WASI', 'MicroVMs', 'Sub-millisecond Sandboxing']
  },
  '04-agent-script-the-optimal-agent-language.md': {
    slug: 'agent-script-the-optimal-agent-language',
    category: 'Language Theory',
    date: '2026-09-03',
    author: 'ASL Systems & Compiler Group',
    readTime: '8 min read',
    excerpt: 'Why S-expressions, homoiconic ASTs, exhaustive pattern matching, and explicit effect boundaries are mathematically optimal for autoregressive LLMs.',
    tags: ['Homoiconicity', 'Algebraic Types', 'Exhaustive Matching', 'Deterministic AST']
  },
  '05-token-economy-and-nano-projection.md': {
    slug: 'token-economy-and-nano-projection',
    category: 'Token Optimization',
    date: '2026-09-03',
    author: 'ASL Systems & Compiler Group',
    readTime: '8 min read',
    excerpt: 'The abbreviation fallacy under BPE tokenizers, why keyword shortening saves 0.00% tokens, and how tabular serialization cuts prompt overhead by 65%.',
    tags: ['Byte-Pair Encoding', 'Nano Projection', 'Tabular Serialization', 'Token Ceiling']
  },
  '06-inter-agent-protocols-and-wire-frames.md': {
    slug: 'inter-agent-protocols-and-wire-frames',
    category: 'Protocols & Mesh',
    date: '2026-09-04',
    author: 'ASL Systems & Compiler Group',
    readTime: '7 min read',
    excerpt: 'Beyond conversational mesh chaos: replacing natural language chatter with typed S-expression frames, SkyLoom mesh buses, and zero-drift handoffs.',
    tags: ['SkyLoom', 'AgP Wire Protocol', 'Typed Frames', 'Conversational Mesh']
  },
  '07-the-agent-native-developer-cockpit.md': {
    slug: 'the-agent-native-developer-cockpit',
    category: 'Developer Tooling',
    date: '2026-09-04',
    author: 'ASL Systems & Compiler Group',
    readTime: '9 min read',
    excerpt: 'The complete agent-native developer cockpit: sub-0.05ms LSP, AST structural clone linters, autonomous auto-fixers, and live visual observability.',
    tags: ['Language Server Protocol', 'AST Auto-Fixer', 'Observability', 'Sandboxing']
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

  return {
    ...meta,
    title,
    content: rawContent
  };
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
