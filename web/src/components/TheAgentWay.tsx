import React from 'react';
import { Compass, Sparkles, CheckCircle2, XCircle, ShieldCheck, Zap, Layers } from 'lucide-react';

export const TheAgentWay: React.FC = () => {
  return (
    <section id="agent-way" className="relative py-28 border-b border-craft-200 dark:border-craft-800/80 bg-craft-50/60 dark:bg-craft-950/80 transition-colors">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Section Header */}
        <div className="max-w-3xl mx-auto text-center mb-16">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-cyan-500/10 border border-cyan-500/30 text-cyan-600 dark:text-cyan-400 text-xs font-mono mb-4">
            <Compass className="w-3.5 h-3.5" />
            <span>The Paradigm Shift</span>
          </div>

          <h2 className="text-3xl sm:text-5xl font-extrabold tracking-[-0.035em] text-craft-900 dark:text-craft-50 font-sans leading-tight">
            The Agent Way.
          </h2>

          <p className="mt-4 text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans leading-relaxed">
            First came <strong>Object-Oriented Programming</strong>. Then came <strong>Functional Programming</strong>. Today begins <strong>Agentic-Oriented Programming (AOP)</strong> — the true path for human-AI co-creation.
          </p>
        </div>

        {/* The Comparative Paradigm Grid: The Old Way vs The Agent Way */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 mb-16">
          
          {/* Column 1: The Fragile Old Way */}
          <div className="lg:col-span-6 p-8 rounded-3xl border border-rose-500/20 bg-rose-500/[0.02] dark:bg-rose-500/[0.04] backdrop-blur-xl text-left flex flex-col justify-between">
            <div>
              <div className="flex items-center gap-2 text-rose-500 font-mono text-xs font-bold uppercase tracking-wider mb-4">
                <XCircle className="w-4 h-4" />
                <span>The Fragile Past (1995 – 2024)</span>
              </div>
              <h3 className="text-2xl font-bold text-craft-900 dark:text-craft-100 mb-4 font-sans">
                Prompt-and-Pray Code Generation
              </h3>
              
              <ul className="space-y-3.5 text-sm text-craft-600 dark:text-craft-300 font-sans">
                <li className="flex items-start gap-2.5">
                  <span className="text-rose-500 font-bold">•</span>
                  <span><strong>Indentation & Syntax Hallucinations:</strong> LLMs struggle with complex bracket pairs, indentation errors, and compiler drift.</span>
                </li>
                <li className="flex items-start gap-2.5">
                  <span className="text-rose-500 font-bold">•</span>
                  <span><strong>Endless Repair Loops:</strong> 4 to 8 conversational roundtrips just to fix broken types and missing imports.</span>
                </li>
                <li className="flex items-start gap-2.5">
                  <span className="text-rose-500 font-bold">•</span>
                  <span><strong>Context Window Bloat:</strong> Massive token waste feeding raw verbose boilerplate back into agent prompts.</span>
                </li>
                <li className="flex items-start gap-2.5">
                  <span className="text-rose-500 font-bold">•</span>
                  <span><strong>Isolated Monoliths:</strong> Agents operate alone in separate terminal windows without a shared wire protocol.</span>
                </li>
              </ul>
            </div>

            <div className="mt-8 pt-4 border-t border-rose-500/20 text-xs font-mono text-rose-500/80 flex items-center justify-between">
              <span>Failure Rate: High Friction</span>
              <span>Manual Debugging Required</span>
            </div>
          </div>

          {/* Column 2: The Agent Way */}
          <div className="lg:col-span-6 p-8 rounded-3xl border border-craft-accent/50 bg-gradient-to-b from-craft-100/90 dark:from-craft-900/90 to-white dark:to-craft-950 backdrop-blur-xl shadow-glow-md text-left flex flex-col justify-between relative overflow-hidden">
            <div className="absolute top-0 right-0 p-4 opacity-10">
              <Sparkles className="w-32 h-32 text-craft-accent" />
            </div>

            <div>
              <div className="flex items-center gap-2 text-craft-accent font-mono text-xs font-bold uppercase tracking-wider mb-4">
                <CheckCircle2 className="w-4 h-4 text-craft-emerald" />
                <span>The Agent Way (2026+)</span>
              </div>
              <h3 className="text-2xl font-bold text-craft-900 dark:text-craft-100 mb-4 font-sans">
                Agentic-Oriented Programming (AOP)
              </h3>

              <ul className="space-y-3.5 text-sm text-craft-700 dark:text-craft-200 font-sans">
                <li className="flex items-start gap-2.5">
                  <CheckCircle2 className="w-4 h-4 text-craft-emerald shrink-0 mt-0.5" />
                  <span><strong>Single-Pass Mathematical Contracts:</strong> Deterministic S-expressions eliminate all parsing ambiguity and indentation crashes.</span>
                </li>
                <li className="flex items-start gap-2.5">
                  <CheckCircle2 className="w-4 h-4 text-craft-emerald shrink-0 mt-0.5" />
                  <span><strong>78% Lower Token Overhead:</strong> ASL Nano interface compression keeps agent context focused solely on contracts and types.</span>
                </li>
                <li className="flex items-start gap-2.5">
                  <CheckCircle2 className="w-4 h-4 text-craft-emerald shrink-0 mt-0.5" />
                  <span><strong>Autonomous Swarm Superposition:</strong> Specialist agents communicate over high-speed in-memory socket buses in &lt;0.04ms.</span>
                </li>
                <li className="flex items-start gap-2.5">
                  <CheckCircle2 className="w-4 h-4 text-craft-emerald shrink-0 mt-0.5" />
                  <span><strong>Zero-Cost Sandbox Proofs:</strong> Code is proven and executed in Wasm before touching user disk or production servers.</span>
                </li>
              </ul>
            </div>

            <div className="mt-8 pt-4 border-t border-craft-200 dark:border-craft-800 text-xs font-mono text-craft-accent font-bold flex items-center justify-between">
              <span>Zero-Hallucination Execution</span>
              <span>100% Spec Verified</span>
            </div>
          </div>

        </div>

        {/* 3 Core Pillars of Agentic-Oriented Programming */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-6 text-left">
          <div className="p-6 rounded-2xl border border-craft-200 dark:border-craft-800/80 bg-white dark:bg-craft-900/40 backdrop-blur-md hover:border-craft-accent/50 hover:shadow-glow-sm transition-all group">
            <div className="w-10 h-10 rounded-xl bg-craft-100 dark:bg-craft-800 border border-craft-200 dark:border-craft-700 flex items-center justify-center text-craft-accent mb-4 group-hover:scale-110 transition-transform">
              <Zap className="w-5 h-5" />
            </div>
            <h4 className="font-mono font-bold text-base text-craft-900 dark:text-craft-100 mb-1">
              1. Intent to Contract
            </h4>
            <p className="text-xs sm:text-sm text-craft-600 dark:text-craft-300 font-sans leading-relaxed">
              Human intent translates directly into verified mathematical contracts without manual syntax wrestling.
            </p>
          </div>

          <div className="p-6 rounded-2xl border border-craft-200 dark:border-craft-800/80 bg-white dark:bg-craft-900/40 backdrop-blur-md hover:border-craft-accent/50 hover:shadow-glow-sm transition-all group">
            <div className="w-10 h-10 rounded-xl bg-craft-100 dark:bg-craft-800 border border-craft-200 dark:border-craft-700 flex items-center justify-center text-purple-500 mb-4 group-hover:scale-110 transition-transform">
              <Layers className="w-5 h-5 text-purple-400" />
            </div>
            <h4 className="font-mono font-bold text-base text-craft-900 dark:text-craft-100 mb-1">
              2. Swarm Synthesis
            </h4>
            <p className="text-xs sm:text-sm text-craft-600 dark:text-craft-300 font-sans leading-relaxed">
              Planners, coders, and gate auditors collaborate in real-time superposition with deterministic consensus.
            </p>
          </div>

          <div className="p-6 rounded-2xl border border-craft-200 dark:border-craft-800/80 bg-white dark:bg-craft-900/40 backdrop-blur-md hover:border-craft-accent/50 hover:shadow-glow-sm transition-all group">
            <div className="w-10 h-10 rounded-xl bg-craft-100 dark:bg-craft-800 border border-craft-200 dark:border-craft-700 flex items-center justify-center text-emerald-500 mb-4 group-hover:scale-110 transition-transform">
              <ShieldCheck className="w-5 h-5 text-emerald-400" />
            </div>
            <h4 className="font-mono font-bold text-base text-craft-900 dark:text-craft-100 mb-1">
              3. Frictionless Impact
            </h4>
            <p className="text-xs sm:text-sm text-craft-600 dark:text-craft-300 font-sans leading-relaxed">
              Output deploys effortlessly across WebAssembly, TypeScript, Rust, Go, Python with zero platform friction.
            </p>
          </div>
        </div>

      </div>
    </section>
  );
};
