import React, { useState } from 'react';
import { Terminal, Cpu, Layers, Sparkles, FolderPlus } from 'lucide-react';
import { ScaffoldModal } from './ScaffoldModal';

export const Navbar: React.FC = () => {
  const [isScaffoldOpen, setIsScaffoldOpen] = useState(false);

  return (
    <>
      <header className="sticky top-0 z-40 border-b border-craft-800 bg-craft-950/80 backdrop-blur-md">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="h-9 w-9 rounded border border-craft-accent/40 bg-craft-900 flex items-center justify-center text-craft-accent font-mono font-bold text-lg shadow-sm">
              λ
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="font-mono font-bold text-craft-50 tracking-tight text-lg">ASL</span>
                <span className="px-1.5 py-0.5 rounded text-[10px] font-mono font-semibold bg-craft-800 text-craft-accent border border-craft-700">AgentScript</span>
              </div>
              <p className="text-[11px] text-craft-400 font-mono hidden sm:block">The Language for AI Agents & Vibe-Coding</p>
            </div>
          </div>

          <nav className="hidden md:flex items-center gap-6 text-sm font-mono text-craft-300">
            <a href="#showcases" className="hover:text-craft-accent transition-colors flex items-center gap-1.5">
              <Sparkles className="w-4 h-4 text-craft-accent" />
              <span>Showcases</span>
            </a>
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
            <a href="#frameworks" className="hover:text-craft-accent transition-colors">
              <span>Frameworks</span>
            </a>
            <a href="#runtimes" className="hover:text-craft-accent transition-colors">
              <span>Runtimes</span>
            </a>
            <a href="#recipes" className="hover:text-craft-accent transition-colors">
              <span>Recipes</span>
            </a>
            <a href="#blog" className="hover:text-craft-accent transition-colors">
              <span>Journal</span>
            </a>
            <a href="#docs" className="hover:text-craft-accent transition-colors flex items-center gap-1">
              <span className="text-craft-accent">§</span>
              <span>Docs</span>
            </a>
          </nav>

          <div className="flex items-center gap-3">
            <button
              onClick={() => setIsScaffoldOpen(true)}
              className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-mono rounded border border-craft-700 bg-craft-900 hover:border-craft-accent hover:text-craft-accent text-craft-200 transition-colors shadow-sm"
            >
              <FolderPlus className="w-3.5 h-3.5 text-craft-accent" />
              <span>New Project</span>
            </button>
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

      <ScaffoldModal isOpen={isScaffoldOpen} onClose={() => setIsScaffoldOpen(false)} />
    </>
  );
};
