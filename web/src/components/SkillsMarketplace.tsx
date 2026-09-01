import React, { useState } from 'react';
import { Package, Download, Terminal, Check } from 'lucide-react';

interface SkillItem {
  id: string;
  name: string;
  category: string;
  description: string;
  author: string;
  downloads: number;
  tokenCost: number;
  platforms: string[];
  repo: string;
}

export const SkillsMarketplace: React.FC = () => {
  const [selectedCategory, setSelectedCategory] = useState<string>('All');
  const [copiedId, setCopiedId] = useState<string | null>(null);

  const skills: SkillItem[] = [
    {
      id: 'asl-core',
      name: 'AgentScript Language Core',
      category: 'Code & Wasm',
      description: 'Authoritative ASL grammar specification, §9 semantic checker rules, standard library handbook, and zero-blocker self-healing engine.',
      author: 'GenSEAM Core',
      downloads: 4820,
      tokenCost: 2400,
      platforms: ['Claude Code', 'Cursor', 'Antigravity', 'Windsurf', 'OpenDevin'],
      repo: 'https://github.com/GenSEAM/asl'
    },
    {
      id: 'asl-eddie',
      name: 'EDDIE Swarm Orchestrator',
      category: 'Orchestrator',
      description: '3-layer intent classification, consultative ambiguity resolver, follow-up loop, and speculative task pool DAG.',
      author: 'GenSEAM Core',
      downloads: 2910,
      tokenCost: 1850,
      platforms: ['Claude Code', 'Cursor', 'Antigravity'],
      repo: 'https://github.com/GenSEAM/eddie'
    },
    {
      id: 'asl-browser',
      name: 'Browser DOM & WASI Agent',
      category: 'Browser',
      description: 'Intelligent DOM tree compression (-78% tokens), simulated click/fill actions, and in-memory WebAssembly action execution.',
      author: 'GenSEAM Core',
      downloads: 3410,
      tokenCost: 1600,
      platforms: ['Claude Code', 'Antigravity', 'OpenDevin'],
      repo: 'https://github.com/GenSEAM/browser-plugin'
    },
    {
      id: 'asl-search',
      name: 'SearXNG & Proxy Pool Scout',
      category: 'Research',
      description: 'Multi-engine decentralized search with proxy rotation, anti-bot bypass, and clean markdown RAG context compressor.',
      author: 'GenSEAM Core',
      downloads: 2150,
      tokenCost: 1200,
      platforms: ['Claude Code', 'Cursor', 'Antigravity', 'Windsurf'],
      repo: 'https://github.com/GenSEAM/search'
    },
    {
      id: 'asl-mem',
      name: 'Vector Memory & Semantic Recall',
      category: 'Memory',
      description: 'Zero-server in-memory vector database and cosine similarity search in 64KB WebAssembly.',
      author: 'GenSEAM Core',
      downloads: 1940,
      tokenCost: 1100,
      platforms: ['Claude Code', 'Cursor', 'Antigravity'],
      repo: 'https://github.com/GenSEAM/mem'
    }
  ];

  const categories = ['All', 'Code & Wasm', 'Orchestrator', 'Browser', 'Research', 'Memory'];

  const filteredSkills = selectedCategory === 'All'
    ? skills
    : skills.filter(s => s.category === selectedCategory);

  const copyInstall = (id: string) => {
    navigator.clipboard.writeText(`asl skill install ${id}`);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  return (
    <div className="border-t border-[#1e2230] bg-[#080a10] py-20 px-6 sm:px-10">
      <div className="max-w-6xl mx-auto">
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-12 gap-6">
          <div>
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-cyan-500/10 border border-cyan-500/30 text-cyan-400 text-xs font-mono mb-3">
              <Package className="w-3.5 h-3.5" />
              Universal Agent Skills Hub
            </div>
            <h2 className="text-3xl sm:text-4xl font-bold tracking-tight text-white">
              Agent Skills Marketplace
            </h2>
            <p className="text-[#94a3b8] mt-2 max-w-2xl text-sm sm:text-base">
              Distribute and install verified AgentScript capabilities across <strong>Claude Code</strong>, <strong>Cursor</strong>, <strong>Antigravity</strong>, <strong>Windsurf</strong>, and <strong>OpenDevin</strong> with one command.
            </p>
          </div>

          {/* Category Filter */}
          <div className="flex flex-wrap gap-2">
            {categories.map(cat => (
              <button
                key={cat}
                onClick={() => setSelectedCategory(cat)}
                className={`px-3 py-1.5 rounded-lg text-xs font-mono transition-all ${
                  selectedCategory === cat
                    ? 'bg-cyan-500 text-[#07090e] font-bold shadow-lg shadow-cyan-500/20'
                    : 'bg-[#101420] text-[#94a3b8] hover:text-white border border-[#1e2638]'
                }`}
              >
                {cat}
              </button>
            ))}
          </div>
        </div>

        {/* Skills Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {filteredSkills.map(skill => (
            <div
              key={skill.id}
              className="bg-[#0b0e18] border border-[#192134] hover:border-cyan-500/50 rounded-xl p-6 flex flex-col justify-between transition-all group shadow-xl"
            >
              <div>
                <div className="flex items-center justify-between mb-3">
                  <span className="text-[11px] font-mono text-cyan-400 bg-cyan-500/10 px-2 py-0.5 rounded border border-cyan-500/20">
                    {skill.category}
                  </span>
                  <span className="text-[11px] font-mono text-[#64748b] flex items-center gap-1">
                    <Download className="w-3 h-3" />
                    {skill.downloads.toLocaleString()}
                  </span>
                </div>

                <h3 className="text-lg font-bold text-white group-hover:text-cyan-300 transition-colors">
                  {skill.name}
                </h3>
                <p className="text-xs text-[#94a3b8] mt-2 leading-relaxed">
                  {skill.description}
                </p>

                {/* Target Platforms */}
                <div className="mt-4 pt-4 border-t border-[#151c2c]">
                  <div className="text-[10px] font-mono text-[#64748b] mb-1.5 uppercase tracking-wider">Harness Support:</div>
                  <div className="flex flex-wrap gap-1.5">
                    {skill.platforms.map(p => (
                      <span key={p} className="text-[10px] font-mono bg-[#111624] text-[#cbd5e1] px-2 py-0.5 rounded border border-[#1e283e]">
                        {p}
                      </span>
                    ))}
                  </div>
                </div>
              </div>

              {/* Install Bar */}
              <div className="mt-6 pt-4 border-t border-[#151c2c] flex items-center justify-between gap-3">
                <div className="font-mono text-[11px] text-[#64748b]">
                  ~{skill.tokenCost} tokens
                </div>
                <button
                  onClick={() => copyInstall(skill.id)}
                  className={`px-3 py-1.5 rounded-lg font-mono text-xs flex items-center gap-1.5 transition-all ${
                    copiedId === skill.id
                      ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/40'
                      : 'bg-[#141a29] hover:bg-[#1e273d] text-white border border-[#222c42]'
                  }`}
                >
                  {copiedId === skill.id ? (
                    <>
                      <Check className="w-3.5 h-3.5 text-emerald-400" />
                      Copied
                    </>
                  ) : (
                    <>
                      <Terminal className="w-3.5 h-3.5 text-cyan-400" />
                      $ asl skill install
                    </>
                  )}
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
