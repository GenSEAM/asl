import React, { useState } from 'react';
import { Package, Star, Terminal, ExternalLink, PlusCircle, Check, Copy, Puzzle, Search, Zap } from 'lucide-react';

interface PluginItem {
  name: string;
  repo: string;
  capability: string;
  description: string;
  author: string;
  stars: number;
  tags: string[];
}

const PLUGINS: PluginItem[] = [
  {
    name: "asl-github",
    repo: "github.com/GenSEAM/plugin-github",
    capability: "VCS & PRs",
    description: "Inspect repositories, read pull requests, and review diffs via zero-drift GitHub API.",
    author: "GenSEAM Core",
    stars: 142,
    tags: ["GitHub", "Git", "Code Review"]
  },
  {
    name: "asl-slack",
    repo: "github.com/GenSEAM/plugin-slack",
    capability: "Team Chat",
    description: "Autonomous message dispatch, channel listener, and thread summarization.",
    author: "community/alex",
    stars: 98,
    tags: ["Slack", "Messaging", "Notifications"]
  },
  {
    name: "asl-postgres",
    repo: "github.com/GenSEAM/plugin-postgres",
    capability: "Database",
    description: "Type-safe SQL query generation, schema inspection, and migration runner in Wasm.",
    author: "community/database-dao",
    stars: 215,
    tags: ["PostgreSQL", "SQL", "Database"]
  },
  {
    name: "asl-linear",
    repo: "github.com/GenSEAM/plugin-linear",
    capability: "Project Management",
    description: "Issue tracking, sprint planning, and automated roadmap synchronization.",
    author: "community/pm-tools",
    stars: 86,
    tags: ["Linear", "Roadmap", "Issues"]
  },
  {
    name: "asl-search",
    repo: "github.com/GenSEAM/search",
    capability: "Metasearch",
    description: "SearXNG metasearch aggregator with proxy rotation and -78% RAG context compression.",
    author: "GenSEAM Core",
    stars: 310,
    tags: ["SearXNG", "RAG", "Proxy Pool"]
  },
  {
    name: "asl-mem",
    repo: "github.com/GenSEAM/mem",
    capability: "Vector Memory",
    description: "Zero-server in-memory vector database and cosine similarity in 64KB WebAssembly.",
    author: "GenSEAM Core",
    stars: 280,
    tags: ["Vector DB", "Embeddings", "Wasm"]
  }
];

