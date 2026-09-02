import React, { useEffect, useRef, useState } from 'react';
import { Check, Copy, ShieldCheck, Server, Network, FileText, Code2 } from 'lucide-react';
import { ChameleonALogo, ChameleonSchematic } from './ui/Logo';

const INSTALL_CMD = 'curl -sSL aslang.dev/install | sh';
const TARGETS = ['WebAssembly', 'Rust', 'TypeScript', 'Go', 'Python', 'SQL'];

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
    <section id="top" className="relative bg-ground pt-32 pb-20 sm:pt-36 sm:pb-24 overflow-hidden bg-blueprint-grid">
      {/* Ambient background glow and watermark chameleon */}
      <div className="absolute top-1/4 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[800px] h-[550px] bg-purple-600/10 dark:bg-purple-900/20 blur-[140px] rounded-full pointer-events-none" />

      {/* Isometric 3D Circuit Background Grid (matching design mockup) */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none opacity-40 select-none">
        <svg
          className="w-full h-full text-purple-500/20"
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 1440 900"
          fill="none"
        >
          <g stroke="currentColor" strokeWidth="1" strokeDasharray="4 8">
            {/* Perspective Ray Lines */}
            <line x1="720" y1="200" x2="0" y2="900" />
            <line x1="720" y1="200" x2="360" y2="900" />
            <line x1="720" y1="200" x2="720" y2="900" />
            <line x1="720" y1="200" x2="1080" y2="900" />
            <line x1="720" y1="200" x2="1440" y2="900" />
            
            {/* Concentric Horizon Arcs */}
            <ellipse cx="720" cy="200" rx="400" ry="120" />
            <ellipse cx="720" cy="200" rx="700" ry="240" />
            <ellipse cx="720" cy="200" rx="1050" ry="380" />
          </g>

          {/* Glowing Circuit Node Dots */}
          <circle cx="580" cy="380" r="3" fill="#c084fc" className="animate-pulse" />
          <circle cx="860" cy="380" r="3" fill="#a855f7" className="animate-pulse" />
          <circle cx="420" cy="520" r="3.5" fill="#c084fc" />
          <circle cx="1020" cy="520" r="3.5" fill="#a855f7" />
          <circle cx="720" cy="580" r="4" fill="#d8b4fe" />
        </svg>
      </div>

      {/* Large Schematic Chameleon Watermark (as shown in reference design mockup) */}
      <div className="absolute -top-6 -left-12 sm:left-4 lg:left-12 w-80 sm:w-96 lg:w-[480px] h-auto opacity-20 dark:opacity-25 pointer-events-none select-none transition-opacity">
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
              The Native Language for Autonomous Agents.{' '}
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-purple-400 via-purple-300 to-indigo-300">
                Universal, Safe & Token-Efficient.
              </span>
            </h1>

            {/* Sub-proposition */}
            <p className="text-lead text-ink-2 max-w-prose leading-relaxed">
              Every existing language was designed for human typists with fragile indentation. AgentScript is engineered from first principles for autonomous models: single-pass balanced S-expressions, zero syntax repair loops, 70% token savings, and verified multi-target compilation into Wasm, Rust, TypeScript, Go, Python, and SQL.
            </p>

            {/* Prominent Agent Specification Links right in Hero */}
            <div className="flex flex-wrap items-center gap-3 pt-1">
              <span className="font-mono text-micro text-ink-3 uppercase font-semibold mr-1">
                Model Spec:
              </span>
              <a
                href="/llms.txt"
                target="_blank"
                rel="noreferrer"
                className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-full border border-signal/40 bg-signal/10 text-signal hover:bg-signal/20 font-mono text-micro font-medium transition-colors"
              >
                <FileText className="w-3.5 h-3.5" />
                <span>/llms.txt</span>
              </a>
              <a
                href="/llms-full.txt"
                target="_blank"
                rel="noreferrer"
                className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-full border border-line bg-surface/80 text-ink-2 hover:text-ink hover:border-signal/30 font-mono text-micro font-medium transition-colors"
              >
                <Code2 className="w-3.5 h-3.5" />
                <span>/llms-full.txt</span>
              </a>
              <span className="text-micro text-ink-3 font-mono">
                · Zero-leak Wasm sandbox
              </span>
            </div>

            {/* Two Side-by-Side Blueprint Sub-cards [A] and [B] */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-2">
              
              {/* Sub-card A: Reliable System Glue */}
              <div className="p-4 rounded-2xl border border-line bg-surface/80 backdrop-blur-md shadow-sm hover:border-signal/30 transition-all flex items-start gap-3.5">
                <div className="flex flex-col items-center gap-2 shrink-0">
                  <span className="font-mono text-micro font-bold text-signal px-1.5 py-0.5 rounded bg-signal/10 border border-signal/20">
                    [A]
                  </span>
                  <div className="p-2 rounded-xl bg-inset border border-line text-signal">
                    <Server className="w-5 h-5" />
                  </div>
                </div>
                <div>
                  <h3 className="font-sans font-bold text-ink text-sm">
                    Token & Time Economy
                  </h3>
                  <p className="text-meta text-ink-3 mt-1 leading-relaxed">
                    Saves up to 70% prompt tokens compared to verbose JSON/YAML. Frees model attention budget for reasoning.
                  </p>
                </div>
              </div>

              {/* Sub-card B: Verify Composition */}
              <div className="p-4 rounded-2xl border border-line bg-surface/80 backdrop-blur-md shadow-sm hover:border-signal/30 transition-all flex items-start gap-3.5">
                <div className="flex flex-col items-center gap-2 shrink-0">
                  <span className="font-mono text-micro font-bold text-signal px-1.5 py-0.5 rounded bg-signal/10 border border-signal/20">
                    [B]
                  </span>
                  <div className="p-2 rounded-xl bg-inset border border-line text-signal">
                    <Network className="w-5 h-5" />
                  </div>
                </div>
                <div>
                  <h3 className="font-sans font-bold text-ink text-sm">
                    Differential Verification
                  </h3>
                  <p className="text-meta text-ink-3 mt-1 leading-relaxed">
                    Single source compiles with verified equivalence across Wasm, Rust, TypeScript, Go, Python, and SQL.
                  </p>
                </div>
              </div>

            </div>
          </div>

          {/* Right Card: High-Density Blueprint Terminal & Install Box */}
          <div className="lg:col-span-5">
            <div className="p-6 sm:p-7 rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e3 relative overflow-hidden">
              
              {/* Corner Drafting Marks */}
              <div className="absolute top-2 left-2 font-mono text-[9px] text-ink-3 opacity-40">
                +12.00 / ASL
              </div>
              <div className="absolute bottom-2 right-2 font-mono text-[9px] text-ink-3 opacity-40">
                CORE-SPEC-V1
              </div>

              <div className="flex items-center justify-between pb-4 border-b border-line">
                <div className="flex items-center gap-2">
                  <div className="w-2.5 h-2.5 rounded-full bg-red-500/80" />
                  <div className="w-2.5 h-2.5 rounded-full bg-yellow-500/80" />
                  <div className="w-2.5 h-2.5 rounded-full bg-green-500/80" />
                  <span className="ml-2 font-mono text-micro text-ink-3">asl-cli</span>
                </div>
                <span className="font-mono text-micro font-semibold text-signal uppercase">
                  GET STARTED NOW
                </span>
              </div>

              {/* Install Terminal Box */}
              <div className="mt-5">
                <label htmlFor="install-input" className="font-mono text-micro uppercase text-ink-3 font-semibold block mb-2">
                  Universal CLI Installation
                </label>
                <div className="flex items-center gap-2 p-2.5 rounded-2xl bg-ground border border-line focus-within:border-signal/50 transition-colors">
                  <span className="font-mono text-meta text-signal font-semibold select-none pl-2">$</span>
                  <input
                    id="install-input"
                    type="text"
                    readOnly
                    value={INSTALL_CMD}
                    className="flex-1 bg-transparent font-mono text-meta text-ink outline-none select-all"
                  />
                  <button
                    type="button"
                    onClick={copy}
                    aria-label="Copy installation command"
                    className="p-2 rounded-xl bg-surface hover:bg-inset text-ink-2 hover:text-ink border border-line transition-all"
                  >
                    {copied ? <Check className="w-4 h-4 text-signal" /> : <Copy className="w-4 h-4" />}
                  </button>
                </div>
              </div>

              {/* Value Metrics Quad */}
              <div className="mt-6 pt-5 border-t border-line/60 grid grid-cols-2 gap-3">
                <div className="p-3 rounded-2xl bg-inset/70 border border-line/60">
                  <span className="font-mono text-micro text-ink-3 uppercase block">Token Reduction</span>
                  <span className="text-lg font-bold text-signal font-mono">-70% Bloat</span>
                </div>
                <div className="p-3 rounded-2xl bg-inset/70 border border-line/60">
                  <span className="font-mono text-micro text-ink-3 uppercase block">Syntax Errors</span>
                  <span className="text-lg font-bold text-green-400 font-mono">0 Retries</span>
                </div>
                <div className="p-3 rounded-2xl bg-inset/70 border border-line/60">
                  <span className="font-mono text-micro text-ink-3 uppercase block">Wasm Sandbox</span>
                  <span className="text-lg font-bold text-ink font-mono">&lt;0.05ms</span>
                </div>
                <div className="p-3 rounded-2xl bg-inset/70 border border-line/60">
                  <span className="font-mono text-micro text-ink-3 uppercase block">Targets</span>
                  <span className="text-lg font-bold text-ink font-mono">6 Verified</span>
                </div>
              </div>

              {/* Cross-Runtime Target Badges */}
              <div className="mt-5 pt-4 border-t border-line/60">
                <span className="font-mono text-micro uppercase text-ink-3 block mb-2">
                  Verified Compile Targets:
                </span>
                <div className="flex flex-wrap gap-1.5">
                  {TARGETS.map((t) => (
                    <span
                      key={t}
                      className="px-2.5 py-1 rounded-full border border-line bg-inset font-mono text-micro text-ink-2"
                    >
                      {t}
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
