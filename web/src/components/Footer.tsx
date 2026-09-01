import React from 'react';
import { Logo } from './ui/Logo';

export const Footer: React.FC = () => (
  <footer className="py-16 border-t border-line bg-sunken">
    <div className="max-w-6xl mx-auto px-6 lg:px-8 flex flex-col md:flex-row md:items-center justify-between gap-8">
      <div className="flex items-center gap-3">
        <Logo className="w-8 h-8 text-ink" />
        <span>
          <span className="block font-sans font-semibold text-ink text-brand">
            ASL — AgentScript Language
          </span>
          <span className="block font-mono text-meta text-ink-3">aslang.dev</span>
        </span>
      </div>

      <nav aria-label="Footer" className="flex flex-wrap items-center gap-6 font-mono text-meta">
        <a href="https://github.com/genseam/asl" target="_blank" rel="noreferrer" className="text-ink-2 hover:text-ink transition-colors">
          GitHub
        </a>
        <a href="/llms.txt" className="text-ink-2 hover:text-ink transition-colors">
          llms.txt
        </a>
        <a href="/llms-full.txt" className="text-ink-2 hover:text-ink transition-colors">
          llms-full.txt
        </a>
      </nav>
    </div>

    <p className="max-w-6xl mx-auto px-6 lg:px-8 mt-10 pt-6 border-t border-line font-mono text-meta text-ink-3">
      MIT licensed. Built for the agentic era.
    </p>
  </footer>
);
