import React, { useEffect, useRef, useState } from 'react';
import { ArrowRight, Check, Copy, ShieldCheck, Server, Network, Sparkles } from 'lucide-react';
import { ChameleonALogo, ChameleonSchematic } from './ui/Logo';

const INSTALL_CMD = 'curl -sSL aslang.dev/install | sh';
const TARGETS = ['WebAssembly', 'Rust', 'TypeScript', 'Go', 'Python'];

export const Hero: React.FC = () => {
  const [copied, setCopied] = useState(false);
  const timer = useRef<number | undefined>(undefined);

  useEffect(() => () => window.clearTimeout(timer.current), []);

  const copy = async () => {
    let ok = true;
    try {
      await navigator.clipboard.writeText(INSTALL_CMD);
    } catch {
      ok = false;
    }
    setCopied(ok);
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setCopied(false), 2000);
  };

  return (
    <section id="top" className="relative bg-ground pt-32 pb-20 sm:pt-40 sm:pb-28 overflow-hidden bg-blueprint-grid">
      {/* Ambient background glow and watermark chameleon */}
      <div className="absolute top-1/4 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[700px] h-[500px] bg-purple-600/10 dark:bg-purple-900/20 blur-[130px] rounded-full pointer-events-none" />

      {/* Large Schematic Chameleon Watermark (as shown in reference design mockup) */}
      <div className="absolute -top-10 -left-12 sm:left-4 lg:left-12 w-80 sm:w-96 lg:w-[460px] h-auto opacity-20 dark:opacity-25 pointer-events-none select-none transition-opacity">
        <ChameleonSchematic className="w-full h-auto text-signal" strokeWidth={2.2} glow={true} />
      </div>

      <div className="max-w-6xl mx-auto px-5 sm:px-6 lg:px-8 relative z-10">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-10 lg:gap-12 items-center">
          
          {/* Main Hero Proposition */}
          <div className="lg:col-span-7 space-y-6">
            
            {/* Brand Emblem & Name */}
            <div className="flex items-center gap-3.5">
              <div className="p-2 rounded-2xl bg-surface/90 border border-line shadow-e2 flex items-center justify-center">
                <ChameleonALogo className="w-9 h-9 text-signal" />
              </div>
              <div className="flex items-center gap-2">
                <span className="font-sans font-bold text-ink text-2xl sm:text-3xl tracking-tight">
                  aslang<span className="text-signal">.dev</span>
                </span>
                <span className="inline-flex items-center p-1 rounded-full text-signal bg-signal/10 border border-signal/20">
                  <ShieldCheck className="w-4 h-4" />
                </span>
              </div>
            </div>

            {/* Main Headline */}
            <h1 className="text-display font-semibold text-ink text-balance tracking-tight leading-[1.08]">
              Design, Verify, and Scale distributed infrastructure with{' '}
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-purple-400 via-purple-300 to-indigo-300">
                formal precision.
              </span>
            </h1>

            {/* Sub-proposition */}
            <p className="text-lead text-ink-2 max-w-prose leading-relaxed">
              Every existing language was designed for human typists. AgentScript is engineered from first principles for autonomous models: balanced S-expressions, deterministic execution, zero syntax repairs, and unified multi-target compilation.
            </p>

            {/* Two Side-by-Side Blueprint Sub-cards [A] and [B] */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-2">
              
              {/* Sub-card A: Reliable System Glue */}
              <div className="p-4 rounded-2xl border border-line bg-surface/80 backdrop-blur-md shadow-sm hover:border-signal/30 transition-all flex items-start gap-3.5">
                <div className="flex flex-col items-center gap-2 shrink-0">
                  <span className="w-6 h-6 rounded-full bg-surface border border-line font-mono text-micro font-semibold text-signal flex items-center justify-center">
                    A
                  </span>
                  <div className="p-2 rounded-xl bg-inset border border-line/60">
                    <Server className="w-5 h-5 text-signal" />
                  </div>
                </div>
                <div>
                  <h3 className="font-semibold text-ink text-body">Reliable System Glue</h3>
                  <p className="mt-1 text-meta text-ink-2 leading-snug">
                    Scalable, formally connected nodes with provable invariants and wire-safe S-expressions.
                  </p>
                </div>
              </div>

              {/* Sub-card B: Verify Composition & Interfaces */}
              <div className="p-4 rounded-2xl border border-line bg-surface/80 backdrop-blur-md shadow-sm hover:border-signal/30 transition-all flex items-start gap-3.5">
                <div className="flex flex-col items-center gap-2 shrink-0">
                  <span className="w-6 h-6 rounded-full bg-surface border border-line font-mono text-micro font-semibold text-signal flex items-center justify-center">
                    B
                  </span>
                  <div className="p-2 rounded-xl bg-inset border border-line/60">
                    <Network className="w-5 h-5 text-signal" />
                  </div>
                </div>
                <div>
                  <h3 className="font-semibold text-ink text-body">Verify Composition</h3>
                  <p className="mt-1 text-meta text-ink-2 leading-snug">
                    Formally proved states, static types, and certified runtime determinism across backends.
                  </p>
                </div>
              </div>

            </div>

            {/* Call to Actions */}
            <div className="pt-2 flex flex-wrap items-center gap-3.5">
              <a
                href="#capabilities"
                className="inline-flex items-center gap-2 px-6 py-3 rounded-full bg-gradient-to-r from-purple-700 to-indigo-600 hover:from-purple-600 hover:to-indigo-500 text-white font-medium text-body shadow-e2 hover:shadow-purple-500/20 transition-all"
              >
                Key Capabilities
                <ArrowRight className="w-4 h-4" />
              </a>
              <a
                href="#agent-way"
                className="inline-flex items-center gap-2 px-6 py-3 rounded-full border border-line bg-surface/80 hover:bg-inset text-ink font-medium text-body transition-colors"
              >
                The Agent Way
              </a>
            </div>

          </div>

          {/* Right Card: GET STARTED NOW (Mockup faithful design) */}
          <div className="lg:col-span-5">
            <div className="relative rounded-3xl border border-line bg-surface/90 backdrop-blur-2xl shadow-e4 p-6 sm:p-8 space-y-6">
              
              <div className="space-y-1">
                <span className="font-mono text-micro uppercase tracking-widest text-signal font-semibold">
                  GET STARTED NOW
                </span>
                <h2 className="text-xl sm:text-2xl font-bold text-ink">
                  Install the latest CLI tool.
                </h2>
                <p className="text-meta text-ink-2">
                  Zero external dependencies. Precompiled binaries for macOS, Linux, and Windows.
                </p>
              </div>

              {/* Terminal Code Snippet with Copy */}
              <div className="relative p-3.5 rounded-2xl bg-ground border border-line/80 shadow-inner group">
                <div className="flex items-center justify-between gap-3">
                  <code className="font-mono text-meta text-ink-2 select-all overflow-x-auto whitespace-nowrap scrollbar-none">
                    <span className="text-signal font-semibold">$ </span>
                    {INSTALL_CMD}
                  </code>
                  <button
                    type="button"
                    onClick={copy}
                    className="shrink-0 p-2 rounded-xl bg-inset hover:bg-surface border border-line text-ink-2 hover:text-signal transition-colors"
                    aria-label="Copy install command"
                  >
                    {copied ? (
                      <Check className="w-4 h-4 text-signal" />
                    ) : (
                      <Copy className="w-4 h-4" />
                    )}
                  </button>
                </div>
                {copied && (
                  <span className="absolute -top-7 right-3 px-2 py-0.5 rounded-full bg-signal text-ground font-mono text-[11px] font-medium shadow">
                    Copied!
                  </span>
                )}
              </div>

              <div className="pt-2 border-t border-line/60 flex items-center justify-between">
                <a
                  href="#toolchain"
                  className="font-mono text-meta text-signal hover:underline inline-flex items-center gap-1 font-medium"
                >
                  Explore installation guides
                  <ArrowRight className="w-3.5 h-3.5" />
                </a>
              </div>

              {/* Target Environments Pill Row */}
              <div className="pt-2">
                <div className="flex items-center gap-2 font-mono text-micro uppercase text-ink-3 mb-2.5">
                  <Sparkles className="w-3.5 h-3.5 text-signal" />
                  <span>Cross-Runtime Targets</span>
                </div>
                <div className="flex flex-wrap gap-1.5">
                  {TARGETS.map((target) => (
                    <span
                      key={target}
                      className="px-2.5 py-1 rounded-full border border-line bg-inset font-mono text-[11px] text-ink-2"
                    >
                      {target}
                    </span>
                  ))}
                </div>
              </div>

            </div>
          </div>

        </div>
      </div>
    </section>
  );
};
