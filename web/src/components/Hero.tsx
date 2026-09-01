import React, { useState } from 'react';
import { ArrowRight, Terminal, Check, Sparkles, ShieldCheck, Compass } from 'lucide-react';

export const Hero: React.FC = () => {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText('curl -fsSL https://aslang.dev/install.sh | bash');
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <section className="relative min-h-[90vh] flex items-center justify-center pt-24 pb-20 border-b border-craft-200/60 dark:border-white/[0.06] bg-white dark:bg-[#04060a] overflow-hidden transition-colors">
      
      {/* Seamless Ambient Caustics & Volumetric Glow */}
      <div className="absolute top-1/4 right-1/4 w-[700px] h-[500px] bg-cyan-500/10 dark:bg-cyan-500/15 blur-[160px] rounded-full pointer-events-none z-0" />
      <div className="absolute bottom-10 left-10 w-[500px] h-[400px] bg-amber-500/5 dark:bg-amber-500/10 blur-[150px] rounded-full pointer-events-none z-0" />

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10 w-full">
        
        {/* Asymmetrical 2-Column Grid: Text & Actions on Left, Seamless Floating Core on Right */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 lg:gap-12 items-center">
          
          {/* Left Column: Monumental Typography, Inline Installer & Actions */}
          <div className="lg:col-span-7 space-y-6 text-left">
            
            {/* Ambient Pill Tag */}
            <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full border border-craft-300/80 dark:border-white/[0.12] bg-craft-100/80 dark:bg-white/[0.03] backdrop-blur-2xl text-xs font-mono text-craft-900 dark:text-white shadow-sm">
              <span className="w-2 h-2 rounded-full bg-craft-accent shadow-[0_0_8px_#06b6d4] animate-pulse" />
              <span className="font-semibold tracking-wider uppercase text-[11px]">THE AGENT WAY // AGENTIC PROGRAMMING</span>
            </div>

            {/* Monumental Editorial Headline */}
            <h1 className="text-4xl sm:text-6xl lg:text-[4.8rem] font-extrabold tracking-[-0.045em] font-sans leading-[1.02] text-craft-900 dark:text-white">
              The Architecture of{' '}
              <span className="bg-gradient-to-r from-cyan-400 via-teal-300 to-emerald-400 bg-clip-text text-transparent">
                Autonomous Thought.
              </span>
            </h1>

            {/* Visionary Narrative */}
            <p className="text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans font-light leading-relaxed max-w-xl">
              <strong>ASL</strong> is the precision language substrate uniting human intent with self-organizing societies of autonomous agents. Single-pass mathematical contracts, deterministic type invariants, and instant sub-millisecond execution.
            </p>

            {/* Inline Frosted Glass Installer */}
            <div className="pt-2 max-w-lg">
              <div className="p-2 rounded-2xl border border-craft-300/80 dark:border-white/[0.12] bg-craft-100/90 dark:bg-white/[0.03] backdrop-blur-2xl shadow-xl flex items-center justify-between gap-3">
                <div className="flex items-center gap-2.5 px-2 text-xs font-mono text-craft-600 dark:text-craft-400 truncate">
                  <Terminal className="w-4 h-4 text-craft-accent shrink-0" />
                  <code className="text-craft-900 dark:text-cyan-300 font-bold select-all overflow-x-auto whitespace-nowrap">
                    curl -fsSL https://aslang.dev/install.sh | bash
                  </code>
                </div>
                <button
                  onClick={handleCopy}
                  className="px-4 py-2 rounded-xl bg-craft-900 dark:bg-white text-white dark:text-black font-mono text-xs font-bold hover:scale-105 active:scale-95 transition-all flex items-center gap-1.5 shrink-0 shadow-md"
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

            {/* Seamless Action Buttons */}
            <div className="flex flex-wrap gap-4 items-center pt-2 font-mono">
              <a
                href="#agent-way"
                className="px-7 py-3.5 rounded-full bg-craft-accent text-craft-950 font-extrabold text-xs tracking-wider uppercase hover:bg-craft-accent/90 hover:scale-105 active:scale-95 transition-all flex items-center gap-2 shadow-[0_0_25px_rgba(6,182,212,0.35)]"
              >
                <span>Explore The Paradigm</span>
                <ArrowRight className="w-4 h-4" />
              </a>
              <a
                href="#a2a-protocol"
                className="px-7 py-3.5 rounded-full bg-craft-100 dark:bg-white/[0.04] border border-craft-300 dark:border-white/[0.12] text-craft-900 dark:text-white text-xs tracking-wider uppercase hover:border-craft-accent hover:text-craft-accent transition-all flex items-center gap-2"
              >
                <Compass className="w-4 h-4 text-craft-accent" />
                <span>A2A Wire Protocol</span>
              </a>
            </div>

          </div>

          {/* Right Column: Seamless 3D Quantum Processor Core Floating in Space */}
          <div className="lg:col-span-5 relative flex items-center justify-center">
            
            <div className="relative w-full max-w-md lg:max-w-none group">
              
              {/* Diffuse radial aura behind the core */}
              <div className="absolute inset-0 bg-gradient-to-tr from-cyan-500/20 via-purple-500/15 to-transparent blur-3xl rounded-full scale-110 group-hover:scale-125 transition-transform duration-1000" />

              <img
                src="/assets/images/quantum_core_scene.jpg"
                alt="Autonomous Agentic Quantum Processor Core"
                className="relative z-10 w-full h-auto rounded-3xl object-cover shadow-[0_0_60px_rgba(0,0,0,0.8)] group-hover:scale-[1.02] transition-transform duration-700 ease-out"
              />

              {/* Seamless Orbiting Telemetry HUD Badge 1 */}
              <div className="absolute -top-4 -left-4 sm:top-6 sm:-left-6 z-20 p-3.5 rounded-2xl bg-white/90 dark:bg-[#06080d]/90 backdrop-blur-2xl border border-craft-200 dark:border-white/[0.12] shadow-2xl text-left font-mono">
                <div className="flex items-center gap-2 text-[10px] text-craft-accent font-bold tracking-wider">
                  <Sparkles className="w-3.5 h-3.5 animate-pulse" />
                  <span>SINGLE-PASS CONTRACT</span>
                </div>
                <div className="text-xs font-bold text-craft-900 dark:text-white mt-1">
                  Minimizes Hallucination Drift
                </div>
                <div className="text-[10px] text-craft-500 dark:text-craft-400 mt-0.5">–78% Token Overhead</div>
              </div>

              {/* Seamless Orbiting Telemetry HUD Badge 2 */}
              <div className="absolute -bottom-4 -right-4 sm:bottom-6 sm:-right-6 z-20 p-3.5 rounded-2xl bg-white/90 dark:bg-[#06080d]/90 backdrop-blur-2xl border border-craft-200 dark:border-white/[0.12] shadow-2xl text-right font-mono">
                <div className="flex items-center justify-end gap-2 text-[10px] text-emerald-500 dark:text-emerald-400 font-bold tracking-wider">
                  <ShieldCheck className="w-3.5 h-3.5" />
                  <span>NATIVE PROOF</span>
                </div>
                <div className="text-xs font-bold text-craft-900 dark:text-white mt-1">
                  WASI &lt;0.04ms Latency
                </div>
                <div className="text-[10px] text-craft-500 dark:text-craft-400 mt-0.5">100% Spec Verified</div>
              </div>
            </div>

          </div>

        </div>

      </div>
    </section>
  );
};
