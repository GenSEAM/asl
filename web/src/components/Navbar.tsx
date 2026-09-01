import React, { useState } from 'react';
import { Menu, X } from 'lucide-react';
import { ThemeToggle } from './ThemeToggle';

export const Navbar: React.FC = () => {
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

  const navItems = [
    { label: 'The Agent Way', href: '#agent-way' },
    { label: 'A2A Wire', href: '#a2a-protocol' },
    { label: 'Observability', href: '#observability' },
    { label: 'Insights', href: '#insights' },
    { label: 'Skills Hub', href: '#skills' },
  ];

  return (
    <div className="fixed top-4 left-0 right-0 z-50 flex justify-center px-4 pointer-events-none">
      <header className="pointer-events-auto max-w-4xl w-full rounded-full border border-craft-200/80 dark:border-white/[0.12] bg-white/80 dark:bg-[#06080d]/80 backdrop-blur-2xl px-4 sm:px-6 h-14 flex items-center justify-between shadow-2xl transition-all">
        {/* Brand Logo Capsule */}
        <a href="#" className="flex items-center gap-2.5 group">
          <div className="h-8 w-8 rounded-full border border-craft-300 dark:border-craft-accent/50 bg-craft-100 dark:bg-craft-900 flex items-center justify-center text-craft-accent font-mono font-bold text-base shadow-sm group-hover:scale-105 transition-all">
            λ
          </div>
          <span className="font-mono font-extrabold text-craft-900 dark:text-white tracking-tight text-base">
            ASL
          </span>
        </a>

        {/* Compact Center Navigation */}
        <nav className="hidden md:flex items-center gap-1 text-xs font-mono text-craft-600 dark:text-craft-300">
          {navItems.map((item) => (
            <a
              key={item.href}
              href={item.href}
              className="px-3.5 py-1.5 rounded-full hover:text-craft-accent hover:bg-craft-100 dark:hover:bg-white/[0.06] transition-all"
            >
              {item.label}
            </a>
          ))}
        </nav>

        {/* Action Capsule */}
        <div className="flex items-center gap-2">
          <ThemeToggle />

          <a
            href="#skills"
            className="px-4 py-1.5 text-xs font-mono font-bold rounded-full bg-craft-accent text-craft-950 hover:bg-craft-accent/90 transition-all shadow-sm flex items-center gap-1.5"
          >
            <span>Install</span>
          </a>

          {/* Mobile Menu Button */}
          <button
            onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
            className="md:hidden p-1.5 text-craft-500 dark:text-craft-400 hover:text-craft-900 dark:hover:text-white"
            aria-label="Toggle navigation menu"
          >
            {isMobileMenuOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
          </button>
        </div>
      </header>

      {/* Mobile Dropdown Drawer */}
      {isMobileMenuOpen && (
        <div className="pointer-events-auto absolute top-16 left-4 right-4 rounded-3xl border border-craft-200 dark:border-white/[0.12] bg-white/95 dark:bg-[#06080d]/95 backdrop-blur-2xl p-4 shadow-2xl md:hidden space-y-2 font-mono text-xs text-left">
          {navItems.map((item) => (
            <a
              key={item.href}
              href={item.href}
              onClick={() => setIsMobileMenuOpen(false)}
              className="block p-3 rounded-2xl bg-craft-100/50 dark:bg-white/[0.03] text-craft-800 dark:text-craft-200 hover:text-craft-accent"
            >
              {item.label}
            </a>
          ))}
        </div>
      )}
    </div>
  );
};
