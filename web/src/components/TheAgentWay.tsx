import React from 'react';
import { Compass, Sparkles, CheckCircle2, XCircle, ShieldCheck, Zap, Layers } from 'lucide-react';

export const TheAgentWay: React.FC = () => {
  return (
    <section id="agent-way" className="relative py-32 border-b border-craft-200/60 dark:border-white/[0.06] bg-white dark:bg-[#05070a] transition-colors">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Section Header */}
        <div className="max-w-3xl mx-auto text-center mb-20">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-cyan-500/10 border border-cyan-500/30 text-cyan-600 dark:text-cyan-400 text-xs font-mono mb-4">
            <Compass className="w-3.5 h-3.5" />
            <span>The Paradigm Shift</span>
          </div>

          <h2 className="text-4xl sm:text-6xl font-extrabold tracking-[-0.04em] text-craft-900 dark:text-white font-sans leading-tight">
            The Agent Way.
          </h2>

          <p className="mt-5 text-base sm:text-xl text-craft-600 dark:text-craft-300 font-sans leading-relaxed tracking-[-0.015em]">
            First came <strong>Object-Oriented Programming (OOP)</strong>. Then came <strong>Functional Programming (FP)</strong>. Today begins <strong>Agentic Programming (AgP)</strong> — the true path for human-AI co-creation.
          </p>
        </div>

        {/* The Comparative Paradigm Grid: The Old Way vs The Agent Way */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 mb-16">
          
          {/* Column 1: The Fragile Old Way */}
          <div className="lg:col-span-6 p-8 sm:p-10 rounded-[2rem] border border-rose-500/20 bg-rose-500/[0.02] dark:bg-rose-500/[0.03] backdrop-blur-2xl text-left flex flex-col justify-between">
            <div>
              <div className="flex items-center gap-2 text-rose-500 font-mono text-xs font-bold uppercase tracking-wider mb-4">
                <XCircle className="w-4 h-4" />
                <span>The Fragile Past (1995 – 2024)</span>
              </div>
              <h3 className="text-2xl font-bold text-craft-900 dark:text-white mb-4 font-sans tracking-tight">
                Prompt-and-Pray Code Generation
              </h3>
              
              <ul className="space-y-4 text-sm text-craft-600 dark:text-craft-300 font-sans leading-relaxed">
                <li className="flex items-start gap-3">
                  <span className="text-rose-500 font-bold">•</span>
                  <span><strong>Indentation & Syntax Hallucinations:</strong> LLMs struggle with complex bracket pairs, indentation errors, and compiler drift.</span>
                </li>
                <li className="flex items-start gap-3">
                  <span className="text-rose-500 font-bold">•</span>
                  <span><strong>Endless Repair Loops:</strong> 4 to 8 conversational roundtrips just to fix broken types and missing imports.</span>
                </li>
                <li className="flex items-start gap-3">
                  <span className="text-rose-500 font-bold">•</span>
                  <span><strong>Context Window Bloat:</strong> Massive token waste feeding raw verbose boilerplate back into agent prompts.</span>
                </li>
                <li className="flex items-start gap-3">
                  <span className="text-rose-500 font-bold">•</span>
                  <span><strong>Isolated Monoliths:</strong> Agents operate alone in separate terminal windows without a shared wire protocol.</span>
                </li>
              </ul>
            </div>

            <div className="mt-10 pt-4 border-t border-rose-500/20 text-xs font-mono text-rose-500/80 flex items-center justify-between">
              <span>Failure Rate: High Friction</span>
              <span>Manual Debugging Required</span>
            </div>
          </div>

          {/* Column 2: The Agent Way */}
          <div className="lg:col-span-6 p-8 sm:p-10 rounded-[2rem] border border-craft-accent/50 bg-gradient-to-b from-white dark:from-white/[0.04] to-craft-50 dark:to-white/[0.01] backdrop-blur-2xl shadow-[0_0_40px_rgba(6,182,212,0.12)] text-left flex flex-col justify-between relative overflow-hidden">
            <div className="absolute top-0 right-0 p-6 opacity-10">
              <Sparkles className="w-36 h-36 text-craft-accent" />
            </div>

            <div>
              <div className="flex items-center gap-2 text-craft-accent font-mono text-xs font-bold uppercase tracking-wider mb-4">
                <CheckCircle2 className="w-4 h-4 text-emerald-400" />
                <span>The Agent Way (2026+)</span>
              </div>
              <h3 className="text-2xl font-bold text-craft-900 dark:text-white mb-4 font-sans tracking-tight">
                Agentic Programming (AgP)
              </h3>

              <ul className="space-y-4 text-sm text-craft-700 dark:text-craft-200 font-sans leading-relaxed">
                <li className="flex items-start gap-3">
                  <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
                  <span><strong>Single-Pass Mathematical Contracts:</strong> Deterministic S-expressions eliminate all parsing ambiguity and indentation crashes.</span>
                </li>
                <li className="flex items-start gap-3">
                  <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
                  <span><strong>78% Lower Token Overhead:</strong> ASL Nano interface compression keeps agent context focused solely on contracts and types.</span>
                </li>
                <li className="flex items-start gap-3">
                  <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
                  <span><strong>Autonomous Swarm Superposition:</strong> Specialist agents communicate over high-speed in-memory socket buses in &lt;0.04ms.</span>
                </li>
                <li className="flex items-start gap-3">
                  <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
                  <span><strong>Zero-Cost Sandbox Proofs:</strong> Code is proven and executed in Wasm before touching user disk or production servers.</span>
                </li>
              </ul>
            </div>

            <div className="mt-10 pt-4 border-t border-craft-200 dark:border-white/[0.08] text-xs font-mono text-craft-accent font-bold flex items-center justify-between">
              <span>Zero-Hallucination Execution</span>
              <span className="text-emerald-400">100% Spec Verified</span>
            </div>
          </div>

        </div>

        {/* 3 Core Pillars of Agentic Programming */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-6 text-left">
          <div className="p-8 rounded-[1.8rem] border border-craft-200 dark:border-white/[0.08] bg-white dark:bg-white/[0.02] backdrop-blur-xl hover:border-craft-accent/50 hover:shadow-glow-sm transition-all group">
            <div className="w-12 h-12 rounded-2xl bg-craft-100 dark:bg-white/[0.04] border border-craft-200 dark:border-white/[0.08] flex items-center justify-center text-craft-accent mb-6 group-hover:scale-110 transition-transform">
              <Zap className="w-6 h-6" />
            </div>
            <h4 className="font-mono font-bold text-lg text-craft-900 dark:text-white mb-2">
              1. Intent to Contract
            </h4>
            <p className="text-sm text-craft-600 dark:text-craft-300 font-sans leading-relaxed">
              Human intent translates directly into verified mathematical contracts without manual syntax wrestling.
            </p>
          </div>

          <div className="p-8 rounded-[1.8rem] border border-craft-200 dark:border-white/[0.08] bg-white dark:bg-white/[0.02] backdrop-blur-xl hover:border-craft-accent/50 hover:shadow-glow-sm transition-all group">
            <div className="w-12 h-12 rounded-2xl bg-craft-100 dark:bg-white/[0.04] border border-craft-200 dark:border-white/[0.08] flex items-center justify-center text-purple-500 mb-6 group-hover:scale-110 transition-transform">
              <Layers className="w-6 h-6 text-purple-400" />
            </div>
            <h4 className="font-mono font-bold text-lg text-craft-900 dark:text-white mb-2">
              2. Swarm Synthesis
            </h4>
            <p className="text-sm text-craft-600 dark:text-craft-300 font-sans leading-relaxed">
              Planners, coders, and gate auditors collaborate in real-time superposition with deterministic consensus.
            </p>
          </div>

          <div className="p-8 rounded-[1.8rem] border border-craft-200 dark:border-white/[0.08] bg-white dark:bg-white/[0.02] backdrop-blur-xl hover:border-craft-accent/50 hover:shadow-glow-sm transition-all group">
            <div className="w-12 h-12 rounded-2xl bg-craft-100 dark:bg-white/[0.04] border border-craft-200 dark:border-white/[0.08] flex items-center justify-center text-emerald-500 mb-6 group-hover:scale-110 transition-transform">
              <ShieldCheck className="w-6 h-6 text-emerald-400" />
            </div>
            <h4 className="font-mono font-bold text-lg text-craft-900 dark:text-white mb-2">
              3. Frictionless Impact
            </h4>
            <p className="text-sm text-craft-600 dark:text-craft-300 font-sans leading-relaxed">
              Output deploys effortlessly across WebAssembly, TypeScript, Rust, Go, Python with zero platform friction.
            </p>
          </div>
        </div>

      </div>
    </section>
  );
};
