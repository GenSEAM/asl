import React, { useState } from 'react';
import { Package, Terminal, Check, Search, ExternalLink } from 'lucide-react';

interface SkillItem {
  id: string;
  name: string;
  pkg: string;
  category: string;
  description: string;
  author: string;
  tokenCost: number;
  platforms: string[];
  repo: string;
  isCore?: boolean;
}

export const SkillsMarketplace: React.FC = () => {
  const [selectedCategory, setSelectedCategory] = useState<string>('All');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [copiedId, setCopiedId] = useState<string | null>(null);

  const skills: SkillItem[] = [
    {
      id: 'asl-core',
      name: 'AgentScript Language Core',
      pkg: '@genseam/asl',
      category: 'Compiler & Spec',
      description: 'Authoritative ASL grammar specification, §9 semantic checker rules, standard library handbook, and zero-blocker self-healing engine.',
      author: 'GenSEAM Core',
      tokenCost: 2400,
      platforms: ['Claude Code', 'Cursor', 'Antigravity', 'Windsurf', 'OpenDevin'],
      repo: 'https://github.com/GenSEAM/asl',
      isCore: true
    },
    {
      id: 'asl-harness',
      name: 'Agent Harness Engine',
      pkg: '@genseam/harness',
      category: 'Orchestrator',
      description: 'Meta-Agent Harness for multi-tier intent classification, consultative ambiguity loops, and speculative task pool execution.',
      author: 'GenSEAM Core',
      tokenCost: 1850,
      platforms: ['Claude Code', 'Cursor', 'Antigravity'],
      repo: 'https://github.com/GenSEAM/harness',
      isCore: true
    },
    {
      id: 'asl-skills',
      name: 'Universal Agent Skills Hub',
      pkg: '@genseam/skills',
      category: 'Skills Hub',
      description: 'Zero-drift prompt skills and tool adapters distributed natively across AI developer coding harnesses.',
      author: 'GenSEAM Core',
      tokenCost: 1400,
      platforms: ['Claude Code', 'Cursor', 'Antigravity', 'Windsurf', 'OpenDevin'],
      repo: 'https://github.com/GenSEAM/skills',
      isCore: true
    },
    {
      id: 'asl-bus',
      name: 'Agent Socket & SSE Bus',
      pkg: '@genseam/agent-bus',
      category: 'Communication',
      description: 'Ultra-low latency in-memory Unix socket & SSE bus for warm subagent orchestration in <0.04ms.',
      author: 'GenSEAM Core',
      tokenCost: 1100,
      platforms: ['Claude Code', 'Antigravity', 'OpenDevin'],
      repo: 'https://github.com/GenSEAM/agent-bus',
      isCore: true
    },
    {
      id: 'asl-browser-ext',
      name: 'Companion Extension & Visual Lens',
      pkg: '@genseam/browser-plugin',
      category: 'Browser & DOM',
      description: 'Browser extension companion for visual context extraction, in-situ DOM actions, and direct daemon socket bridge.',
      author: 'GenSEAM Core',
      tokenCost: 1500,
      platforms: ['Chrome Extension', 'Edge', 'Brave', 'Firefox'],
      repo: 'https://github.com/GenSEAM/browser-plugin',
      isCore: true
    },
    {
      id: 'asl-in-browser-dev',
      name: 'In-Browser Dev & Hot-Reload IDE',
      pkg: '@genseam/in-browser-dev',
      category: 'Browser & DOM',
      description: 'Zero-server in-browser WebAssembly hot-reloading runtime, Web Worker threads, OPFS, and isomorphic-git integration.',
      author: 'GenSEAM Core',
      tokenCost: 1650,
      platforms: ['Web Sandbox', 'PWA', 'Chrome Extension'],
      repo: 'https://github.com/GenSEAM/in-browser-dev',
      isCore: true
    },
    {
      id: 'asl-search',
      name: 'SearXNG & Proxy Pool Scout',
      pkg: '@genseam/search',
      category: 'Search & RAG',
      description: 'Multi-engine decentralized search with proxy rotation, anti-bot bypass, and clean markdown RAG context compressor.',
      author: 'GenSEAM Core',
      tokenCost: 1200,
      platforms: ['Claude Code', 'Cursor', 'Antigravity', 'Windsurf'],
      repo: 'https://github.com/GenSEAM/search'
    },
    {
      id: 'asl-mem',
      name: 'Vector Memory & Semantic Recall',
      pkg: '@genseam/mem',
      category: 'Memory',
      description: 'Zero-server in-memory vector database and cosine similarity search in 64KB WebAssembly.',
      author: 'GenSEAM Core',
      tokenCost: 1100,
      platforms: ['Claude Code', 'Cursor', 'Antigravity'],
      repo: 'https://github.com/GenSEAM/mem'
    }
  ];

  const categories = ['All', 'Compiler & Spec', 'Orchestrator', 'Skills Hub', 'Communication', 'Browser & DOM', 'Search & RAG', 'Memory'];

  const filteredSkills = skills.filter(s => {
    const matchesCategory = selectedCategory === 'All' || s.category === selectedCategory;
    const matchesSearch = s.name.toLowerCase().includes(searchQuery.toLowerCase()) || 
                          s.description.toLowerCase().includes(searchQuery.toLowerCase()) ||
                          s.pkg.toLowerCase().includes(searchQuery.toLowerCase());
    return matchesCategory && matchesSearch;
  });

  const handleCopyInstall = (skill: SkillItem) => {
    const cmd = `asl skill install ${skill.pkg}`;
    navigator.clipboard.writeText(cmd);
    setCopiedId(skill.id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  return (
    <section id="skills" className="relative py-28 border-b border-craft-200/60 dark:border-white/[0.06] bg-white dark:bg-[#05070a] transition-colors">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Section Header */}
        <div className="max-w-3xl mx-auto text-center mb-12">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-cyan-500/10 border border-cyan-500/30 text-cyan-600 dark:text-cyan-400 text-xs font-mono mb-4">
            <Package className="w-3.5 h-3.5" />
            <span>Official Ecosystem Registry</span>
          </div>

          <h2 className="text-3xl sm:text-5xl font-extrabold tracking-[-0.04em] text-craft-900 dark:text-white font-sans leading-tight">
            Agent Skills & Packages.
          </h2>

          <p className="mt-4 text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans leading-relaxed tracking-[-0.01em]">
            Verified modular capabilities for autonomous agents. Distribute and install across <strong>Claude Code</strong>, <strong>Cursor</strong>, <strong>Antigravity</strong>, and <strong>Windsurf</strong> with one command.
          </p>
        </div>

        {/* Floating Capsule Category Filter & Search matching Header design */}
        <div className="flex flex-col md:flex-row items-center justify-between gap-4 mb-12 max-w-5xl mx-auto">
          
          {/* Capsule Filter Pills */}
          <div className="p-1.5 rounded-full border border-craft-200 dark:border-white/[0.1] bg-craft-100/80 dark:bg-white/[0.03] backdrop-blur-2xl flex flex-wrap gap-1 shadow-lg max-w-full overflow-x-auto">
            {categories.slice(0, 5).map((cat) => (
              <button
                key={cat}
                onClick={() => setSelectedCategory(cat)}
                className={`px-4 py-1.5 rounded-full text-xs font-mono transition-all ${
                  selectedCategory === cat
                    ? 'bg-craft-accent text-craft-950 font-bold shadow-[0_0_12px_rgba(6,182,212,0.35)]'
                    : 'text-craft-600 dark:text-craft-400 hover:text-craft-900 dark:hover:text-white'
                }`}
              >
                {cat}
              </button>
            ))}
          </div>

          {/* Floating Pill Search Bar */}
          <div className="relative w-full md:w-72">
            <Search className="w-4 h-4 text-craft-400 absolute left-3.5 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              placeholder="Search packages..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-9 pr-4 py-2 rounded-full border border-craft-200 dark:border-white/[0.1] bg-craft-100/80 dark:bg-white/[0.03] backdrop-blur-2xl text-xs font-mono text-craft-900 dark:text-white placeholder-craft-400 focus:outline-none focus:border-craft-accent transition-all shadow-sm"
            />
          </div>

        </div>

        {/* Package Grid with Frosted Glass Styling */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 text-left">
          {filteredSkills.map((skill) => (
            <div
              key={skill.id}
              className="p-7 rounded-[2rem] border border-craft-200 dark:border-white/[0.08] bg-white/70 dark:bg-white/[0.02] backdrop-blur-2xl hover:border-craft-accent/50 hover:shadow-[0_0_30px_rgba(6,182,212,0.12)] transition-all flex flex-col justify-between group"
            >
              <div>
                {/* Header Badge */}
                <div className="flex items-center justify-between gap-2 mb-4">
                  <span className="px-3 py-1 rounded-full text-[10px] font-mono font-bold uppercase tracking-wider bg-cyan-500/10 text-craft-accent border border-cyan-500/30">
                    {skill.category}
                  </span>
                  <span className="text-[11px] font-mono text-craft-400 font-semibold">
                    ~{skill.tokenCost} tokens
                  </span>
                </div>

                <h3 className="text-xl font-bold text-craft-900 dark:text-white font-sans tracking-tight mb-1 group-hover:text-craft-accent transition-colors">
                  {skill.name}
                </h3>
                
                <div className="text-xs font-mono text-craft-500 dark:text-craft-400 mb-3">
                  {skill.pkg}
                </div>

                <p className="text-xs sm:text-sm text-craft-600 dark:text-craft-300 font-sans leading-relaxed mb-6">
                  {skill.description}
                </p>
              </div>

              <div>
                {/* Platform Support Tags */}
                <div className="flex flex-wrap gap-1.5 mb-5">
                  {skill.platforms.map((p) => (
                    <span
                      key={p}
                      className="px-2 py-0.5 rounded-md text-[9px] font-mono bg-craft-100 dark:bg-white/[0.04] border border-craft-200 dark:border-white/[0.06] text-craft-600 dark:text-craft-400"
                    >
                      {p}
                    </span>
                  ))}
                </div>

                {/* 1-Click Install Bar */}
                <div className="pt-4 border-t border-craft-200 dark:border-white/[0.06] flex items-center justify-between gap-2">
                  <a
                    href={skill.repo}
                    target="_blank"
                    rel="noreferrer"
                    className="p-2 rounded-xl text-craft-400 hover:text-craft-900 dark:hover:text-white hover:bg-craft-100 dark:hover:bg-white/[0.06] transition-colors"
                    title="View Source on GitHub"
                  >
                    <ExternalLink className="w-4 h-4" />
                  </a>

                  <button
                    onClick={() => handleCopyInstall(skill)}
                    className="flex-1 py-2 px-3 rounded-xl bg-craft-100 dark:bg-white/[0.04] border border-craft-200 dark:border-white/[0.1] hover:border-craft-accent hover:bg-craft-accent/10 text-craft-900 dark:text-craft-100 font-mono text-xs font-semibold flex items-center justify-center gap-1.5 transition-all"
                  >
                    {copiedId === skill.id ? (
                      <>
                        <Check className="w-3.5 h-3.5 text-emerald-500" />
                        <span className="text-emerald-500 font-bold">Copied command!</span>
                      </>
                    ) : (
                      <>
                        <Terminal className="w-3.5 h-3.5 text-craft-accent" />
                        <span>asl skill install {skill.pkg}</span>
                      </>
                    )}
                  </button>
                </div>
              </div>

            </div>
          ))}
        </div>

      </div>
    </section>
  );
};
