import React from 'react';
import { Logo } from './ui/Logo';

export const Footer: React.FC = () => (
  <footer className="py-14 border-t border-line bg-sunken/60">
    <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 flex flex-col md:flex-row md:items-center justify-between gap-6">
      <div className="flex items-center gap-3">
        <Logo className="w-7 h-7 text-signal" />
        <span className="flex items-baseline gap-2">
          <span className="font-sans font-semibold text-ink text-brand">
            aslang<span className="text-signal">.dev</span>
          </span>
          <span className="font-mono text-meta text-ink-3">ASL Agent Core</span>
        </span>
      </div>

      <nav aria-label="Footer" className="flex flex-wrap items-center gap-6 font-mono text-meta">
        <a href="#agent-way" className="text-ink-2 hover:text-ink transition-colors">
          Specification
        </a>
        <a href="#capabilities" className="text-ink-2 hover:text-ink transition-colors">
          Capabilities
        </a>
        <a href="#toolchain" className="text-ink-2 hover:text-ink transition-colors">
          Ecosystem
        </a>
        <a href="https://github.com/genseam/asl" target="_blank" rel="noreferrer" className="text-ink-2 hover:text-ink transition-colors">
          GitHub
        </a>
        <a href="/llms.txt" className="text-ink-2 hover:text-ink transition-colors">
          Security
        </a>
      </nav>

      <a
        href="/llms.txt"
        className="font-mono text-micro text-ink-3 hover:text-signal transition-colors flex items-center gap-1.5"
      >
        <span className="w-1.5 h-1.5 rounded-full bg-signal" />
        <span>Agent Spec (llms.txt)</span>
      </a>
    </div>

    <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 mt-8 pt-6 border-t border-line/60 flex flex-col sm:flex-row items-center justify-between gap-4 font-mono text-micro text-ink-3">
      <p>MIT licensed. Single-pass S-expression language for autonomous agents.</p>
      <p>Formally verified determinism across runtimes.</p>
    </div>
  </footer>
);
