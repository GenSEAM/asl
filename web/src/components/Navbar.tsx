import React, { useState } from 'react';
import { Terminal, Cpu, Layers, Sparkles, FolderPlus, Bot, Menu, X, ExternalLink, Package } from 'lucide-react';
import { ScaffoldModal } from './ScaffoldModal';

export const Navbar: React.FC = () => {
  const [isScaffoldOpen, setIsScaffoldOpen] = useState(false);
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

  const navItems = [
    { label: 'EDDIE Swarm', href: '#eddie', icon: Bot },
    { label: 'Skills Hub', href: '#skills', icon: Package },
    { label: 'Wasm REPL', href: '#playground', icon: Terminal },
    { label: 'AST Graph', href: '#graph', icon: Layers },
    { label: 'Vector AI', href: '#neural', icon: Cpu },
    { label: 'Matrix', href: '#matrix', icon: Sparkles },
    { label: 'Docs', href: '#docs', icon: ExternalLink },
  ];

  return (
    <>
      <header className="sticky top-0 z-50 border-b border-craft-800/80 bg-craft-950/90 backdrop-blur-md">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
          {/* Logo */}
          <a href="#" className="flex items-center gap-3 group">
            <div className="h-9 w-9 rounded-md border border-craft-accent/50 bg-craft-900/80 flex items-center justify-center text-craft-accent font-mono font-bold text-lg shadow-sm group-hover:border-craft-accent transition-colors">
              λ
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="font-mono font-bold text-craft-50 tracking-tight text-lg">ASL</span>
                <span className="px-1.5 py-0.5 rounded text-[10px] font-mono font-semibold bg-craft-800 text-craft-accent border border-craft-700">v1.0 Nano</span>
              </div>
              <p className="text-[10px] text-craft-400 font-mono hidden sm:block">AgentScript Language</p>
            </div>
          </a>

          {/* Desktop Navigation */}
          <nav className="hidden lg:flex items-center gap-1 xl:gap-2 text-xs font-mono text-craft-300">
            {navItems.map((item) => {
              const Icon = item.icon;
              return (
                <a
                  key={item.href}
                  href={item.href}
                  className="px-2.5 py-1.5 rounded hover:text-craft-accent hover:bg-craft-900/60 transition-colors flex items-center gap-1.5"
                >
                  <Icon className="w-3.5 h-3.5 text-craft-accent/80" />
                  <span>{item.label}</span>
                </a>
              );
            })}
          </nav>

          {/* Action Buttons */}
          <div className="flex items-center gap-2 sm:gap-3">
            <a
              href="https://github.com/GenSEAM/asl"
              target="_blank"
              rel="noreferrer"
              className="p-2 text-craft-400 hover:text-craft-100 hover:bg-craft-900 rounded border border-transparent hover:border-craft-800 transition-colors"
              title="GitHub Repository"
            >
              <svg className="w-4 h-4 fill-current" viewBox="0 0 24 24">
                <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z" />
              </svg>
            </a>

            <button
              onClick={() => setIsScaffoldOpen(true)}
              className="hidden sm:flex items-center gap-1.5 px-3 py-1.5 text-xs font-mono rounded border border-craft-700 bg-craft-900 hover:border-craft-accent hover:text-craft-accent text-craft-200 transition-colors shadow-sm"
            >
              <FolderPlus className="w-3.5 h-3.5 text-craft-accent" />
              <span>Scaffold</span>
            </button>

            <a
              href="#playground"
              className="px-3 py-1.5 text-xs font-mono font-semibold rounded bg-craft-accent text-craft-950 hover:bg-craft-accent/90 transition-colors shadow-sm flex items-center gap-1.5"
            >
              <Terminal className="w-3.5 h-3.5" />
              <span className="hidden xs:inline">Run</span> Wasm
            </a>

            {/* Mobile Hamburger Toggle */}
            <button
              onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
              className="lg:hidden p-2 text-craft-400 hover:text-craft-100 hover:bg-craft-900 rounded border border-craft-800 transition-colors"
              aria-label="Toggle navigation menu"
            >
              {isMobileMenuOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
            </button>
          </div>
        </div>

        {/* Mobile Dropdown Drawer */}
        {isMobileMenuOpen && (
          <div className="lg:hidden border-b border-craft-800 bg-craft-950/95 backdrop-blur-xl px-4 py-4 space-y-2">
            <div className="grid grid-cols-2 gap-2 text-xs font-mono">
              {navItems.map((item) => {
                const Icon = item.icon;
                return (
                  <a
                    key={item.href}
                    href={item.href}
                    onClick={() => setIsMobileMenuOpen(false)}
                    className="p-2.5 rounded bg-craft-900/60 border border-craft-800/80 hover:border-craft-accent/50 text-craft-200 flex items-center gap-2 transition-colors"
                  >
                    <Icon className="w-4 h-4 text-craft-accent" />
                    <span>{item.label}</span>
                  </a>
                );
              })}
            </div>
            <div className="pt-2 flex gap-2">
              <button
                onClick={() => {
                  setIsMobileMenuOpen(false);
                  setIsScaffoldOpen(true);
                }}
                className="w-full py-2 text-xs font-mono rounded border border-craft-700 bg-craft-900 text-craft-200 flex items-center justify-center gap-2"
              >
                <FolderPlus className="w-4 h-4 text-craft-accent" />
                <span>New Project Scaffold</span>
              </button>
            </div>
          </div>
        )}
      </header>

      <ScaffoldModal isOpen={isScaffoldOpen} onClose={() => setIsScaffoldOpen(false)} />
    </>
  );
};
