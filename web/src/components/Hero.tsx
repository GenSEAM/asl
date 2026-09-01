import React, { useState } from 'react';
import { ArrowRight, Terminal, Check, Sparkles, Compass, ShieldCheck } from 'lucide-react';

export const Hero: React.FC = () => {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText('curl -fsSL https://aslang.dev/install.sh | bash');
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <section className="relative pt-20 pb-36 border-b border-craft-200/60 dark:border-white/[0.06] bg-white dark:bg-[#030508] overflow-hidden transition-colors">
      {/* Apple-grade Optical Radial Caustics */}
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[1000px] h-[550px] bg-gradient-to-b from-cyan-500/10 via-purple-500/5 to-transparent blur-[160px] rounded-full pointer-events-none" />
      <div className="absolute top-1/3 left-1/4 w-[400px] h-[400px] bg-amber-500/5 blur-[140px] rounded-full pointer-events-none" />

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Top Floating Pro Tag */}
        <div className="flex justify-center mb-8">
          <div className="inline-flex items-center gap-2.5 px-4 py-1.5 rounded-full border border-craft-300/80 dark:border-white/[0.12] bg-white/80 dark:bg-white/[0.03] backdrop-blur-2xl text-xs font-mono text-craft-900 dark:text-white shadow-xl hover:border-craft-accent transition-all">
            <span className="w-2 h-2 rounded-full bg-craft-accent shadow-[0_0_8px_#06b6d4] animate-pulse" />
            <span className="font-medium tracking-wide">THE AGENT WAY // AGENTIC PROGRAMMING</span>
          </div>
        </div>

        {/* Monumental Editorial Headline */}
        <div className="max-w-5xl mx-auto text-center space-y-6">
          <h1 className="text-5xl sm:text-7xl lg:text-[5.4rem] font-extrabold tracking-[-0.05em] font-sans leading-[0.98] text-craft-900 dark:text-white">
            The Architecture of{' '}
            <span className="bg-gradient-to-r from-cyan-400 via-teal-300 to-emerald-400 bg-clip-text text-transparent">
              Autonomous Intelligence.
            </span>
          </h1>

          <p className="mt-6 text-lg sm:text-2xl text-craft-600 dark:text-craft-300 font-sans font-normal max-w-3xl mx-auto leading-relaxed tracking-[-0.015em]">
            ASL is the precision language and ecosystem substrate crafted for the next epoch. Uniting human intent with self-organizing societies of autonomous agents.
          </p>
        </div>

        {/* Central Masterpiece: The 3D Titanium & Sapphire Glass Monolith */}
        <div className="mt-14 relative max-w-4xl mx-auto">
          <div className="relative rounded-[2.5rem] border border-craft-200 dark:border-white/[0.12] bg-craft-50/40 dark:bg-white/[0.02] p-4 sm:p-6 backdrop-blur-3xl shadow-2xl overflow-hidden group">
            
            {/* The 3D Sculptural Monolith Artifact */}
            <div className="relative rounded-3xl overflow-hidden bg-black/40">
              <img
                src="/assets/images/apple_monolith.jpg"
                alt="ASL Titanium & Sapphire Prism Monolith"
                className="w-full h-auto max-h-[520px] object-cover rounded-3xl shadow-2xl group-hover:scale-[1.02] transition-transform duration-1000 ease-out"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-[#030508] via-transparent to-transparent opacity-80" />
            </div>

            {/* Left Floating Frosted Spec Card */}
            <div className="absolute top-10 left-10 p-4 rounded-2xl bg-white/85 dark:bg-[#080b11]/85 backdrop-blur-2xl border border-craft-200 dark:border-white/[0.1] shadow-2xl text-left font-mono hidden sm:block">
              <div className="flex items-center gap-2 text-[10px] text-craft-accent font-bold tracking-wider uppercase">
                <Sparkles className="w-3.5 h-3.5" />
                <span>Single-Pass Substrate</span>
              </div>
              <div className="text-xs font-semibold text-craft-900 dark:text-white mt-1">
                Zero Syntax Repair Loops
              </div>
              <div className="text-[10px] text-craft-500 mt-0.5">78% Lower Token Context</div>
            </div>

            {/* Right Floating Frosted Spec Card */}
            <div className="absolute bottom-12 right-10 p-4 rounded-2xl bg-white/85 dark:bg-[#080b11]/85 backdrop-blur-2xl border border-craft-200 dark:border-white/[0.1] shadow-2xl text-right font-mono hidden sm:block">
              <div className="flex items-center justify-end gap-2 text-[10px] text-emerald-400 font-bold tracking-wider uppercase">
                <ShieldCheck className="w-3.5 h-3.5" />
                <span>Mathematical Proof</span>
              </div>
              <div className="text-xs font-semibold text-craft-900 dark:text-white mt-1">
                WASI Isolate &lt;0.04ms
              </div>
              <div className="text-[10px] text-craft-500 mt-0.5">100% Deterministic Wire</div>
            </div>
          </div>
        </div>

        {/* Minimalist Apple-Grade Installation Pill */}
        <div className="mt-12 max-w-xl mx-auto p-2.5 rounded-2xl border border-craft-300 dark:border-white/[0.12] bg-white/90 dark:bg-white/[0.03] backdrop-blur-2xl shadow-xl transition-all">
          <div className="flex items-center justify-between gap-3 px-3 py-2 rounded-xl bg-craft-50 dark:bg-[#06090e] border border-craft-200 dark:border-white/[0.06]">
            <div className="flex items-center gap-2 text-xs font-mono text-craft-600 dark:text-craft-400">
              <Terminal className="w-4 h-4 text-craft-accent" />
              <code className="text-craft-900 dark:text-craft-accent font-bold select-all overflow-x-auto whitespace-nowrap">
                curl -fsSL https://aslang.dev/install.sh | bash
              </code>
            </div>
            <button
              onClick={handleCopy}
              className="px-4 py-1.5 rounded-lg bg-craft-900 dark:bg-white text-white dark:text-black font-mono text-xs font-bold hover:scale-105 active:scale-95 transition-all flex items-center gap-1.5 shrink-0 shadow-sm"
            >
              {copied ? (
                <>
                  <Check className="w-3.5 h-3.5 text-emerald-500" />
                  <span>Copied</span>
                </>
              ) : (
                <span>Copy</span>
              )}
            </button>
          </div>
        </div>

        {/* Minimalist Action Buttons */}
        <div className="mt-8 flex flex-wrap gap-4 items-center justify-center font-mono">
          <a
            href="#agent-way"
            className="px-8 py-4 rounded-2xl bg-craft-accent text-craft-950 font-extrabold text-sm hover:bg-craft-accent/90 hover:scale-[1.02] active:scale-[0.98] transition-all flex items-center gap-2.5 shadow-[0_0_30px_rgba(6,182,212,0.3)]"
          >
            <span>Discover The Agent Way</span>
            <ArrowRight className="w-4 h-4" />
          </a>
          <a
            href="#a2a-protocol"
            className="px-8 py-4 rounded-2xl bg-craft-100 dark:bg-white/[0.04] border border-craft-300 dark:border-white/[0.12] text-craft-900 dark:text-white text-sm hover:border-craft-accent hover:text-craft-accent transition-all flex items-center gap-2"
          >
            <Compass className="w-4 h-4 text-craft-accent" />
            <span>A2A Wire Protocol</span>
          </a>
        </div>

      </div>
    </section>
  );
};
