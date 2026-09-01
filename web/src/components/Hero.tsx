import React, { useEffect, useRef, useState } from 'react';
import { ArrowRight, Check, Copy, Cpu, ShieldCheck, Zap, Layers, Sparkles } from 'lucide-react';
import { Emblem } from './ui/Logo';

const INSTALL = 'curl -fsSL https://aslang.dev/install.sh | bash';
const TARGETS = [
  { name: 'WebAssembly', tag: 'WASI Preview1', hot: true },
  { name: 'Native Rust', tag: 'rustc clean' },
  { name: 'TypeScript', tag: 'Node & Browser' },
  { name: 'Go', tag: 'go vet clean' },
  { name: 'Python', tag: 'py_compile clean' },
  { name: 'Interpreter', tag: 'Reference Tree-Walk' },
];

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
    <section id="top" className="relative bg-ground pt-36 pb-24 sm:pt-44 sm:pb-32 overflow-hidden bg-dot-grid">
      {/* Ambient Atmospheric Lighting Glows */}
      <div className="glow-orb -top-32 -left-32 w-96 h-96" aria-hidden="true" />
      <div className="glow-orb top-1/2 -right-32 w-[32rem] h-[32rem]" aria-hidden="true" />

      <div className="max-w-6xl mx-auto px-6 lg:px-8 relative z-10">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-16 lg:gap-12 items-center">
          <div className="lg:col-span-6">
            <span className="inline-flex items-center gap-2.5 px-3 py-1 rounded-full border border-line bg-surface/80 backdrop-blur-md font-mono text-micro font-medium uppercase text-ink-3 shadow-e1">
              <span className="w-2 h-2 rounded-full bg-signal animate-pulse" aria-hidden />
              The Deterministic Agentic Language
            </span>

            <h1 className="mt-8 text-display font-bold text-ink text-balance tracking-tight">
              Code an agent can<br className="hidden sm:block" /> write correctly the
              <span className="text-signal"> first time.</span>
            </h1>

            <p className="mt-8 text-lead text-ink-2 max-w-prose leading-relaxed">
              AgentScript (ASL) is a high-performance S-expression language engineered exclusively for autonomous AI swarms. Single-pass LL(1) grammar, zero indentation hazards, and instant WebAssembly compilation — eliminating hallucinated brackets and multi-turn repair loops.
            </p>

            <div className="mt-10 flex flex-wrap items-center gap-3">
              <a
                href="#agent-way"
                className="inline-flex items-center gap-2 px-7 py-3.5 rounded-full bg-ink text-ground font-medium text-body hover:opacity-90 transition-all shadow-e2"
              >
                Explore the Architecture
                <ArrowRight className="w-4 h-4" aria-hidden />
              </a>
              <a
                href="#toolchain"
                className="inline-flex items-center gap-2 px-7 py-3.5 rounded-full border border-line-strong text-ink font-medium text-body hover:bg-surface transition-colors"
              >
                Multi-Target Engine
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
                className="shrink-0 inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-inset font-mono text-meta text-ink hover:text-signal transition-colors"
              >
                {copied ? <Check className="w-3.5 h-3.5 text-signal" aria-hidden /> : <Copy className="w-3.5 h-3.5" aria-hidden />}
                {copied ? 'Copied' : failed ? 'Select it' : 'Copy'}
              </button>
            </div>
          </div>

          {/* ASL Nano Visual Architecture Engine */}
          <div className="lg:col-span-6 lg:-mr-8 xl:-mr-12">
            <div className="relative rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e3 overflow-hidden p-6 sm:p-8">
              {/* Card Accent Ambient Gradient */}
              <div className="absolute top-0 right-0 w-64 h-64 bg-signal/10 rounded-full blur-3xl pointer-events-none" />

              <div className="flex items-center justify-between pb-6 border-b border-line">
                <div className="flex items-center gap-3">
                  <Emblem className="w-10 h-10 text-ink" />
                  <div>
                    <h2 className="font-sans font-bold text-ink text-base">ASL Nano Core</h2>
                    <p className="font-mono text-micro uppercase text-ink-3">Single-Pass LL(1) Engine</p>
                  </div>
                </div>
                <span className="px-3 py-1 rounded-full bg-signal/10 text-signal font-mono text-micro font-semibold uppercase">
                  v0.1.0 Ready
                </span>
              </div>

              <div className="mt-6 grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div className="p-4 rounded-2xl border border-line bg-ground/80 backdrop-blur-sm hover:border-line-strong transition-colors">
                  <div className="flex items-center gap-2 text-ink">
                    <Zap className="w-4 h-4 text-signal" />
                    <p className="font-mono text-micro uppercase font-medium text-ink-3">Zero Syntax Drift</p>
                  </div>
                  <p className="mt-2 text-h3 font-bold text-ink">100% 1-Pass</p>
                  <p className="mt-1 text-meta text-ink-2">Strict balanced parentheses. No invisible indentation ambiguity.</p>
                </div>

                <div className="p-4 rounded-2xl border border-line bg-ground/80 backdrop-blur-sm hover:border-line-strong transition-colors">
                  <div className="flex items-center gap-2 text-ink">
                    <ShieldCheck className="w-4 h-4 text-signal" />
                    <p className="font-mono text-micro uppercase font-medium text-ink-3">Differential Lockstep</p>
                  </div>
                  <p className="mt-2 text-h3 font-bold text-ink">0 Mismatch</p>
                  <p className="mt-1 text-meta text-ink-2">Identical execution across Rust, Wasm, Go, Python, TS & Interp.</p>
                </div>

                <div className="p-4 rounded-2xl border border-line bg-ground/80 backdrop-blur-sm hover:border-line-strong transition-colors">
                  <div className="flex items-center gap-2 text-ink">
                    <Layers className="w-4 h-4 text-signal" />
                    <p className="font-mono text-micro uppercase font-medium text-ink-3">Token Economy</p>
                  </div>
                  <p className="mt-2 text-h3 font-bold text-ink">-78.4% Tokens</p>
                  <p className="mt-1 text-meta text-ink-2">Interface compressor extracts pure typed signatures for prompts.</p>
                </div>

                <div className="p-4 rounded-2xl border border-line bg-ground/80 backdrop-blur-sm hover:border-line-strong transition-colors">
                  <div className="flex items-center gap-2 text-ink">
                    <Cpu className="w-4 h-4 text-signal" />
                    <p className="font-mono text-micro uppercase font-medium text-ink-3">In-Browser Wasm</p>
                  </div>
                  <p className="mt-2 text-h3 font-bold text-ink">&lt;0.04 ms</p>
                  <p className="mt-1 text-meta text-ink-2">Zero-server in-memory WASI sandbox with instant export execution.</p>
                </div>
              </div>

              <div className="mt-6 pt-5 border-t border-line flex items-center justify-between">
                <div className="flex items-center gap-2 font-mono text-micro uppercase text-ink-3">
                  <Sparkles className="w-3.5 h-3.5 text-signal" />
                  <span>Verified Standard Library</span>
                </div>
                <span className="font-mono text-micro text-signal font-bold">107/107 Builtins (100%)</span>
              </div>
            </div>
          </div>
        </div>

        {/* 6 Target Runtimes Grid */}
        <div className="mt-24 sm:mt-32">
          <div className="rule-fade" aria-hidden />
          <div className="mt-10 grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-4">
            {TARGETS.map((t) => (
              <div
                key={t.name}
                className="p-4 rounded-2xl border border-line bg-surface/60 backdrop-blur-md text-center hover:border-line-strong transition-all"
              >
                <p className="font-sans font-semibold text-body text-ink">{t.name}</p>
                <p className="mt-1 font-mono text-micro uppercase text-ink-3">{t.tag}</p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
};
