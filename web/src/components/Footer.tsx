import React, { useState } from 'react';
import { Logo } from './ui/Logo';
import { Link } from '../lib/router';

export const Footer: React.FC = () => {
  const [clickedCount, setClickedCount] = useState(0);

  const easterEggQuotes = [
    "Psst! You made it all the way to the end of the runtime.",
    "Formally verified from head to tail! 🦎",
    "Zero heap allocations down here.",
    "Watching over your AST trees from this branch.",
    "Deterministic execution reached EOF."
  ];

  return (
    <footer className="relative pt-12 pb-14 border-t border-line bg-sunken/60">
      {/* Chameleon Mascot: Sitting in the footer */}
      <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 mb-8 flex flex-col items-center justify-center">
        <button
          type="button"
          onClick={() => setClickedCount((prev) => prev + 1)}
          className="group relative flex flex-col items-center focus:outline-none cursor-pointer"
          title="Leon the Chameleon"
          aria-label="AgentScript Mascot Chameleon"
        >
          {/* Emergent Speech Bubble on hover or click */}
          <div className="opacity-0 group-hover:opacity-100 transition-all duration-300 transform translate-y-1 group-hover:translate-y-0 mb-3 px-3.5 py-1.5 rounded-2xl bg-surface/95 backdrop-blur-xl border border-line shadow-e2 text-micro font-mono text-ink flex items-center gap-2 pointer-events-none">
            <span className="w-1.5 h-1.5 rounded-full bg-signal animate-pulse shrink-0" />
            <span>{easterEggQuotes[clickedCount % easterEggQuotes.length]}</span>
          </div>

          <div className="relative">
            {/* Subtle atmospheric ambient glow behind chameleon */}
            <div className="absolute inset-0 rounded-full bg-purple-500/15 blur-2xl group-hover:bg-purple-500/25 transition-all scale-110 pointer-events-none" />
            
            <img
              src="/chameleon.png"
              alt="AgentScript Mascot Chameleon"
              width="130"
              height="138"
              className="relative z-10 w-24 sm:w-28 h-auto select-none rounded-2xl transition-all duration-300 transform group-hover:scale-105 group-active:scale-95 shadow-md"
            />
          </div>

          <span className="mt-2 font-mono text-2xs uppercase tracking-widest text-ink-3 group-hover:text-signal transition-colors">
            Leon the Chameleon
          </span>
        </button>
      </div>

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
          <Link to="/docs" className="text-ink-2 hover:text-ink transition-colors">
            Documentation
          </Link>
          <Link to="/blog" className="text-ink-2 hover:text-ink transition-colors">
            Blog
          </Link>
          <Link to="/ecosystem" className="text-ink-2 hover:text-ink transition-colors">
            Ecosystem
          </Link>
          <Link to="/roadmap" className="text-ink-2 hover:text-ink transition-colors">
            Roadmap
          </Link>
          <a href="https://github.com/genseam/asl" target="_blank" rel="noreferrer" className="text-ink-2 hover:text-ink transition-colors">
            GitHub
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
};
