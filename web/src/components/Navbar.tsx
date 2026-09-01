import React, { useState } from 'react';
import { Bot, Package, Sparkles, Globe, Menu, X, Compass, Radio } from 'lucide-react';
import { ThemeToggle } from './ThemeToggle';

export const Navbar: React.FC = () => {
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

  const navItems = [
    { label: 'The Agent Way', href: '#agent-way', icon: Compass },
    { label: 'A2A Wire Protocol', href: '#a2a-protocol', icon: Radio },
    { label: 'EDDIE Swarm', href: '#eddie', icon: Bot },
    { label: 'Skills Hub', href: '#skills', icon: Package },
    { label: 'Swarm Bus', href: '#bus', icon: Sparkles },
    { label: 'Community', href: '#community', icon: Globe },
  ];

  return (
    <header className="sticky top-0 z-50 border-b border-craft-200/80 dark:border-craft-800/80 bg-white/80 dark:bg-craft-950/85 backdrop-blur-xl transition-colors">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
        {/* Logo & Brand */}
        <a href="#" className="flex items-center gap-3 group">
          <div className="h-9 w-9 rounded-xl border border-craft-300 dark:border-craft-accent/50 bg-craft-100 dark:bg-craft-900 flex items-center justify-center text-craft-accent font-mono font-bold text-lg shadow-sm group-hover:border-craft-accent group-hover:scale-105 transition-all">
            λ
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="font-mono font-bold text-craft-900 dark:text-craft-50 tracking-tight text-lg">ASL</span>
              <span className="px-2 py-0.5 rounded-full text-[10px] font-mono font-semibold bg-craft-100 dark:bg-craft-800 text-craft-accent border border-craft-200 dark:border-craft-700">
                The Agent Way
              </span>
            </div>
            <p className="text-[10px] text-craft-500 dark:text-craft-400 font-mono hidden sm:block">Agentic Programming (AgP)</p>
          </div>
        </a>

        {/* Desktop Navigation */}
        <nav className="hidden lg:flex items-center gap-1.5 text-xs font-mono text-craft-600 dark:text-craft-300">
          {navItems.map((item) => {
            const Icon = item.icon;
            return (
              <a
                key={item.href}
                href={item.href}
                className="px-3 py-1.5 rounded-lg hover:text-craft-accent hover:bg-craft-100 dark:hover:bg-craft-900/80 transition-all flex items-center gap-1.5"
              >
                <Icon className="w-3.5 h-3.5 text-craft-accent" />
                <span>{item.label}</span>
              </a>
            );
          })}
        </nav>

        {/* Action Buttons & Theme Toggle */}
        <div className="flex items-center gap-2 sm:gap-3">
          <ThemeToggle />

          <a
            href="https://github.com/GenSEAM/asl"
            target="_blank"
            rel="noreferrer"
            className="p-2 text-craft-500 dark:text-craft-400 hover:text-craft-900 dark:hover:text-craft-100 hover:bg-craft-100 dark:hover:bg-craft-900 rounded-lg border border-craft-200 dark:border-craft-800 transition-colors"
            title="GitHub Repository"
          >
            <svg className="w-4 h-4 fill-current" viewBox="0 0 24 24">
              <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z" />
            </svg>
          </a>

          <a
            href="#skills"
            className="px-3.5 py-1.5 text-xs font-mono font-semibold rounded-lg bg-craft-accent text-craft-950 hover:bg-craft-accent/90 transition-all shadow-glow-sm flex items-center gap-1.5"
          >
            <Package className="w-3.5 h-3.5" />
            <span>Install Skills</span>
          </a>

          {/* Mobile Hamburger Toggle */}
          <button
            onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
            className="lg:hidden p-2 text-craft-500 dark:text-craft-400 hover:text-craft-900 dark:hover:text-craft-100 hover:bg-craft-100 dark:hover:bg-craft-900 rounded-lg border border-craft-200 dark:border-craft-800 transition-colors"
            aria-label="Toggle navigation menu"
          >
            {isMobileMenuOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
          </button>
        </div>
      </div>

      {/* Mobile Dropdown Drawer */}
      {isMobileMenuOpen && (
        <div className="lg:hidden border-b border-craft-200 dark:border-craft-800 bg-white/95 dark:bg-craft-950/95 backdrop-blur-2xl px-4 py-4 space-y-2">
          <div className="grid grid-cols-2 gap-2 text-xs font-mono">
            {navItems.map((item) => {
              const Icon = item.icon;
              return (
                <a
                  key={item.href}
                  href={item.href}
                  onClick={() => setIsMobileMenuOpen(false)}
                  className="p-3 rounded-lg bg-craft-100/60 dark:bg-craft-900/60 border border-craft-200 dark:border-craft-800/80 hover:border-craft-accent/50 text-craft-800 dark:text-craft-200 flex items-center gap-2 transition-all"
                >
                  <Icon className="w-4 h-4 text-craft-accent" />
                  <span>{item.label}</span>
                </a>
              );
            })}
          </div>
        </div>
      )}
    </header>
  );
};
