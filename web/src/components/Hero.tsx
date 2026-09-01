import React, { useState } from 'react';
import { ArrowRight, Terminal, Check, ShieldCheck, Code2, Zap, Cpu } from 'lucide-react';

export const Hero: React.FC = () => {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText('curl -fsSL https://aslang.dev/install.sh | bash');
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <section className="relative min-h-[88vh] flex items-center justify-center pt-24 pb-20 border-b border-craft-200/80 dark:border-white/[0.08] bg-white dark:bg-[#07090e] transition-colors">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10 w-full">
        
        {/* Asymmetrical 2-Column Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 lg:gap-12 items-center">
          
          {/* Left Column: Language Proposition & Inline Installer */}
          <div className="lg:col-span-7 space-y-6 text-left">
            
            {/* Clean Architectural Badge */}
            <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full border border-craft-300 dark:border-white/[0.12] bg-craft-100 dark:bg-white/[0.03] backdrop-blur-xl text-xs font-mono text-craft-900 dark:text-white">
              <span className="w-2 h-2 rounded-full bg-cyan-400" />
              <span className="font-semibold tracking-wider uppercase text-[11px]">THE NATIVE LANGUAGE FOR AI AGENTS</span>
            </div>

            {/* Monumental Headline: The Language */}
            <h1 className="text-4xl sm:text-6xl lg:text-[4.6rem] font-extrabold tracking-[-0.045em] font-sans leading-[1.02] text-craft-900 dark:text-white">
              The Programming Language for{' '}
              <span className="bg-gradient-to-r from-cyan-400 via-teal-300 to-emerald-400 bg-clip-text text-transparent">
                Autonomous Agents.
              </span>
            </h1>

            {/* Clear Language Value Narrative */}
            <p className="text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans font-normal leading-relaxed max-w-xl">
              <strong>ASL (AgentScript)</strong> is a single-pass deterministic S-expression language designed from first principles for LLMs to generate, typecheck, and execute code with <strong>zero syntax repair loops</strong> and native WebAssembly isolation.
            </p>

            {/* 4 Core Language Feature Badges */}
            <div className="grid grid-cols-2 gap-3 max-w-lg font-mono text-xs text-left">
              <div className="p-3.5 rounded-xl border border-craft-200 dark:border-white/[0.08] bg-craft-50 dark:bg-white/[0.02] flex items-center gap-2.5 text-craft-800 dark:text-craft-200">
                <Code2 className="w-4 h-4 text-cyan-400 shrink-0" />
                <span>Single-Pass LL(1) S-Expr</span>
              </div>
              <div className="p-3.5 rounded-xl border border-craft-200 dark:border-white/[0.08] bg-craft-50 dark:bg-white/[0.02] flex items-center gap-2.5 text-craft-800 dark:text-craft-200">
                <ShieldCheck className="w-4 h-4 text-emerald-400 shrink-0" />
                <span>107 Closed Safe Builtins</span>
              </div>
              <div className="p-3.5 rounded-xl border border-craft-200 dark:border-white/[0.08] bg-craft-50 dark:bg-white/[0.02] flex items-center gap-2.5 text-craft-800 dark:text-craft-200">
                <Zap className="w-4 h-4 text-amber-400 shrink-0" />
                <span>–78% Prompt Token Load</span>
              </div>
              <div className="p-3.5 rounded-xl border border-craft-200 dark:border-white/[0.08] bg-craft-50 dark:bg-white/[0.02] flex items-center gap-2.5 text-craft-800 dark:text-craft-200">
                <Cpu className="w-4 h-4 text-purple-400 shrink-0" />
                <span>WASI Sandbox &lt;0.04ms</span>
              </div>
            </div>

            {/* Inline Precision Installer */}
            <div className="pt-2 max-w-lg">
              <div className="p-2 rounded-2xl border border-craft-300 dark:border-white/[0.12] bg-craft-100/90 dark:bg-white/[0.03] backdrop-blur-xl shadow-lg flex items-center justify-between gap-3">
                <div className="flex items-center gap-2.5 px-2 text-xs font-mono text-craft-600 dark:text-craft-400 truncate">
                  <Terminal className="w-4 h-4 text-cyan-400 shrink-0" />
                  <code className="text-craft-900 dark:text-cyan-300 font-bold select-all overflow-x-auto whitespace-nowrap">
                    curl -fsSL https://aslang.dev/install.sh | bash
                  </code>
                </div>
                <button
                  onClick={handleCopy}
                  className="px-4 py-2 rounded-xl bg-craft-900 dark:bg-white text-white dark:text-black font-mono text-xs font-bold hover:opacity-90 active:scale-95 transition-all flex items-center gap-1.5 shrink-0"
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

            {/* Clean Action Buttons */}
            <div className="flex flex-wrap gap-4 items-center pt-2 font-mono">
              <a
                href="#agent-way"
                className="px-7 py-3.5 rounded-full bg-cyan-400 hover:bg-cyan-300 text-black font-extrabold text-xs tracking-wider uppercase transition-all flex items-center gap-2"
              >
                <span>Language Specification</span>
                <ArrowRight className="w-4 h-4" />
              </a>
              <a
                href="#a2a-protocol"
                className="px-7 py-3.5 rounded-full bg-craft-100 dark:bg-white/[0.04] border border-craft-300 dark:border-white/[0.12] text-craft-900 dark:text-white text-xs tracking-wider uppercase hover:border-white/[0.25] transition-all flex items-center gap-2"
              >
                <span>A2A Wire Protocol</span>
              </a>
            </div>

          </div>

          {/* Right Column: Precision 3D Quantum Processor Core */}
          <div className="lg:col-span-5 relative flex items-center justify-center">
            <div className="relative w-full max-w-md lg:max-w-none group">
              <img
                src="/assets/images/quantum_core_scene.jpg"
                alt="Autonomous Agentic Quantum Processor Core"
                className="relative z-10 w-full h-auto rounded-3xl object-cover shadow-2xl transition-transform duration-700 ease-out"
              />

              {/* Orbiting Telemetry HUD Badge 1 */}
              <div className="absolute -top-4 -left-4 sm:top-6 sm:-left-6 z-20 p-3.5 rounded-2xl bg-white/95 dark:bg-[#0b0e14]/95 backdrop-blur-2xl border border-craft-200 dark:border-white/[0.12] shadow-xl text-left font-mono">
                <div className="flex items-center gap-2 text-[10px] text-cyan-400 font-bold tracking-wider">
                  <Code2 className="w-3.5 h-3.5" />
                  <span>DETERMINISTIC LANGUAGE</span>
                </div>
                <div className="text-xs font-bold text-craft-900 dark:text-white mt-1">
                  Zero Indentation Hallucinations
                </div>
                <div className="text-[10px] text-craft-500 dark:text-craft-400 mt-0.5">LL(1) S-Expression Grammar</div>
              </div>

              {/* Orbiting Telemetry HUD Badge 2 */}
              <div className="absolute -bottom-4 -right-4 sm:bottom-6 sm:-right-6 z-20 p-3.5 rounded-2xl bg-white/95 dark:bg-[#0b0e14]/95 backdrop-blur-2xl border border-craft-200 dark:border-white/[0.12] shadow-xl text-right font-mono">
                <div className="flex items-center justify-end gap-2 text-[10px] text-emerald-400 font-bold tracking-wider">
                  <ShieldCheck className="w-3.5 h-3.5" />
                  <span>NATIVE PROOF</span>
                </div>
                <div className="text-xs font-bold text-craft-900 dark:text-white mt-1">
                  WASI &lt;0.04ms Isolation
                </div>
                <div className="text-[10px] text-craft-500 dark:text-craft-400 mt-0.5">100% Spec Verified Gates</div>
              </div>
            </div>

          </div>

        </div>

      </div>
    </section>
  );
};
