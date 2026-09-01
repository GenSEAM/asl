import React from 'react';
import { Bot, Wrench, ShieldCheck, Cpu, Zap, Activity } from 'lucide-react';

export const Ecosystem: React.FC = () => {
  return (
    <section className="py-24 border-b border-craft-200/80 dark:border-white/[0.08] bg-white dark:bg-[#05070a] transition-colors">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        
        {/* Section Header */}
        <div className="max-w-3xl mx-auto text-center mb-16">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-cyan-500/10 border border-cyan-500/30 text-cyan-600 dark:text-cyan-400 text-xs font-mono mb-4">
            <Activity className="w-3.5 h-3.5" />
            <span>Developer Surface & Empirical Verification</span>
          </div>

          <h2 className="text-3xl sm:text-5xl font-extrabold tracking-[-0.04em] text-craft-900 dark:text-white font-sans leading-tight">
            Deterministic Developer Suite.
          </h2>

          <p className="mt-4 text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans leading-relaxed tracking-[-0.01em]">
            ASL gives autonomous agents computational freedom with strict host isolation, in-memory WASI preview1 execution, and verified differential gates.
          </p>
        </div>

        {/* 4 Core Tooling Pillars */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 text-left mb-16">
          
          {/* Tool 1: MCP Server */}
          <div className="p-6 rounded-3xl border border-craft-200 dark:border-white/[0.08] bg-craft-50/80 dark:bg-white/[0.02] backdrop-blur-xl hover:border-craft-300 dark:hover:border-white/[0.15] transition-all flex flex-col justify-between">
            <div>
              <div className="w-10 h-10 rounded-2xl bg-cyan-500/10 border border-cyan-500/30 flex items-center justify-center text-cyan-400 mb-4">
                <Bot className="w-5 h-5" />
              </div>
              <h3 className="text-base font-bold text-craft-900 dark:text-white mb-2 font-sans">
                Stdlib MCP Server
              </h3>
              <p className="text-xs text-craft-600 dark:text-craft-300 font-sans leading-relaxed mb-4">
                JSON-RPC 2.0 stdio server providing structured tools for LLMs: <code className="text-cyan-600 dark:text-cyan-400">asl_check</code>, <code className="text-cyan-600 dark:text-cyan-400">asl_eval</code>, <code className="text-cyan-600 dark:text-cyan-400">asl_format</code>, <code className="text-cyan-600 dark:text-cyan-400">asl_compress</code>.
              </p>
            </div>
            <div className="p-2.5 rounded-xl bg-craft-100 dark:bg-[#07090e] border border-craft-200 dark:border-white/[0.06] text-[11px] font-mono text-cyan-600 dark:text-cyan-300">
              $ asl mcp
            </div>
          </div>

          {/* Tool 2: In-Memory Scratchpad */}
          <div className="p-6 rounded-3xl border border-cyan-500/30 bg-cyan-500/5 dark:bg-white/[0.03] backdrop-blur-xl hover:border-cyan-500/50 transition-all flex flex-col justify-between shadow-lg">
            <div>
              <div className="w-10 h-10 rounded-2xl bg-cyan-500/10 border border-cyan-500/30 flex items-center justify-center text-cyan-400 mb-4">
                <Cpu className="w-5 h-5" />
              </div>
              <h3 className="text-base font-bold text-craft-900 dark:text-white mb-2 font-sans">
                WASI Scratchpad
              </h3>
              <p className="text-xs text-craft-600 dark:text-craft-300 font-sans leading-relaxed mb-4">
                Execute compiled ASL bytecode inside an in-memory WASI sandbox in &lt;0.04ms. Pure memory buffers capture stdout/stderr with zero host disk risks.
              </p>
            </div>
            <div className="p-2.5 rounded-xl bg-craft-100 dark:bg-[#07090e] border border-craft-200 dark:border-white/[0.06] text-[11px] font-mono text-emerald-600 dark:text-emerald-400">
              $ asl run --target wasm app.asl
            </div>
          </div>

          {/* Tool 3: Tree-Sitter & Formatter */}
          <div className="p-6 rounded-3xl border border-craft-200 dark:border-white/[0.08] bg-craft-50/80 dark:bg-white/[0.02] backdrop-blur-xl hover:border-craft-300 dark:hover:border-white/[0.15] transition-all flex flex-col justify-between">
            <div>
              <div className="w-10 h-10 rounded-2xl bg-cyan-500/10 border border-cyan-500/30 flex items-center justify-center text-cyan-400 mb-4">
                <Wrench className="w-5 h-5" />
              </div>
              <h3 className="text-base font-bold text-craft-900 dark:text-white mb-2 font-sans">
                CLI Compiler & Formatter
              </h3>
              <p className="text-xs text-craft-600 dark:text-craft-300 font-sans leading-relaxed mb-4">
                Multi-target compiler with canonical S-expression layout formatting, syntax queries via Tree-Sitter, and zero-overhead binary builds.
              </p>
            </div>
            <div className="p-2.5 rounded-xl bg-craft-100 dark:bg-[#07090e] border border-craft-200 dark:border-white/[0.06] text-[11px] font-mono text-cyan-600 dark:text-cyan-300">
              $ asl build --target wasm
            </div>
          </div>

          {/* Tool 4: Differential Gate */}
          <div className="p-6 rounded-3xl border border-craft-200 dark:border-white/[0.08] bg-craft-50/80 dark:bg-white/[0.02] backdrop-blur-xl hover:border-craft-300 dark:hover:border-white/[0.15] transition-all flex flex-col justify-between">
            <div>
              <div className="w-10 h-10 rounded-2xl bg-cyan-500/10 border border-cyan-500/30 flex items-center justify-center text-cyan-400 mb-4">
                <ShieldCheck className="w-5 h-5" />
              </div>
              <h3 className="text-base font-bold text-craft-900 dark:text-white mb-2 font-sans">
                Differential Gate Matrix
              </h3>
              <p className="text-xs text-craft-600 dark:text-craft-300 font-sans leading-relaxed mb-4">
                Automated differential runner asserting identical bytecode execution across 6 platforms (Python, Rust, Wasm, Go, TS, Interp) with 0 tolerance.
              </p>
            </div>
            <div className="p-2.5 rounded-xl bg-craft-100 dark:bg-[#07090e] border border-craft-200 dark:border-white/[0.06] text-[11px] font-mono text-cyan-600 dark:text-cyan-300">
              0 disagreements across 135 runs
            </div>
          </div>

        </div>

        {/* Benchmarks & Empirical Proof */}
        <div className="p-8 sm:p-10 rounded-[2.5rem] border border-craft-200 dark:border-white/[0.08] bg-craft-50/60 dark:bg-white/[0.02] backdrop-blur-2xl text-left">
          <div className="flex flex-col lg:flex-row gap-8 items-center justify-between">
            <div className="max-w-xl">
              <div className="flex items-center gap-2 text-cyan-600 dark:text-cyan-400 font-mono text-xs font-bold uppercase tracking-wider mb-2">
                <Zap className="w-4 h-4" />
                <span>Empirical Measurements</span>
              </div>
              <h3 className="text-2xl sm:text-3xl font-extrabold text-craft-900 dark:text-white font-sans tracking-tight mb-2">
                78% Token Reduction for AI Workflows
              </h3>
              <p className="text-xs sm:text-sm text-craft-600 dark:text-craft-300 font-sans leading-relaxed">
                Because AgentScript interface compression (<code className="text-cyan-600 dark:text-cyan-400 font-mono">asl_compress</code>) strips internal function bodies into stubbed signatures while retaining full type safety, multi-agent LLM calls use a fraction of their context window.
              </p>
            </div>

            <div className="w-full lg:w-auto font-mono text-xs overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="border-b border-craft-200 dark:border-white/[0.08] text-craft-400 text-[11px]">
                    <th className="pb-2 pr-6">Benchmark Task</th>
                    <th className="pb-2 pr-6 text-cyan-600 dark:text-cyan-400 font-bold">ASL / Wasm</th>
                    <th className="pb-2 text-craft-500">Python 3.13</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-craft-200 dark:divide-white/[0.04] text-craft-800 dark:text-craft-200">
                  <tr>
                    <td className="py-2.5 pr-6">Word Frequency (10k ops)</td>
                    <td className="py-2.5 pr-6 text-emerald-600 dark:text-emerald-400 font-bold">3.42 ms</td>
                    <td className="py-2.5 text-craft-500">38.20 ms</td>
                  </tr>
                  <tr>
                    <td className="py-2.5 pr-6">Matrix Multiplication (64x64)</td>
                    <td className="py-2.5 pr-6 text-emerald-600 dark:text-emerald-400 font-bold">0.85 ms</td>
                    <td className="py-2.5 text-craft-500">46.10 ms</td>
                  </tr>
                  <tr>
                    <td className="py-2.5 pr-6">Vector Cosine Search (1,000 embeddings)</td>
                    <td className="py-2.5 pr-6 text-emerald-600 dark:text-emerald-400 font-bold">0.35 ms</td>
                    <td className="py-2.5 text-craft-500">26.40 ms</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

      </div>
    </section>
  );
};
