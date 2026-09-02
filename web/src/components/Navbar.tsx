import React, { useEffect, useState } from 'react';
import { Menu, X } from 'lucide-react';
import { ThemeToggle } from './ThemeToggle';
import { Wordmark } from './ui/Logo';

const navItems = [
  { label: 'The Agent Way', href: '#agent-way' },
  { label: 'Wire Protocol', href: '#a2a-protocol' },
  { label: 'SkyLoom Mesh', href: '#skyloom-mesh' },
  { label: 'Toolchain', href: '#toolchain' },
];

export const Navbar: React.FC = () => {
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setIsOpen(false);
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  return (
    <div className="fixed top-4 left-0 right-0 z-50 flex justify-center px-4 pointer-events-none">
      <header className="pointer-events-auto max-w-4xl w-full rounded-full border border-line bg-surface/85 backdrop-blur-2xl px-4 sm:px-5 h-14 flex items-center justify-between shadow-e2">
        <a href="#top" className="rounded-full">
          <Wordmark />
        </a>

        <nav aria-label="Sections" className="hidden md:flex items-center gap-1">
          {navItems.map((item) => (
            <a
              key={item.href}
              href={item.href}
              className="px-3.5 py-1.5 rounded-full font-mono text-meta text-ink-2 hover:text-ink hover:bg-inset transition-colors"
            >
              {item.label}
            </a>
          ))}
        </nav>

        <div className="flex items-center gap-2">
          <ThemeToggle />
          <a
            href="#install"
            className="px-4 py-2 rounded-full bg-ink text-ground font-mono text-meta font-medium hover:opacity-90 transition-opacity"
          >
            Install
          </a>
          <button
            onClick={() => setIsOpen(!isOpen)}
            className="md:hidden p-1.5 rounded-full text-ink-2 hover:text-ink"
            aria-expanded={isOpen}
            aria-controls="mobile-nav"
            aria-label="Toggle navigation menu"
          >
            {isOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
          </button>
        </div>
      </header>

      {isOpen && (
        <nav
          id="mobile-nav"
          aria-label="Sections"
          className="pointer-events-auto absolute top-[4.5rem] left-4 right-4 rounded-2xl border border-line bg-surface/95 backdrop-blur-2xl p-2 shadow-e3 md:hidden"
        >
          {navItems.map((item) => (
            <a
              key={item.href}
              href={item.href}
              onClick={() => setIsOpen(false)}
              className="block px-4 py-3 rounded-2xl font-mono text-meta text-ink-2 hover:text-ink hover:bg-inset transition-colors"
            >
              {item.label}
            </a>
          ))}
        </nav>
      )}
    </div>
  );
};
