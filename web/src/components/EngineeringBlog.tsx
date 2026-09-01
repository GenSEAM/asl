import React, { useState } from 'react';
import { BookOpen, ChevronDown, ChevronUp } from 'lucide-react';

interface Article {
  id: string;
  title: string;
  category: string;
  readTime: string;
  date: string;
  summary: string;
  highlights: string[];
  deepDive: string;
  tags: string[];
}

export const EngineeringBlog: React.FC = () => {
  const [selectedArticle, setSelectedArticle] = useState<string | null>(null);
  const [selectedCategory, setSelectedCategory] = useState<string>('All');

  const articles: Article[] = [
    {
      id: 'death-of-syntax-hallucinations',
      title: 'The Death of Syntax Hallucinations: Why S-Expressions Beat Python & Rust for AI Agents',
      category: 'Language Design',
      readTime: '6 min read',
      date: '2026-09-01',
      summary: 'Why generating complex indentation or borrow-checked syntax causes 4–8 LLM repair loops, and how ASL single-pass LL(1) grammar guarantees 0 syntax crashes with –78% token savings.',
      highlights: [
        'Single-pass LL(1) balanced parenthesis guarantees structural integrity',
        'Tail-expression derivation precedes result, eliminating prompt reasoning friction',
        '107 closed safe builtins verified across 6 execution targets with zero drift'
      ],
      deepDive: `Traditional programming languages were designed for human typing ergonomics, not tokenized probability distributions. When LLMs generate Python, invisible indentation mismatches cause catastrophic syntax crashes. When LLMs generate Rust, borrow checker edge cases require multi-turn repair loops that explode context windows.

ASL (AgentScript) was created from first principles as an S-expression substrate:
1. Deterministic Structural Boundaries: Parentheses are unambiguous token boundaries.
2. Interface Compression: Module headers with :export lists compress type interfaces by 78%, allowing LLMs to import large libraries without context starvation.
3. Universal Transpilation: A single verified ASL module transpiles byte-for-byte to Rust, WebAssembly, TypeScript, Go, and Python without semantic divergence.`,
      tags: ['LL(1) Grammar', 'Token Efficiency', 'WASI']
    },
    {
      id: 'multilayer-observability',
      title: 'Multilayer Observability: How Humans Govern Autonomous Swarms Without Reading Code',
      category: 'Architecture & UX',
      readTime: '8 min read',
      date: '2026-08-28',
      summary: 'Humans cannot read 50,000 lines of generated code per day. We present a 4-layer cognitive zoom system from high-level Strategic Constitution down to physical WASI traces.',
      highlights: [
        'Layer 1 (Strategic): Invariant safety constitution and ethical boundaries',
        'Layer 2 (Tactical): Live swarm topology and inter-agent message buses',
        'Layer 3 (Operational): Version-controlled Git-native memory (.asl/mem/)',
        'Layer 4 (Physical): Sub-millisecond WASI heap isolates and execution timers'
      ],
      deepDive: `As autonomous agent velocity increases, human code review becomes the single largest bottleneck. The solution is not better code review tools—it is moving human cognition up the abstraction stack.

Our 4-layer zoom framework enables architects to:
- Inspect System Health in <50ms through visual topologies.
- Verify Invariants Mathematically: 7/7 automated verification gates prove correctness before code touches production.
- Drill Down Situational: Seamlessly expand a single failing subagent module to inspect its memory heap without wading through thousands of lines of working code.`,
      tags: ['Observability', 'Cognitive Ergonomics', 'Swarm UI']
    },
    {
      id: 'beyond-mcp-wire-protocol',
      title: 'Beyond MCP: Sub-Millisecond A2A Wire Protocols & In-Memory Socket Meshes',
      category: 'Protocols',
      readTime: '5 min read',
      date: '2026-08-22',
      summary: 'Why verbose JSON-RPC over stdio drains agent context, and how typed S-expression wire frames reduce latency to <0.04ms with zero attention drift.',
      highlights: [
        '3-cycle discovery handshake: (?agent/probe) -> (!agent/ack) -> typed execution',
        '–88% token context savings compared to natural language agent chats',
        'Zero attention loss: Deterministic framing prevents prompt dilution'
      ],
      deepDive: `While Model Context Protocol (MCP) standardized tool connectivity, agent-to-agent (A2A) collaboration requires ultra-dense, high-frequency signaling. Natural language agent chatter ("Hello! Could you please format this...") wastes up to 375 tokens per turn with 1,400ms latency.

The AgP Wire Protocol introduces nano S-expression frames over Unix Domain Sockets and SSE:
- Handshake in 1 network cycle.
- Typed query and response executed in <0.015ms.
- 100% deterministic type safety with zero ambiguity.`,
      tags: ['A2A Protocol', 'High-Frequency IPC', 'Socket Mesh']
    },
    {
      id: 'git-native-agent-memory',
      title: 'Git-Native Agent Memory: Why Vector Databases Belong in Version Control',
      category: 'Memory & State',
      readTime: '7 min read',
      date: '2026-08-15',
      summary: 'Why external black-box vector stores fail in production, and how .asl/mem/ provides version-controlled ADRs with 64KB WebAssembly vector recall.',
      highlights: [
        'Version-controlled memory records committed alongside code',
        'Zero-server vector search executed locally in 64KB WebAssembly',
        'Full auditability: Roll back agent memory to any historical commit'
      ],
      deepDive: `External vector databases detach agent memory from the codebase lifecycle. When code changes, disconnected vector embeddings hallucinate outdated architectural decisions.

ASL embeds hierarchical memory directly in Git (.asl/mem/):
- Architectural Decision Records (ADRs) and requirements are first-class versioned files.
- In-memory WASI cosine similarity recall runs in <0.04ms with zero external servers.
- Branching a repository automatically branches the agent's memory and knowledge base.`,
      tags: ['Git Memory', 'Wasm Vectors', 'ADR Architecture']
    }
  ];

  const categories = ['All', 'Language Design', 'Architecture & UX', 'Protocols', 'Memory & State'];

  const filteredArticles = articles.filter(a => selectedCategory === 'All' || a.category === selectedCategory);

  return (
    <section id="insights" className="relative py-28 border-b border-craft-200/80 dark:border-white/[0.08] bg-white dark:bg-[#07090e] overflow-hidden transition-colors">
      
      {/* Ambient background depth */}
      <div className="absolute inset-0 z-0 pointer-events-none opacity-10">
        <img src="/assets/images/ambient_bg.jpg" alt="" className="w-full h-full object-cover" />
      </div>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Section Header */}
        <div className="max-w-3xl mx-auto text-center mb-12">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-cyan-500/10 border border-cyan-500/30 text-cyan-600 dark:text-cyan-400 text-xs font-mono mb-4">
            <BookOpen className="w-3.5 h-3.5" />
            <span>Architecture Insights & Engineering Essays</span>
          </div>

          <h2 className="text-3xl sm:text-5xl font-extrabold tracking-[-0.04em] text-craft-900 dark:text-white font-sans leading-tight">
            Next-Gen Architecture Hub.
          </h2>

          <p className="mt-4 text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans leading-relaxed tracking-[-0.01em]">
            Deep-dive technical essays on solving LLM hallucination loops, multilayer observability, high-frequency A2A wire protocols, and Git-native agent memory.
          </p>
        </div>

        {/* Category Pills */}
        <div className="flex justify-center mb-10 overflow-x-auto">
          <div className="p-1.5 rounded-full border border-craft-200 dark:border-white/[0.1] bg-craft-100/80 dark:bg-white/[0.03] backdrop-blur-2xl flex gap-1 shadow-lg font-mono text-xs max-w-full">
            {categories.map(c => (
              <button
                key={c}
                onClick={() => setSelectedCategory(c)}
                className={`px-4 py-2 rounded-full transition-all whitespace-nowrap ${
                  selectedCategory === c
                    ? 'bg-craft-accent text-craft-950 font-bold shadow-[0_0_12px_rgba(6,182,212,0.35)]'
                    : 'text-craft-600 dark:text-craft-400 hover:text-craft-900 dark:hover:text-white'
                }`}
              >
                {c}
              </button>
            ))}
          </div>
        </div>

        {/* Articles Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 text-left">
          {filteredArticles.map((article) => {
            const isExpanded = selectedArticle === article.id;

            return (
              <article
                key={article.id}
                className={`rounded-[2rem] border transition-all duration-300 backdrop-blur-xl p-6 sm:p-8 flex flex-col justify-between ${
                  isExpanded
                    ? 'border-cyan-500/50 bg-craft-50 dark:bg-[#090c14] shadow-2xl md:col-span-2'
                    : 'border-craft-200 dark:border-white/[0.08] bg-white/70 dark:bg-white/[0.02] hover:border-craft-300 dark:hover:border-white/[0.15] shadow-lg'
                }`}
              >
                <div>
                  {/* Metadata Header */}
                  <div className="flex items-center justify-between gap-2 mb-4 font-mono text-xs text-craft-400">
                    <span className="px-3 py-1 rounded-full bg-cyan-500/10 text-cyan-600 dark:text-cyan-400 font-bold border border-cyan-500/20">
                      {article.category}
                    </span>
                    <div className="flex items-center gap-3">
                      <span>{article.readTime}</span>
                      <span>•</span>
                      <span>{article.date}</span>
                    </div>
                  </div>

                  {/* Title */}
                  <h3 className="text-xl sm:text-2xl font-bold text-craft-900 dark:text-white font-sans tracking-tight mb-3 leading-snug">
                    {article.title}
                  </h3>

                  {/* Summary */}
                  <p className="text-sm text-craft-600 dark:text-craft-300 font-sans leading-relaxed mb-5">
                    {article.summary}
                  </p>

                  {/* Bullet Highlights */}
                  <ul className="space-y-2 mb-6 text-xs font-sans text-craft-700 dark:text-craft-200 border-l-2 border-cyan-500/40 pl-4">
                    {article.highlights.map((h, i) => (
                      <li key={i} className="leading-relaxed">
                        &rarr; {h}
                      </li>
                    ))}
                  </ul>

                  {/* Deep Dive Expanded Section */}
                  {isExpanded && (
                    <div className="pt-6 border-t border-craft-200 dark:border-white/[0.08] text-sm text-craft-700 dark:text-craft-200 font-sans leading-relaxed whitespace-pre-line space-y-4 animate-fadeIn">
                      <div className="font-mono text-xs font-bold text-cyan-400 uppercase tracking-wider">
                        // FULL ARCHITECTURAL ESSAY
                      </div>
                      {article.deepDive}
                    </div>
                  )}
                </div>

                {/* Footer Action & Tags */}
                <div className="pt-6 border-t border-craft-200 dark:border-white/[0.06] flex flex-wrap items-center justify-between gap-3 mt-4">
                  <div className="flex flex-wrap gap-1.5 font-mono text-[10px]">
                    {article.tags.map(t => (
                      <span key={t} className="px-2.5 py-0.5 rounded-md bg-craft-100 dark:bg-white/[0.04] text-craft-500 dark:text-craft-400 border border-craft-200 dark:border-white/[0.06]">
                        #{t}
                      </span>
                    ))}
                  </div>

                  <button
                    onClick={() => setSelectedArticle(isExpanded ? null : article.id)}
                    className="inline-flex items-center gap-1.5 text-xs font-mono font-bold text-cyan-600 dark:text-cyan-400 hover:underline"
                  >
                    <span>{isExpanded ? 'Collapse Essay' : 'Read Full Essay'}</span>
                    {isExpanded ? <ChevronUp className="w-3.5 h-3.5" /> : <ChevronDown className="w-3.5 h-3.5" />}
                  </button>
                </div>

              </article>
            );
          })}
        </div>

      </div>
    </section>
  );
};
