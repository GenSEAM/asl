import React from 'react';
import { Terminal, Cpu, Layers, Sparkles, Code } from 'lucide-react';

export const Navbar: React.FC = () => {
  return (
    <header className="sticky top-0 z-50 border-b border-craft-800 bg-craft-950/80 backdrop-blur-md">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="h-9 w-9 rounded border border-craft-accent/40 bg-craft-900 flex items-center justify-center text-craft-accent font-mono font-bold text-lg shadow-sm">
            λ
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="font-mono font-bold text-craft-50 tracking-tight text-lg">AgentScript</span>
              <span className="px-1.5 py-0.5 rounded text-[10px] font-mono font-semibold bg-craft-800 text-craft-accent border border-craft-700">v1.0-WASM</span>
            </div>
            <p className="text-[11px] text-craft-400 font-mono hidden sm:block">Deterministic S-Expressions for AI Agents</p>
          </div>
        </div>

        <nav className="hidden md:flex items-center gap-6 text-sm font-mono text-craft-300">
          <a href="#playground" className="hover:text-craft-accent transition-colors flex items-center gap-1.5">
            <Terminal className="w-4 h-4 text-craft-accent" />
            <span>Playground</span>
          </a>
          <a href="#graph" className="hover:text-craft-accent transition-colors flex items-center gap-1.5">
            <Layers className="w-4 h-4 text-craft-accent" />
            <span>AST Visualizer</span>
          </a>
          <a href="#neural" className="hover:text-craft-accent transition-colors flex items-center gap-1.5">
            <Cpu className="w-4 h-4 text-craft-accent" />
            <span>Wasm Vector AI</span>
          </a>
          <a href="#targets" className="hover:text-craft-accent transition-colors">
            <span>Targets</span>
          </a>
          <a href="#benchmarks" className="hover:text-craft-accent transition-colors">
            <span>Benchmarks</span>
          </a>
          <a href="#docs" className="hover:text-craft-accent transition-colors flex items-center gap-1">
            <span className="text-craft-accent">§</span>
            <span>Docs</span>
          </a>
        </nav>

        <div className="flex items-center gap-3">
          <a 
            href="#targets" 
            className="flex items-center gap-2 px-3 py-1.5 text-xs font-mono rounded border border-craft-700 bg-craft-900 hover:border-craft-600 text-craft-100 transition-colors"
          >
            <Code className="w-4 h-4 text-craft-accent" />
            <span className="hidden sm:inline">6 Targets</span>
          </a>
          <a 
            href="#playground"
            className="px-3.5 py-1.5 text-xs font-mono font-semibold rounded bg-craft-accent text-craft-950 hover:bg-craft-accent/90 transition-colors shadow-sm flex items-center gap-1.5"
          >
            <Sparkles className="w-3.5 h-3.5" />
            <span>Run Sandbox</span>
          </a>
        </div>
      </div>
    </header>
  );
};
