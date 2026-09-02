import React, { useEffect, useRef, useState } from 'react';
import { ArrowRight, Check, Copy, Zap, ShieldCheck, Layers, Cpu, Sparkles } from 'lucide-react';
import { Emblem } from './ui/Logo';

const INSTALL = 'curl -fsSL https://aslang.dev/install.sh | bash';
const TARGETS = ['WebAssembly', 'Rust', 'TypeScript', 'Go', 'Python'];

export const Hero: React.FC = () => {
  const [copied, setCopied] = useState(false);
  const [failed, setFailed] = useState(false);
  const timer = useRef<number | undefined>(undefined);

  useEffect(() => () => window.clearTimeout(timer.current), []);

  const copy = async () => {
    let ok = true;
    try {
      await navigator.clipboard.writeText(INSTALL);
    } catch {
      ok = false;
    }
    setCopied(ok);
    setFailed(!ok);
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      setCopied(false);
      setFailed(false);
    }, 2000);
  };

  return (
    <section id="top" className="relative bg-ground pt-36 pb-20 sm:pt-44 sm:pb-28 overflow-hidden bg-dot-grid">

      <div className="max-w-6xl mx-auto px-6 lg:px-8 relative z-10">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12 lg:gap-12 items-center">
          <div className="lg:col-span-6">
            <span className="inline-flex items-center gap-2.5 px-3.5 py-1 rounded-full border border-line bg-surface/80 backdrop-blur-md font-mono text-micro font-medium uppercase text-ink-3 shadow-e1">
              <span className="w-2 h-2 rounded-full bg-signal" aria-hidden />
              The Language for Autonomous Agents
            </span>

            <h1 className="mt-7 text-display font-semibold text-ink text-balance tracking-tight">
              Code that agents write right the
              <span className="text-signal"> first time.</span>
            </h1>

            <p className="mt-6 text-lead text-ink-2 max-w-prose leading-relaxed">
              Every existing language was designed for human typists. AgentScript is engineered from first principles for model generation: balanced, deterministic, compact, and eliminating syntax errors and repair loops by design.
            </p>

            <div className="mt-9 flex flex-wrap items-center gap-3.5">
              <a
                href="#agent-way"
                className="inline-flex items-center gap-2 px-7 py-3.5 rounded-full bg-ink text-ground font-medium text-body hover:opacity-90 transition-all shadow-e2"
              >
                Why AgentScript
                <ArrowRight className="w-4 h-4" aria-hidden />
              </a>
              <a
                href="#toolchain"
                className="inline-flex items-center gap-2 px-7 py-3.5 rounded-full border border-line-strong text-ink font-medium text-body hover:bg-surface transition-colors"
              >
                The Toolchain
              </a>
            </div>

            <div id="install" className="mt-8 flex items-center gap-3 max-w-lg p-2 rounded-2xl border border-line bg-surface/90 backdrop-blur-md shadow-e1">
              <code className="flex-1 min-w-0 font-mono text-meta text-ink-2 px-2 truncate select-all">
                <span className="text-signal font-semibold">$ </span>
                {INSTALL}
              </code>
              <button
                type="button"
                onClick={copy}
                className="shrink-0 inline-flex items-center gap-1.5 px-3 py-1.5 rounded-2xl bg-inset font-mono text-meta text-ink hover:text-signal transition-colors"
              >
                {copied ? <Check className="w-3.5 h-3.5 text-signal" aria-hidden /> : <Copy className="w-3.5 h-3.5" aria-hidden />}
                {copied ? 'Copied' : failed ? 'Select it' : 'Copy'}
              </button>
            </div>
          </div>

          {/* Architectural Telemetry Cockpit */}
          <div className="lg:col-span-6 lg:-mr-4 xl:-mr-8">
            <div className="relative rounded-2xl border border-line bg-surface/90 backdrop-blur-xl shadow-e3 overflow-hidden p-6 sm:p-8">
                            <div className="flex items-center justify-between pb-6 border-b border-line">
                <div className="flex items-center gap-3.5">
                  <Emblem className="w-9 h-9 text-ink" />
                  <div>
                    <h2 className="font-sans font-semibold text-ink text-base">AgentScript Core</h2>
                    <p className="font-mono text-micro uppercase text-ink-3">Generation Engine</p>
                  </div>
                </div>
                <span className="px-3 py-1 rounded-full bg-signal/10 text-signal font-mono text-micro font-semibold uppercase">
                  Active
                </span>
              </div>

              <div className="mt-6 grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div className="p-4 rounded-2xl border border-line bg-ground/70 backdrop-blur-sm">
                  <div className="flex items-center gap-2 text-ink">
                    <Zap className="w-4 h-4 text-ink-3" />
                    <p className="font-mono text-micro uppercase font-medium text-ink-3">Grammar Safety</p>
                  </div>
                  <p className="mt-2 text-h3 font-semibold text-ink">Deterministic</p>
                  <p className="mt-1 text-meta text-ink-2">Strict balanced structure. Zero indentation bugs or ambiguous syntax trees.</p>
                </div>

                <div className="p-4 rounded-2xl border border-line bg-ground/70 backdrop-blur-sm">
                  <div className="flex items-center gap-2 text-ink">
                    <Layers className="w-4 h-4 text-ink-3" />
                    <p className="font-mono text-micro uppercase font-medium text-ink-3">Context Efficiency</p>
                  </div>
                  <p className="mt-2 text-h3 font-semibold text-ink">Ultra-Compact</p>
                  <p className="mt-1 text-meta text-ink-2">Drastically lower token overhead compared to verbose code or nested JSON.</p>
                </div>

                <div className="p-4 rounded-2xl border border-line bg-ground/70 backdrop-blur-sm">
                  <div className="flex items-center gap-2 text-ink">
                    <ShieldCheck className="w-4 h-4 text-ink-3" />
                    <p className="font-mono text-micro uppercase font-medium text-ink-3">Execution</p>
                  </div>
                  <p className="mt-2 text-h3 font-semibold text-ink">Verified</p>
                  <p className="mt-1 text-meta text-ink-2">Programs produce consistent semantics regardless of the deployment target.</p>
                </div>

                <div className="p-4 rounded-2xl border border-line bg-ground/70 backdrop-blur-sm">
                  <div className="flex items-center gap-2 text-ink">
                    <Cpu className="w-4 h-4 text-ink-3" />
                    <p className="font-mono text-micro uppercase font-medium text-ink-3">Toolchain</p>
                  </div>
                  <p className="mt-2 text-h3 font-semibold text-ink">Universal</p>
                  <p className="mt-1 text-meta text-ink-2">Compiles seamlessly to native binaries, web runtimes, and agent tools.</p>
                </div>
              </div>

              <div className="mt-6 pt-5 border-t border-line flex items-center justify-between">
                <div className="flex items-center gap-2 font-mono text-micro uppercase text-ink-3">
                  <Sparkles className="w-3.5 h-3.5 text-ink-3" />
                  <span>Target Platforms</span>
                </div>
                <div className="flex items-center gap-2">
                  {TARGETS.map((t) => (
                    <span key={t} className="font-mono text-micro text-ink-2 px-2 py-0.5 rounded-full bg-inset border border-line">
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
