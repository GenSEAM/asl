import React, { useEffect, useState } from 'react';
import {
  Home,
  Terminal,
  Layers,
  Milestone,
  BookOpen,
  Newspaper,
  Search,
  Sparkles,
} from 'lucide-react';
import { ThemeToggle } from './ThemeToggle';
import { ChameleonALogo } from './ui/Logo';
import { SearchModal } from './SearchModal';
import { Link } from '../lib/router';

const navItems = [
  { label: 'Home', href: '/', icon: Home },
  { label: 'Playground', href: '/playground', icon: Terminal },
  { label: 'Ecosystem', href: '/ecosystem', icon: Layers },
  { label: 'Roadmap', href: '/roadmap', icon: Milestone },
  { label: 'Docs', href: '/docs', icon: BookOpen },
  { label: 'Blog', href: '/blog', icon: Newspaper },
];

export const Navbar: React.FC = () => {
  const [isSearchOpen, setIsSearchOpen] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
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
      <div className="fixed top-2 sm:top-3 left-0 right-0 z-50 flex justify-center px-2 sm:px-4 pointer-events-none w-full max-w-[100vw]">
        <div className="relative pointer-events-auto max-w-6xl w-full">
          {/* Main Top Header Toolbar: Fully expanded & perfectly responsive */}
          <header className="relative z-10 w-full rounded-full border border-line/80 bg-surface/90 backdrop-blur-2xl px-2 xs:px-3 sm:px-4 h-12 sm:h-14 flex items-center justify-between shadow-e2 transition-all">
            {/* Logo / Wordmark */}
            <Link
              to="/"
              className="rounded-full shrink-0 flex items-center gap-1.5 sm:gap-2 pr-1 sm:pr-2 group"
              title="aslang.dev home"
            >
              <ChameleonALogo className="w-6 h-6 sm:w-7 sm:h-7 text-signal shrink-0 group-hover:scale-105 transition-transform" />
              <span className="font-sans font-bold tracking-tight text-ink text-sm sm:text-base hidden min-[360px]:inline">
                asl<span className="hidden xs:inline">ang<span className="text-signal">.dev</span></span>
              </span>
            </Link>

            {/* Navigation links: Fully expanded on mobile & desktop */}
            <nav aria-label="Main Navigation" className="flex items-center gap-0.5 xs:gap-1 sm:gap-1.5 shrink-0">
              {navItems.map((item) => {
                const Icon = item.icon;
                return (
                  <Link
                    key={item.href}
                    to={item.href}
                    className="p-1.5 xs:p-2 nav:px-3.5 nav:py-1.5 rounded-full font-mono text-meta text-ink-2 hover:text-ink hover:bg-inset transition-colors flex items-center gap-1.5 shrink-0"
                    activeClassName="!text-signal !bg-signal/10 !font-semibold shadow-sm"
                    title={item.label}
                    aria-label={item.label}
                  >
                    <Icon className="w-3.5 h-3.5 sm:w-4 sm:h-4 shrink-0 text-current" />
                    <span className="hidden nav:inline">{item.label}</span>
                  </Link>
                );
              })}
            </nav>

            {/* Right Action Icons: Search, llms.txt, GitHub, Theme */}
            <div className="flex items-center gap-1 sm:gap-2 shrink-0">
              {/* Search Trigger */}
              <button
                type="button"
                onClick={() => setIsSearchOpen(true)}
                className="flex items-center gap-1.5 p-1.5 xs:p-2 min-[1100px]:px-3 min-[1100px]:py-1.5 rounded-full border border-line bg-inset/80 hover:bg-inset text-ink-3 hover:text-ink font-mono text-micro transition-all shadow-sm shrink-0"
                aria-label="Search documentation"
                title="Search documentation (⌘K)"
              >
                <Search className="w-3.5 h-3.5 text-signal shrink-0" />
                <span className="hidden min-[1100px]:inline">Search</span>
                <kbd className="hidden min-[1100px]:inline-block px-1.5 py-0.5 rounded bg-surface border border-line font-mono text-[9px] text-ink-3">
                  ⌘K
                </kbd>
              </button>

              {/* llms.txt Direct Button (Only on >=1200px) */}
              <a
                href="/llms.txt"
                target="_blank"
                rel="noreferrer"
                className="hidden min-[1200px]:inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full border border-signal/30 bg-signal/10 hover:bg-signal/20 text-signal font-mono text-micro font-medium transition-colors shrink-0"
                title="Raw model specification (/llms.txt)"
              >
                <Sparkles className="w-3 h-3 shrink-0" />
                <span>llms.txt</span>
              </a>

              {/* GitHub Repository Link: Hidden on small mobile to fit iPhone 12 mini perfectly */}
              <a
                href="https://github.com/genseam/asl"
                target="_blank"
                rel="noreferrer"
                className="hidden sm:flex items-center gap-1.5 p-2 nav:px-3 nav:py-1.5 rounded-full border border-line bg-surface hover:bg-inset text-ink font-mono text-meta font-medium shadow-sm transition-all shrink-0"
                aria-label="GitHub Repository"
                title="GitHub Repository"
              >
                <svg className="w-4 h-4 fill-current text-ink shrink-0" viewBox="0 0 24 24">
                  <path
                    fillRule="evenodd"
                    clipRule="evenodd"
                    d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.53 1.032 1.53 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z"
                  />
                </svg>
                <span className="hidden nav:inline">GitHub</span>
              </a>

              <ThemeToggle />
            </div>
          </header>
        </div>
      </div>

      {/* Search Modal */}
      <SearchModal isOpen={isSearchOpen} onClose={() => setIsSearchOpen(false)} />
    </>
  );
};
