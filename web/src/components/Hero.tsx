import React, { useEffect, useRef, useState } from 'react';
import { Check, Copy, ShieldCheck, Server, Network, FileText, Code2 } from 'lucide-react';
import { ChameleonWatermark } from './ui/Logo';

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
    <section id="top" className="relative pt-32 pb-20 sm:pt-36 sm:pb-24 overflow-hidden">
      {/* Large Schematic Chameleon Watermark hanging in the corner */}
      <div className="absolute -top-12 -right-12 sm:-top-8 sm:right-4 lg:right-12 w-72 sm:w-96 lg:w-[460px] h-72 sm:h-96 lg:h-[460px] pointer-events-none select-none opacity-15 sm:opacity-20 transition-opacity duration-700">
        <ChameleonWatermark className="w-full h-full" />
      </div>

      <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-10 lg:gap-12 items-center">
          
          {/* Main Hero Proposition */}
          <div className="lg:col-span-7 space-y-6">
            
            {/* Brand Title */}
            <div className="flex items-center gap-3.5 sm:gap-4 flex-wrap">
              <span className="font-sans font-extrabold text-ink text-3xl sm:text-4xl lg:text-5xl tracking-tight leading-none">
                Agent<span className="text-transparent bg-clip-text bg-gradient-to-r from-purple-400 to-indigo-300">Script</span>
              </span>
              <span className="inline-flex items-center p-2 rounded-2xl text-signal bg-signal/15 border border-signal/30 shadow-sm" title="Formally Verified Language Core">
                <ShieldCheck className="w-6 h-6 sm:w-7 sm:h-7" />
              </span>
            </div>

            {/* Main Headline */}
            <h1 className="text-display font-semibold text-ink text-balance tracking-tight leading-[1.08]">
              The Native Language for Autonomous Agents.{' '}
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-purple-400 via-purple-300 to-indigo-300">
                Multi-Runtime, Portable & Token-Efficient.
              </span>
            </h1>

            {/* Sub-proposition */}
            <p className="text-lead text-ink-2 max-w-prose leading-relaxed">
              Every existing language was designed for human typists with fragile indentation. AgentScript is engineered from first principles for autonomous models: single-pass balanced S-expressions, zero syntax repair loops, 57%–65% token savings over JSON, and verified multi-target compilation into Wasm, Rust, TypeScript, and Python.
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
              <span className="text-micro text-amber-300/90 font-mono px-2 py-0.5 rounded-full bg-amber-500/10 border border-amber-500/20">
                Core & Wire Protocol: Stable · Extended Tools: Under Development
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
                    57%–65% token compaction over verbose JSON/YAML, with a strict ≤ 2-token primitive ceiling.
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
                    Single source compiles with verified equivalence across Wasm, Rust, TypeScript, and Python.
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
                  Multi-Platform CLI Installation
                </label>
                <div className="flex items-center gap-2 p-2.5 rounded-2xl bg-ground border border-line focus-within:border-signal/50 transition-colors">
                  <span className="font-mono text-meta text-signal font-semibold select-none pl-2">$</span>
                  <input
                    id="install-input"
                    type="text"
                    readOnly
                    value={INSTALL_CMD}
                    className="flex-1 min-w-0 bg-transparent font-mono text-meta text-ink outline-none select-all"
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
                  <span className="text-lg font-bold text-signal font-mono">57%–65%</span>
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
