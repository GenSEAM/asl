import React, { useEffect, useState } from 'react';
import { Menu, X, Search, ExternalLink, Sparkles } from 'lucide-react';
import { ThemeToggle } from './ThemeToggle';
import { Wordmark } from './ui/Logo';
import { SearchModal } from './SearchModal';
import { Link } from '../lib/router';

const navItems = [
  { label: 'Home', href: '/' },
  { label: 'Playground', href: '/playground' },
  { label: 'Ecosystem', href: '/ecosystem' },
  { label: 'Roadmap', href: '/roadmap' },
  { label: 'Docs', href: '/docs' },
];

export const Navbar: React.FC = () => {
  const [isOpen, setIsOpen] = useState(false);
  const [isSearchOpen, setIsSearchOpen] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setIsOpen(false);
        setIsSearchOpen(false);
      }
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        setIsSearchOpen((prev) => !prev);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  return (
    <>
      <div className="fixed top-3 left-0 right-0 z-50 flex justify-center px-3 sm:px-4 pointer-events-none">
        <header className="pointer-events-auto max-w-6xl w-full rounded-full border border-line/80 bg-surface/85 backdrop-blur-2xl px-3 sm:px-5 h-14 flex items-center justify-between shadow-e2 transition-all">
          <Link to="/" className="rounded-full shrink-0">
            <Wordmark />
          </Link>

          <nav aria-label="Main Navigation" className="hidden md:flex items-center gap-1">
            {navItems.map((item) => (
              <Link
                key={item.href}
                to={item.href}
                className="px-3.5 py-1.5 rounded-full font-mono text-meta text-ink-2 hover:text-ink hover:bg-inset transition-colors"
                activeClassName="!text-signal !bg-signal/10 !font-semibold"
              >
                {item.label}
              </Link>
            ))}
          </nav>

          <div className="flex items-center gap-2 sm:gap-3">
            {/* Search Trigger (Cmd + K) */}
            <div className="hidden sm:flex items-center">
              <button
                type="button"
                onClick={() => setIsSearchOpen(true)}
                className="flex items-center gap-2 px-3 py-1.5 rounded-full border border-line bg-inset/80 hover:bg-inset text-ink-3 hover:text-ink font-mono text-micro transition-all shadow-sm"
                aria-label="Search documentation"
              >
                <Search className="w-3.5 h-3.5 text-signal" />
                <span>Search</span>
                <kbd className="px-1.5 py-0.5 rounded bg-surface border border-line font-mono text-[9px] text-ink-3">
                  ⌘K
                </kbd>
              </button>
            </div>

            {/* llms.txt Direct Button */}
            <a
              href="/llms.txt"
              target="_blank"
              rel="noreferrer"
              className="hidden lg:inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full border border-signal/30 bg-signal/10 hover:bg-signal/20 text-signal font-mono text-micro font-medium transition-colors"
            >
              <Sparkles className="w-3 h-3" />
              <span>llms.txt</span>
            </a>

            {/* GitHub Repository Link */}
            <a
              href="https://github.com/genseam/asl"
              target="_blank"
              rel="noreferrer"
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-full border border-line bg-surface hover:bg-inset text-ink font-mono text-meta font-medium shadow-sm transition-all"
              aria-label="GitHub Repository"
            >
              <svg className="w-4 h-4 fill-current text-ink" viewBox="0 0 24 24">
                <path fillRule="evenodd" clipRule="evenodd" d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.53 1.032 1.53 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z" />
              </svg>
              <span className="hidden sm:inline">GitHub</span>
            </a>

            <ThemeToggle />

            {/* Mobile Menu Button */}
            <button
              type="button"
              onClick={() => setIsOpen((prev) => !prev)}
              aria-label="Toggle navigation menu"
              aria-expanded={isOpen}
              className="md:hidden p-2 rounded-full border border-line text-ink-2 hover:text-ink hover:bg-inset transition-colors"
            >
              {isOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
            </button>
          </div>
        </header>
      </div>

      {/* Mobile Menu Dropdown */}
      {isOpen && (
        <div className="md:hidden fixed inset-x-3 top-20 z-40 rounded-3xl border border-line bg-surface/95 backdrop-blur-2xl p-5 shadow-e3 transition-all space-y-4">
          <nav className="flex flex-col space-y-1">
            {navItems.map((item) => (
              <Link
                key={item.href}
                to={item.href}
                onClick={() => setIsOpen(false)}
                className="px-4 py-2.5 rounded-xl font-mono text-body text-ink-2 hover:text-ink hover:bg-inset transition-colors"
                activeClassName="!text-signal !bg-signal/10 !font-semibold"
              >
                {item.label}
              </Link>
            ))}
          </nav>

          <div className="pt-4 border-t border-line flex flex-col gap-2.5">
            <a
              href="/llms.txt"
              target="_blank"
              rel="noreferrer"
              className="flex items-center justify-between p-3 rounded-xl bg-signal/10 text-signal font-mono text-meta font-semibold"
            >
              <span>Model Spec (/llms.txt)</span>
              <Sparkles className="w-4 h-4" />
            </a>

            <a
              href="https://github.com/genseam/asl"
              target="_blank"
              rel="noreferrer"
              className="flex items-center justify-between p-3 rounded-xl bg-inset text-ink font-mono text-meta font-semibold"
            >
              <span>View Source on GitHub</span>
              <ExternalLink className="w-4 h-4" />
            </a>
          </div>
        </div>
      )}

      {/* Search Modal */}
      <SearchModal isOpen={isSearchOpen} onClose={() => setIsSearchOpen(false)} />
    </>
  );
};
