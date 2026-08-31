import React from 'react';
import { Terminal, Shield } from 'lucide-react';

export const Footer: React.FC = () => {
  return (
    <footer className="py-12 border-t border-craft-800 bg-craft-950 text-craft-400 font-mono text-xs">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex flex-col md:flex-row items-center justify-between gap-6">
        <div className="flex items-center gap-3">
          <div className="h-7 w-7 rounded bg-craft-900 border border-craft-700 flex items-center justify-center text-craft-accent font-bold">
            λ
          </div>
          <div>
            <div className="text-craft-100 font-semibold">ASL (AgentScript Language)</div>
            <div className="text-[11px] text-craft-500">The Missing Infrastructure Seam • aslang.dev</div>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-6 text-craft-400 text-xs">
          <span className="flex items-center gap-1.5">
            <Shield className="w-3.5 h-3.5 text-craft-emerald" />
            <span>100% Differential Gates Green</span>
          </span>
          <span className="flex items-center gap-1.5">
            <Terminal className="w-3.5 h-3.5 text-craft-accent" />
            <span>Wasm Preview1 Compatible</span>
          </span>
        </div>

        {/* Community & Links */}
        <div className="flex items-center gap-5 text-xs">
          <a
            href="https://github.com/genseam/asl"
            target="_blank"
            rel="noreferrer"
            className="text-craft-300 hover:text-craft-accent transition-colors"
          >
            GitHub
          </a>
          <a
            href="https://discord.gg/genseam"
            target="_blank"
            rel="noreferrer"
            className="text-craft-300 hover:text-craft-accent transition-colors"
          >
            Discord
          </a>
          <a
            href="https://x.com/genseam"
            target="_blank"
            rel="noreferrer"
            className="text-craft-300 hover:text-craft-accent transition-colors"
          >
            Twitter / X
          </a>
          <a
            href="/llms.txt"
            target="_blank"
            className="text-craft-accent hover:underline"
          >
            llms.txt
          </a>
        </div>
      </div>
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mt-6 pt-4 border-t border-craft-900/60 text-center text-[11px] text-craft-600">
        Open Source under MIT License. Built from the ground up for the Agentic Era & Vibe-Coding.
      </div>
    </footer>
  );
};
