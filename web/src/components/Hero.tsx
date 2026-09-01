import React, { useEffect, useRef, useState } from 'react';
import { ArrowRight, Check, Copy, Cpu, ShieldCheck, Zap, Layers } from 'lucide-react';

const INSTALL = 'curl -fsSL https://aslang.dev/install.sh | bash';
const TARGETS = ['Python', 'Rust', 'WebAssembly', 'TypeScript', 'Go', 'Interpreter'];

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
    <section id="top" className="relative bg-ground pt-40 pb-24 sm:pt-48 sm:pb-32">
      <div className="max-w-6xl mx-auto px-6 lg:px-8">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-16 lg:gap-12 items-center">
          <div className="lg:col-span-6">
            <span className="inline-flex items-center gap-3 font-mono text-micro font-medium uppercase text-ink-3">
              <span className="w-1.5 h-1.5 rounded-full bg-signal" aria-hidden />
              A language engineered for the generator
            </span>

            <h1 className="mt-8 text-display font-semibold text-ink text-balance">
              Code an agent can<br className="hidden sm:block" /> write correctly the
              <span className="text-signal"> first time.</span>
            </h1>

            <p className="mt-8 text-lead text-ink-2 max-w-prose">
              AgentScript is an S-expression language with a single-pass LL(1) grammar exported exclusively in ASL Nano format. No significant whitespace to hallucinate and no bracket a parser has to guess at — so a model emits a program once instead of repairing it four times.
            </p>

            <div className="mt-10 flex flex-wrap items-center gap-3">
              <a
                href="#agent-way"
                className="inline-flex items-center gap-2 px-7 py-3.5 rounded-full bg-ink text-ground font-medium text-body hover:opacity-90 transition-opacity"
              >
                Read the idea
                <ArrowRight className="w-4 h-4" aria-hidden />
              </a>
              <a
                href="#toolchain"
                className="inline-flex items-center gap-2 px-7 py-3.5 rounded-full border border-line-strong text-ink font-medium text-body hover:bg-surface transition-colors"
              >
                The toolchain
              </a>
            </div>

            <div id="install" className="mt-8 flex items-center gap-3 max-w-lg">
              <code className="flex-1 min-w-0 font-mono text-meta text-ink-2 truncate select-all">
                <span className="text-ink-3">$ </span>
                {INSTALL}
              </code>
              <button
                type="button"
                onClick={copy}
                className="shrink-0 inline-flex items-center gap-1.5 font-mono text-meta text-ink-3 hover:text-ink transition-colors"
              >
                {copied ? <Check className="w-3.5 h-3.5" aria-hidden /> : <Copy className="w-3.5 h-3.5" aria-hidden />}
                {copied ? 'Copied' : failed ? 'Select it' : 'Copy'}
              </button>
              <span aria-live="polite" className="sr-only">
                {copied ? 'Install command copied to clipboard' : ''}
                {failed ? 'Clipboard unavailable. Select the command to copy it.' : ''}
              </span>
            </div>
          </div>

          {/* ASL Nano Engine Cockpit Card */}
          <div className="lg:col-span-6 lg:-mr-8 xl:-mr-16">
            <div className="rounded-2xl border border-line bg-surface shadow-e3 overflow-hidden p-6 sm:p-8">
              <div className="flex items-center justify-between pb-5 border-b border-line">
                <div className="flex items-center gap-2.5">
                  <Cpu className="w-4 h-4 text-signal" />
                  <span className="font-mono text-micro uppercase text-ink font-semibold">ASL Nano Architecture</span>
                </div>
                <span className="font-mono text-micro uppercase text-signal">Public Nano Protocol</span>
              </div>

              <div className="mt-6 grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div className="p-4 rounded-xl border border-line bg-ground">
                  <div className="flex items-center gap-2 text-ink">
                    <Zap className="w-4 h-4 text-signal" />
                    <p className="font-mono text-micro uppercase font-medium text-ink-3">Deterministic Parsing</p>
                  </div>
                  <p className="mt-2 text-h3 font-semibold text-ink">Single-Pass</p>
                  <p className="mt-1 text-meta text-ink-2">Strict LL(1) grammar with zero ambiguous bracket branches.</p>
                </div>

                <div className="p-4 rounded-xl border border-line bg-ground">
                  <div className="flex items-center gap-2 text-ink">
                    <ShieldCheck className="w-4 h-4 text-signal" />
                    <p className="font-mono text-micro uppercase font-medium text-ink-3">Differential Gate</p>
                  </div>
                  <p className="mt-2 text-h3 font-semibold text-ink">0 Drift</p>
                  <p className="mt-1 text-meta text-ink-2">Identical stdout, stderr, and exit codes across 6 runtimes.</p>
                </div>

                <div className="p-4 rounded-xl border border-line bg-ground">
                  <div className="flex items-center gap-2 text-ink">
                    <Layers className="w-4 h-4 text-signal" />
                    <p className="font-mono text-micro uppercase font-medium text-ink-3">Interface Compression</p>
                  </div>
                  <p className="mt-2 text-h3 font-semibold text-ink">-78.4% Tokens</p>
                  <p className="mt-1 text-meta text-ink-2">ASL Nano signature compressor removes implementation bloat.</p>
                </div>

                <div className="p-4 rounded-xl border border-line bg-ground">
                  <div className="flex items-center gap-2 text-ink">
                    <Cpu className="w-4 h-4 text-signal" />
                    <p className="font-mono text-micro uppercase font-medium text-ink-3">Edge Target</p>
                  </div>
                  <p className="mt-2 text-h3 font-semibold text-ink">&lt;0.04 ms</p>
                  <p className="mt-1 text-meta text-ink-2">Instant in-memory WebAssembly preview1 runtime.</p>
                </div>
              </div>

              <div className="mt-6 pt-5 border-t border-line flex items-center justify-between">
                <span className="font-mono text-micro uppercase text-ink-3">Standard Library</span>
                <span className="font-mono text-micro text-signal font-medium">107/107 Executed Builtins (100%)</span>
              </div>
            </div>
          </div>
        </div>

        {/* One source, six targets */}
        <div className="mt-24 sm:mt-32">
          <div className="rule-fade" aria-hidden />
          <div className="mt-8 flex flex-wrap items-baseline gap-x-10 gap-y-4">
            <span className="font-mono text-micro uppercase text-ink-3">One source compiles to</span>
            {TARGETS.map((t) => (
              <span key={t} className="font-mono text-meta text-ink-2">
                {t}
              </span>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
};