export const CommunityHub: React.FC = () => {
  const [filter, setFilter] = useState('');
  const [copiedRepo, setCopiedRepo] = useState<string | null>(null);

  const filteredPlugins = PLUGINS.filter(p =>
    p.name.toLowerCase().includes(filter.toLowerCase()) ||
    p.description.toLowerCase().includes(filter.toLowerCase()) ||
    p.capability.toLowerCase().includes(filter.toLowerCase()) ||
    p.tags.some(t => t.toLowerCase().includes(filter.toLowerCase()))
  );

  const copyCommand = (repo: string) => {
    navigator.clipboard.writeText(`asl get ${repo}`);
    setCopiedRepo(repo);
    setTimeout(() => setCopiedRepo(null), 2000);
  };

  return (
    <div className="border-t border-[#1e2230] bg-[#07080c] py-20 px-6 sm:px-10">
      <div className="max-w-6xl mx-auto">
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-12 gap-6">
          <div>
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-cyan-500/10 border border-cyan-500/30 text-cyan-400 text-xs font-mono mb-3">
              <Puzzle className="w-3.5 h-3.5" />
              Community Extensible Ecosystem
            </div>
            <h2 className="text-3xl sm:text-4xl font-bold tracking-tight text-white">
              Agent Plugins & Community Hub
            </h2>
            <p className="text-[#94a3b8] mt-2 max-w-2xl text-sm sm:text-base">
              Extend your autonomous agent in 1 command. Build, publish, and compose open-source tools with zero drift and zero boilerplate.
            </p>
          </div>

          <div className="flex flex-col sm:flex-row gap-3">
            <div className="relative">
              <Search className="w-4 h-4 text-[#64748b] absolute left-3 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                placeholder="Search community plugins..."
                value={filter}
                onChange={e => setFilter(e.target.value)}
                className="bg-[#0e111a] border border-[#1e2436] text-white pl-9 pr-4 py-2 rounded-lg text-sm focus:outline-none focus:border-cyan-500 w-full sm:w-64"
              />
            </div>
            <a
              href="https://github.com/GenSEAM"
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center justify-center gap-2 bg-gradient-to-r from-cyan-500 to-blue-600 hover:from-cyan-400 hover:to-blue-500 text-[#090a0f] font-semibold px-4 py-2 rounded-lg text-sm transition-all shadow-lg shadow-cyan-500/10"
            >
              <PlusCircle className="w-4 h-4" />
              Submit a Plugin
            </a>
          </div>
        </div>

        {/* Plugin Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {filteredPlugins.map(plugin => (
            <div
              key={plugin.name}
              className="bg-[#0b0d14] border border-[#1a1f2e] hover:border-cyan-500/40 rounded-xl p-6 transition-all group flex flex-col justify-between"
            >
              <div>
                <div className="flex items-start justify-between mb-3">
                  <div className="flex items-center gap-2.5">
                    <div className="w-9 h-9 rounded-lg bg-cyan-500/10 border border-cyan-500/20 flex items-center justify-center text-cyan-400">
                      <Package className="w-5 h-5" />
                    </div>
                    <div>
                      <h3 className="text-white font-semibold text-base group-hover:text-cyan-300 transition-colors">
                        {plugin.name}
                      </h3>
                      <span className="text-xs text-[#64748b] font-mono">by {plugin.author}</span>
                    </div>
                  </div>
                  <div className="flex items-center gap-1 text-xs text-[#94a3b8] font-mono bg-[#121622] px-2 py-1 rounded border border-[#1e2436]">
                    <Star className="w-3 h-3 text-yellow-400 fill-yellow-400" />
                    {plugin.stars}
                  </div>
                </div>

                <p className="text-[#94a3b8] text-xs leading-relaxed mb-4">
                  {plugin.description}
                </p>

                <div className="flex flex-wrap gap-1.5 mb-6">
                  {plugin.tags.map(t => (
                    <span key={t} className="text-[10px] font-mono bg-[#141824] text-[#7dd3fc] px-2 py-0.5 rounded border border-[#1e293b]">
                      {t}
                    </span>
                  ))}
                </div>
              </div>

              <div className="pt-4 border-t border-[#161a26] flex items-center justify-between gap-2">
                <code className="text-[11px] font-mono text-[#38bdf8] bg-[#07090e] px-2.5 py-1.5 rounded border border-[#1e2436] flex-1 truncate">
                  asl get {plugin.repo}
                </code>
                <button
                  onClick={() => copyCommand(plugin.repo)}
                  className="p-2 bg-[#141824] hover:bg-[#1f2638] text-white rounded-lg border border-[#242c40] transition-colors"
                  title="Copy install command"
                >
                  {copiedRepo === plugin.repo ? (
                    <Check className="w-3.5 h-3.5 text-green-400" />
                  ) : (
                    <Copy className="w-3.5 h-3.5 text-[#94a3b8]" />
                  )}
                </button>
              </div>
            </div>
          ))}
        </div>

        {/* How to Build a Plugin Callout */}
        <div className="mt-12 bg-gradient-to-r from-[#0d121f] to-[#0a0d16] border border-[#1e283d] rounded-xl p-8 flex flex-col md:flex-row items-center justify-between gap-6">
          <div className="flex items-start gap-4">
            <div className="w-12 h-12 rounded-xl bg-cyan-500/20 border border-cyan-500/30 flex items-center justify-center text-cyan-400 shrink-0">
              <Zap className="w-6 h-6" />
            </div>
            <div>
              <h4 className="text-white font-semibold text-lg">Create your own Agent Plugin in seconds</h4>
              <p className="text-[#94a3b8] text-xs sm:text-sm mt-1 max-w-xl">
                Run <code className="text-cyan-400 font-mono">asl plugin --create my-tool</code> to scaffold a ready-to-publish plugin with typed manifest, Wasm builds, and unit tests.
              </p>
            </div>
          </div>
          <a
            href="https://github.com/GenSEAM/asl"
            target="_blank"
            rel="noreferrer"
            className="whitespace-nowrap px-5 py-2.5 bg-[#161c2b] hover:bg-[#1f283d] text-cyan-300 font-mono text-xs rounded-lg border border-cyan-500/30 transition-colors flex items-center gap-2"
          >
            <Terminal className="w-4 h-4" />
            Read Plugin Guide
            <ExternalLink className="w-3 h-3 text-[#64748b]" />
          </a>
        </div>
      </div>
    </div>
  );
};
