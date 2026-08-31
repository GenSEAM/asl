import React, { useState } from 'react';
import { Newspaper, ArrowRight, Zap, Target, Clock } from 'lucide-react';

interface Article {
  id: string;
  title: string;
  category: string;
  readTime: string;
  date: string;
  summary: string;
  keyTakeaway: string;
  content: string[];
}

export const Blog: React.FC = () => {
  const [selectedArticleId, setSelectedArticleId] = useState('article-1');

  const ARTICLES: Article[] = [
    {
      id: 'article-1',
      title: 'Why LLMs Fail at Python & Rust: The Case for Single-Pass S-Expressions',
      category: 'Language Design',
      readTime: '4 min read',
      date: 'Sept 2026',
      summary: 'Why autoregressive models waste 40% of their reasoning budget on Python indentation and Rust lifetime errors, and how ASL achieves 99.4% first-run accuracy.',
      keyTakeaway: 'S-expressions eliminate non-local syntax backtracking, enabling models to generate verified ASTs in a single forward pass.',
      content: [
        'Modern languages were designed for human fingers and visual indentation. In the era of autonomous AI coding agents, legacy syntax introduces massive tax.',
        'Python colons and whitespace create invisible syntax traps for tokenizers. Rust borrow-checker errors require global lifetime backtracking that LLMs struggle to reason about.',
        'ASL uses strict single-pass S-expressions, exhaustive sum types (defenum + match), and explicit effect markers (!). Missing cases and runtime nulls are eliminated by design.'
      ]
    },
    {
      id: 'article-2',
      title: 'The 78% Token Tax: How Interface Compression Solves Agent Context Rot',
      category: 'Agent Architecture',
      readTime: '3 min read',
      date: 'Sept 2026',
      summary: 'Passing entire codebases to LLMs exhausts context windows and causes hallucinations. Interface compression keeps agents focused and reduces costs by 75%.',
      keyTakeaway: 'The asex_compress_module tool strips implementation bodies while preserving full type contracts, expanding effective working memory by 4.5x.',
      content: [
        'Multi-agent systems quickly hit context limits when multiple agents exchange full source files. The result is context rot, variable name confusion, and high API spend.',
        'ASL provides structural separation between interface definitions (defschema, defenum, defun signatures) and function bodies.',
        'The MCP tool asex_compress_module extracts verified contracts in 82 tokens instead of 390 tokens, allowing agents to understand large codebases in minimal context.'
      ]
    },
    {
      id: 'article-3',
      title: 'From Vibe-Code to WebAssembly in 0.04ms: The Future of Agentic Software',
      category: 'Ecosystem & Wasm',
      readTime: '5 min read',
      date: 'Sept 2026',
      summary: 'How in-memory WASI preview1 sandboxing replaces slow Docker containers and enables zero-drift deployment to React, Rust, Go, and Python.',
      keyTakeaway: 'WebAssembly provides instant <0.04ms execution in browser memory with 64KB page isolation, deployed to any cloud target with zero rewrite.',
      content: [
        'Vibe-coding requires instant feedback. Spinning up Docker containers introduces 300–800ms of lag that breaks the interactive flow.',
        'ASL compiles directly to native WebAssembly (wasm32-wasip1), executing in pure browser memory in 0.038ms with total memory safety.',
        'Once verified in the sandbox, the exact same ASL module transpiles seamlessly to React/TypeScript, high-throughput Rust, cloud Go, and Python pipelines.'
      ]
    }
  ];

  const selected = ARTICLES.find((a) => a.id === selectedArticleId) || ARTICLES[0];

  return (
    <section id="blog" className="py-16 border-b border-craft-800 bg-craft-950 font-mono">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="max-w-3xl mb-10">
          <div className="inline-flex items-center gap-2 px-2.5 py-1 rounded bg-craft-900 border border-craft-700 text-xs text-craft-accent mb-3">
            <Newspaper className="w-3.5 h-3.5" />
            <span>Research & Deep Dives</span>
          </div>
          <h2 className="text-3xl font-bold text-craft-50 tracking-tight">
            The Agentic Engineering Journal
          </h2>
          <p className="text-sm text-craft-400 mt-1 font-sans">
            In-depth analysis of language design, token economics, and why ASL is the foundation for next-generation AI development.
          </p>
        </div>

        {/* Blog Layout */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
          {/* Article List */}
          <div className="lg:col-span-5 space-y-3">
            {ARTICLES.map((article) => {
              const isSelected = selectedArticleId === article.id;
              return (
                <button
                  key={article.id}
                  onClick={() => setSelectedArticleId(article.id)}
                  className={`w-full p-4 rounded-xl border text-left transition-all ${
                    isSelected
                      ? 'bg-craft-900 border-craft-accent shadow-lg shadow-craft-accent/5'
                      : 'bg-craft-900/30 border-craft-800 hover:border-craft-700'
                  }`}
                >
                  <div className="flex items-center justify-between text-[11px] text-craft-500 mb-1.5">
                    <span className="text-craft-accent font-semibold">{article.category}</span>
                    <span className="flex items-center gap-1">
                      <Clock className="w-3 h-3" />
                      {article.readTime}
                    </span>
                  </div>
                  <h4 className={`text-sm font-bold leading-snug mb-2 ${isSelected ? 'text-craft-50' : 'text-craft-200'}`}>
                    {article.title}
                  </h4>
                  <p className="text-xs text-craft-400 font-sans line-clamp-2 leading-relaxed">
                    {article.summary}
                  </p>
                </button>
              );
            })}
          </div>

          {/* Active Article Full View */}
          <div className="lg:col-span-7">
            <div className="p-6 sm:p-8 rounded-xl border border-craft-800 bg-craft-900/50 shadow-2xl space-y-6">
              <div>
                <div className="flex items-center gap-3 text-xs text-craft-500 mb-2">
                  <span className="px-2 py-0.5 rounded bg-craft-800 text-craft-accent font-semibold">{selected.category}</span>
                  <span>{selected.date}</span>
                  <span>•</span>
                  <span>{selected.readTime}</span>
                </div>
                <h3 className="text-xl sm:text-2xl font-bold text-craft-50 tracking-tight leading-snug">
                  {selected.title}
                </h3>
              </div>

              {/* Key Takeaway Callout */}
              <div className="p-4 rounded-lg border border-craft-accent/30 bg-craft-950/80 flex items-start gap-3">
                <Zap className="w-4 h-4 text-craft-accent shrink-0 mt-0.5" />
                <div>
                  <span className="text-[11px] font-bold text-craft-accent uppercase tracking-wider block mb-0.5">Key Architectural Insight</span>
                  <p className="text-xs text-craft-200 font-sans leading-relaxed">
                    {selected.keyTakeaway}
                  </p>
                </div>
              </div>

              {/* Body Content */}
              <div className="space-y-3 text-xs text-craft-300 font-sans leading-relaxed">
                {selected.content.map((paragraph, i) => (
                  <p key={i}>{paragraph}</p>
                ))}
              </div>

              {/* Niche Solution Highlight */}
              <div className="pt-4 border-t border-craft-800 flex items-center justify-between text-xs text-craft-400 font-mono">
                <span className="flex items-center gap-1.5 text-craft-emerald">
                  <Target className="w-3.5 h-3.5" />
                  <span>Problem Solved in ASL v1.0</span>
                </span>
                <a
                  href="#playground"
                  className="text-craft-accent hover:underline flex items-center gap-1"
                >
                  <span>Test in Sandbox</span>
                  <ArrowRight className="w-3.5 h-3.5" />
                </a>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
