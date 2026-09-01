import React, { useState } from 'react';
import { Eye, Network, Database, ShieldCheck, Terminal, CheckCircle2, Search } from 'lucide-react';

export const AgentObservabilityStudio: React.FC = () => {
  const [activeLayer, setActiveLayer] = useState<'strategic' | 'tactical' | 'operational' | 'physical'>('tactical');
  const [selectedNode, setSelectedNode] = useState<string>('asl-compiler');
  const memoryQuery = 'ADR: S-expression LL(1) single-pass parser decision';

  const nodes = [
    {
      id: 'human-intent',
      name: 'Human Intent & Constitution',
      type: 'Strategic Layer',
      status: 'Verified Invariants',
      latency: '0.00ms',
      memory: 'Git-Native (.asl/constitution.md)',
      desc: 'High-level goals, safety guardrails, and non-negotiable architectural boundaries.'
    },
    {
      id: 'swarm-planner',
      name: 'Agent Swarm Coordinator',
      type: 'Tactical Mesh',
      status: 'Live Topology',
      latency: '0.015ms',
      memory: 'SSE Socket Bus in Memory',
      desc: 'Supervises subagent decomposition, assigns specialist tasks, and prevents drift.'
    },
    {
      id: 'asl-compiler',
      name: 'ASL Single-Pass Engine',
      type: 'Language Substrate',
      status: '107 Safe Builtins',
      latency: '0.038ms',
      memory: '64KB WASI Heap',
      desc: 'Compiles S-expressions with deterministic typechecking and zero syntax repair loops.'
    },
    {
      id: 'git-memory',
      name: 'Git-Native Project Memory',
      type: 'Operational Memory',
      status: 'Synchronized',
      latency: '0.012ms',
      memory: '.asl/mem/ (Vector Recalled)',
      desc: 'Version-controlled specifications, ADR architectural records, and migration logs.'
    },
  ];

  const activeNodeData = nodes.find(n => n.id === selectedNode) || nodes[2];

  return (
    <section id="observability" className="relative py-28 border-b border-craft-200/80 dark:border-white/[0.08] bg-white dark:bg-[#06080d] overflow-hidden transition-colors">
      {/* Subtle Atmospheric Depth */}
      <div className="absolute inset-0 z-0 pointer-events-none opacity-15 dark:opacity-10">
        <img src="/assets/images/ambient_bg.jpg" alt="" className="w-full h-full object-cover" />
      </div>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Section Header */}
        <div className="max-w-3xl mx-auto text-center mb-12">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-cyan-500/10 border border-cyan-500/30 text-cyan-600 dark:text-cyan-400 text-xs font-mono mb-4">
            <Eye className="w-3.5 h-3.5" />
            <span>Full-Spectrum Agent Observability</span>
          </div>

          <h2 className="text-3xl sm:text-5xl font-extrabold tracking-[-0.04em] text-craft-900 dark:text-white font-sans leading-tight">
            High-Level Agent Cockpit.
          </h2>

          <p className="mt-4 text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans leading-relaxed tracking-[-0.01em]">
            Humans should not parse thousands of lines of generated code. Inspect agent topologies, version-controlled memory, and live execution bounds across 4 cognitive layers.
          </p>
        </div>

        {/* 4 Cognitive Layer Zoom Tabs */}
        <div className="flex justify-center mb-10 overflow-x-auto">
          <div className="p-1.5 rounded-full border border-craft-200 dark:border-white/[0.1] bg-craft-100/80 dark:bg-white/[0.03] backdrop-blur-2xl flex gap-1 shadow-lg font-mono text-xs max-w-full">
            <button
              onClick={() => setActiveLayer('strategic')}
              className={`px-4 py-2 rounded-full transition-all whitespace-nowrap ${
                activeLayer === 'strategic'
                  ? 'bg-craft-accent text-craft-950 font-bold shadow-[0_0_12px_rgba(6,182,212,0.35)]'
                  : 'text-craft-600 dark:text-craft-400 hover:text-craft-900 dark:hover:text-white'
              }`}
            >
              1. Strategic (Constitution)
            </button>
            <button
              onClick={() => setActiveLayer('tactical')}
              className={`px-4 py-2 rounded-full transition-all whitespace-nowrap ${
                activeLayer === 'tactical'
                  ? 'bg-craft-accent text-craft-950 font-bold shadow-[0_0_12px_rgba(6,182,212,0.35)]'
                  : 'text-craft-600 dark:text-craft-400 hover:text-craft-900 dark:hover:text-white'
              }`}
            >
              2. Tactical (Swarm Topology)
            </button>
            <button
              onClick={() => setActiveLayer('operational')}
              className={`px-4 py-2 rounded-full transition-all whitespace-nowrap ${
                activeLayer === 'operational'
                  ? 'bg-craft-accent text-craft-950 font-bold shadow-[0_0_12px_rgba(6,182,212,0.35)]'
                  : 'text-craft-600 dark:text-craft-400 hover:text-craft-900 dark:hover:text-white'
              }`}
            >
              3. Operational (Git Memory)
            </button>
            <button
              onClick={() => setActiveLayer('physical')}
              className={`px-4 py-2 rounded-full transition-all whitespace-nowrap ${
                activeLayer === 'physical'
                  ? 'bg-craft-accent text-craft-950 font-bold shadow-[0_0_12px_rgba(6,182,212,0.35)]'
                  : 'text-craft-600 dark:text-craft-400 hover:text-craft-900 dark:hover:text-white'
              }`}
            >
              4. Physical (WASI Isolate)
            </button>
          </div>
        </div>

        {/* Observatory Main Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 text-left">
          
          {/* Left Column: Interactive Component & Topology Matrix */}
          <div className="lg:col-span-7 space-y-4">
            <div className="p-6 sm:p-8 rounded-[2rem] border border-craft-200 dark:border-white/[0.08] bg-white/70 dark:bg-white/[0.02] backdrop-blur-2xl shadow-xl space-y-4">
              
              <div className="flex items-center justify-between border-b border-craft-200 dark:border-white/[0.08] pb-4">
                <div className="font-mono text-xs font-bold text-craft-900 dark:text-white flex items-center gap-2">
                  <Network className="w-4 h-4 text-cyan-400" />
                  <span>SWARM TOPOLOGY & MODULE DEPENDENCY MESH</span>
                </div>
                <span className="text-[10px] font-mono text-emerald-400 bg-emerald-500/10 px-2.5 py-0.5 rounded-full border border-emerald-500/20">
                  ALL INVARIANTS GREEN
                </span>
              </div>

              {/* Node List */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                {nodes.map((n) => (
                  <button
                    key={n.id}
                    onClick={() => setSelectedNode(n.id)}
                    className={`p-4 rounded-2xl border text-left transition-all font-mono ${
                      selectedNode === n.id
                        ? 'border-cyan-400 bg-cyan-500/10 shadow-sm'
                        : 'border-craft-200 dark:border-white/[0.06] bg-craft-50 dark:bg-[#090c12] hover:border-craft-400 dark:hover:border-white/[0.15]'
                    }`}
                  >
                    <div className="flex items-center justify-between text-[10px] text-craft-400 mb-1">
                      <span>{n.type}</span>
                      <span className="text-cyan-400">{n.latency}</span>
                    </div>
                    <div className="font-bold text-xs text-craft-900 dark:text-white truncate">
                      {n.name}
                    </div>
                    <div className="text-[10px] text-craft-500 dark:text-craft-400 mt-1 truncate">
                      {n.status}
                    </div>
                  </button>
                ))}
              </div>

              {/* CLI Command Launcher Bar */}
              <div className="pt-4 border-t border-craft-200 dark:border-white/[0.06] flex items-center justify-between gap-3 text-xs font-mono">
                <div className="flex items-center gap-2 text-craft-500 dark:text-craft-400">
                  <Terminal className="w-4 h-4 text-cyan-400" />
                  <span>Launch local visual cockpit:</span>
                </div>
                <code className="px-3 py-1.5 rounded-xl bg-craft-100 dark:bg-white/[0.04] border border-craft-200 dark:border-white/[0.08] text-cyan-400 font-bold select-all">
                  asl inspect
                </code>
              </div>

            </div>

            {/* Hierarchical Memory Matrix Card */}
            <div className="p-6 sm:p-8 rounded-[2rem] border border-craft-200 dark:border-white/[0.08] bg-white/70 dark:bg-white/[0.02] backdrop-blur-2xl shadow-xl space-y-4">
              <div className="flex items-center justify-between border-b border-craft-200 dark:border-white/[0.08] pb-4 font-mono text-xs">
                <div className="flex items-center gap-2 text-craft-900 dark:text-white font-bold">
                  <Database className="w-4 h-4 text-purple-400" />
                  <span>GIT-NATIVE MEMORY MATRIX (.asl/mem/)</span>
                </div>
                <span className="text-[10px] text-purple-400">ZERO-SERVER WASM VECTOR RECALL</span>
              </div>

              <div className="p-3.5 rounded-xl bg-craft-50 dark:bg-[#090c12] border border-craft-200 dark:border-white/[0.06] text-xs font-mono space-y-2">
                <div className="flex items-center gap-2 text-craft-500">
                  <Search className="w-3.5 h-3.5 text-cyan-400" />
                  <span className="text-craft-800 dark:text-craft-200 font-semibold">{memoryQuery}</span>
                </div>
                <div className="text-[11px] text-craft-400 pl-5 leading-relaxed font-sans">
                  &rarr; Matched: <code className="text-cyan-400 font-mono">.asl/mem/adr-007-single-pass.asl</code> (Cosine Similarity: <strong>0.942</strong>, Latency: <strong>0.012ms</strong>).
                </div>
              </div>
            </div>

          </div>

          {/* Right Column: Node Inspector & Safety / Quality Advisor */}
          <div className="lg:col-span-5 space-y-4">
            
            {/* Selected Node Detailed Inspector */}
            <div className="p-6 sm:p-8 rounded-[2rem] border border-cyan-500/40 bg-gradient-to-b from-white dark:from-white/[0.03] to-craft-50 dark:to-[#07090e] backdrop-blur-2xl shadow-xl space-y-4">
              
              <div className="flex items-center justify-between border-b border-craft-200 dark:border-white/[0.08] pb-4">
                <span className="px-2.5 py-0.5 rounded-full text-[10px] font-mono font-bold uppercase tracking-wider bg-cyan-500/10 text-cyan-400 border border-cyan-500/30">
                  {activeNodeData.type}
                </span>
                <span className="font-mono text-xs text-emerald-400 font-bold flex items-center gap-1">
                  <CheckCircle2 className="w-3.5 h-3.5" />
                  <span>100% SPEC VERIFIED</span>
                </span>
              </div>

              <div>
                <h3 className="text-xl font-bold text-craft-900 dark:text-white font-sans">
                  {activeNodeData.name}
                </h3>
                <p className="text-xs text-craft-600 dark:text-craft-300 font-sans leading-relaxed mt-1">
                  {activeNodeData.desc}
                </p>
              </div>

              {/* Node Telemetry Details */}
              <div className="p-4 rounded-xl bg-craft-50 dark:bg-[#090c12] border border-craft-200 dark:border-white/[0.06] space-y-2 font-mono text-xs">
                <div className="flex justify-between">
                  <span className="text-craft-400">Isolation Tier:</span>
                  <span className="text-craft-900 dark:text-white font-bold">{activeNodeData.status}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-craft-400">Storage / Mesh:</span>
                  <span className="text-cyan-400 font-bold truncate max-w-[180px]">{activeNodeData.memory}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-craft-400">IPC Dispatch Latency:</span>
                  <span className="text-emerald-400 font-bold">{activeNodeData.latency}</span>
                </div>
              </div>

            </div>

            {/* Architecture Health & Safety Advisor */}
            <div className="p-6 sm:p-8 rounded-[2rem] border border-craft-200 dark:border-white/[0.08] bg-white/70 dark:bg-white/[0.02] backdrop-blur-2xl shadow-xl space-y-4">
              
              <div className="flex items-center gap-2 text-xs font-mono font-bold text-craft-900 dark:text-white border-b border-craft-200 dark:border-white/[0.08] pb-4">
                <ShieldCheck className="w-4 h-4 text-emerald-400" />
                <span>ARCHITECTURAL ADVISORY & SAFETY GATES</span>
              </div>

              <ul className="space-y-2.5 text-xs font-sans text-craft-600 dark:text-craft-300">
                <li className="flex items-center gap-2">
                  <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400 shrink-0" />
                  <span><strong>7/7 Verification Gates:</strong> Closure, Monomorphism, and Differential compiler tests 100% green.</span>
                </li>
                <li className="flex items-center gap-2">
                  <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400 shrink-0" />
                  <span><strong>Closed Memory Bounds:</strong> Zero unbounded heap growth in WASI sandbox.</span>
                </li>
                <li className="flex items-center gap-2">
                  <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400 shrink-0" />
                  <span><strong>Non-Dogmatic Advisory:</strong> Ecosystem-agnostic linters and security checks recommended by default.</span>
                </li>
              </ul>

            </div>

          </div>

        </div>

      </div>
    </section>
  );
};
