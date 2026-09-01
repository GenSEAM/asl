import React, { useState } from 'react';
import { ArrowRight, Terminal, Check, Sparkles, ShieldCheck } from 'lucide-react';

export const Hero: React.FC = () => {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText('curl -fsSL https://aslang.dev/install.sh | bash');
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <section className="relative min-h-[92vh] flex items-center justify-center pt-28 pb-20 border-b border-craft-200/60 dark:border-white/[0.06] bg-[#030508] overflow-hidden">
      
      {/* Full-Bleed Atmospheric Nebula Background Canvas */}
      <div className="absolute inset-0 z-0">
        <img
          src="/assets/images/ambient_bg.jpg"
          alt="Ambient Space Horizon"
          className="w-full h-full object-cover opacity-60 dark:opacity-40"
        />
        <div className="absolute inset-0 bg-gradient-to-b from-[#030508]/80 via-transparent to-[#030508]" />
      </div>

      {/* Ambient Lighting Spotlights */}
      <div className="absolute top-1/4 left-1/2 -translate-x-1/2 w-[800px] h-[500px] bg-cyan-500/10 blur-[160px] rounded-full pointer-events-none z-0" />

      <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10 text-center">
        
        {/* Top Floating Badge */}
        <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full border border-white/[0.12] bg-white/[0.04] backdrop-blur-2xl text-xs font-mono text-white mb-8 shadow-2xl">
          <span className="w-2 h-2 rounded-full bg-craft-accent shadow-[0_0_10px_#06b6d4] animate-pulse" />
          <span className="font-semibold tracking-wider uppercase text-[11px]">THE AGENT WAY // AGENTIC PROGRAMMING</span>
        </div>

        {/* Hero Title Directly On Ambient Canvas */}
        <h1 className="text-5xl sm:text-7xl lg:text-[5.8rem] font-extrabold tracking-[-0.05em] font-sans leading-[0.96] text-white max-w-4xl mx-auto">
          The Architecture of{' '}
          <span className="bg-gradient-to-r from-cyan-400 via-teal-300 to-emerald-400 bg-clip-text text-transparent">
            Autonomous Thought.
          </span>
        </h1>

        <p className="mt-6 text-lg sm:text-xl text-craft-300 font-sans font-light max-w-2xl mx-auto leading-relaxed tracking-[-0.01em]">
          ASL is the precision substrate uniting human vision with self-organizing societies of autonomous agents.
        </p>

        {/* Central Masterpiece: 3D Titanium & Sapphire Monolith Floating with Overlaid HUD Specs */}
        <div className="mt-10 relative max-w-3xl mx-auto">
          <div className="relative rounded-[2.5rem] border border-white/[0.12] bg-white/[0.02] p-3 sm:p-4 backdrop-blur-3xl shadow-[0_0_80px_rgba(0,0,0,0.8)] overflow-hidden group">
            
            <div className="relative rounded-3xl overflow-hidden">
              <img
                src="/assets/images/apple_monolith.jpg"
                alt="ASL Titanium Monolith"
                className="w-full h-auto max-h-[440px] object-cover rounded-3xl group-hover:scale-[1.03] transition-transform duration-1000 ease-out"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-[#030508] via-transparent to-transparent opacity-75" />
            </div>

            {/* Overlaid Holographic Specs */}
            <div className="absolute top-8 left-8 p-3.5 rounded-2xl bg-black/60 backdrop-blur-2xl border border-white/[0.1] shadow-2xl text-left font-mono hidden sm:block">
              <div className="flex items-center gap-2 text-[10px] text-craft-accent font-bold tracking-wider">
                <Sparkles className="w-3.5 h-3.5" />
                <span>SINGLE-PASS CONTRACT</span>
              </div>
              <div className="text-xs font-bold text-white mt-1">Zero Hallucination Loops</div>
              <div className="text-[10px] text-craft-400 mt-0.5">–78% Token Overhead</div>
            </div>

            <div className="absolute bottom-8 right-8 p-3.5 rounded-2xl bg-black/60 backdrop-blur-2xl border border-white/[0.1] shadow-2xl text-right font-mono hidden sm:block">
              <div className="flex items-center justify-end gap-2 text-[10px] text-emerald-400 font-bold tracking-wider">
                <ShieldCheck className="w-3.5 h-3.5" />
                <span>NATIVE PROOF</span>
              </div>
              <div className="text-xs font-bold text-white mt-1">WASI &lt;0.04ms Latency</div>
              <div className="text-[10px] text-craft-400 mt-0.5">100% Spec Verified</div>
            </div>
          </div>
        </div>

        {/* Floating Brushed Titanium Installer Capsule */}
        <div className="mt-10 max-w-lg mx-auto p-2 rounded-2xl border border-white/[0.15] bg-white/[0.04] backdrop-blur-2xl shadow-2xl">
          <div className="flex items-center justify-between gap-3 px-3.5 py-2 rounded-xl bg-black/60 border border-white/[0.06]">
            <div className="flex items-center gap-2 text-xs font-mono text-craft-400">
              <Terminal className="w-4 h-4 text-craft-accent" />
              <code className="text-cyan-300 font-bold select-all overflow-x-auto whitespace-nowrap">
                curl -fsSL https://aslang.dev/install.sh | bash
              </code>
            </div>
            <button
              onClick={handleCopy}
              className="px-4 py-1.5 rounded-lg bg-white text-black font-mono text-xs font-bold hover:scale-105 active:scale-95 transition-all flex items-center gap-1.5 shrink-0 shadow-sm"
            >
              {copied ? (
                <>
                  <Check className="w-3.5 h-3.5 text-emerald-600" />
                  <span>Copied</span>
                </>
              ) : (
                <span>Copy</span>
              )}
            </button>
          </div>
        </div>

        {/* Minimalist CTA Actions */}
        <div className="mt-8 flex flex-wrap gap-4 items-center justify-center font-mono">
          <a
            href="#agent-way"
            className="px-8 py-3.5 rounded-full bg-craft-accent text-craft-950 font-extrabold text-xs tracking-wider uppercase hover:bg-craft-accent/90 hover:scale-105 active:scale-95 transition-all flex items-center gap-2 shadow-[0_0_30px_rgba(6,182,212,0.4)]"
          >
            <span>Explore The Paradigm</span>
            <ArrowRight className="w-4 h-4" />
          </a>
          <a
            href="#a2a-protocol"
            className="px-8 py-3.5 rounded-full bg-white/[0.05] border border-white/[0.12] text-white text-xs tracking-wider uppercase hover:bg-white/[0.1] transition-all flex items-center gap-2"
          >
            <span>A2A Wire Protocol</span>
          </a>
        </div>

      </div>
    </section>
  );
};
