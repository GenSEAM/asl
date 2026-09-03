import React, { useEffect, useState, useRef } from 'react';
import {
  Home,
  Terminal,
  Layers,
  Milestone,
  BookOpen,
  Search,
  Sparkles,
  X,
  ExternalLink,
} from 'lucide-react';
import { ThemeToggle } from './ThemeToggle';
import { Wordmark } from './ui/Logo';
import { SearchModal } from './SearchModal';
import { Link } from '../lib/router';

const navItems = [
  { label: 'Home', href: '/', icon: Home },
  { label: 'Playground', href: '/playground', icon: Terminal },
  { label: 'Ecosystem', href: '/ecosystem', icon: Layers },
  { label: 'Roadmap', href: '/roadmap', icon: Milestone },
  { label: 'Docs', href: '/docs', icon: BookOpen },
];

export const Navbar: React.FC = () => {
  const [isOpen, setIsOpen] = useState(false);
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const curtainRef = useRef<HTMLDivElement>(null);
  const handleRef = useRef<HTMLButtonElement>(null);
  const touchStartY = useRef<number | null>(null);

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

  useEffect(() => {
    const onClickOutside = (e: MouseEvent) => {
      if (
        isOpen &&
        curtainRef.current &&
        !curtainRef.current.contains(e.target as Node) &&
        handleRef.current &&
        !handleRef.current.contains(e.target as Node)
      ) {
        setIsOpen(false);
      }
    };
    document.addEventListener('mousedown', onClickOutside);
    return () => document.removeEventListener('mousedown', onClickOutside);
  }, [isOpen]);

  useEffect(() => {
    const onResize = () => {
      if (window.innerWidth >= 981) {
        setIsOpen(false);
      }
    };
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);

  const handleTouchStart = (e: React.TouchEvent) => {
    touchStartY.current = e.touches[0].clientY;
  };

  const handleTouchMove = (e: React.TouchEvent) => {
    if (touchStartY.current === null) return;
    const diff = e.touches[0].clientY - touchStartY.current;
    if (!isOpen && diff > 25) {
      setIsOpen(true);
      touchStartY.current = null;
    } else if (isOpen && diff < -25) {
      setIsOpen(false);
      touchStartY.current = null;
    }
  };

  const handleTouchEnd = () => {
    touchStartY.current = null;
  };

  return (
    <>
      <div className="fixed top-3 left-0 right-0 z-50 flex justify-center px-2 sm:px-4 pointer-events-none">
        <div className="relative pointer-events-auto max-w-6xl w-full">
          {/* Main Top Header Toolbar */}
          <header
            onTouchStart={handleTouchStart}
            onTouchMove={handleTouchMove}
            onTouchEnd={handleTouchEnd}
            className="relative z-10 w-full rounded-full border border-line/80 bg-surface/90 backdrop-blur-2xl px-2.5 sm:px-4 h-14 flex items-center justify-between shadow-e2 transition-all"
          >
            {/* Logo / Wordmark */}
            <Link to="/" className="rounded-full shrink-0 flex items-center pr-1 sm:pr-2" title="aslang.dev home">
              <Wordmark />
            </Link>

            {/* Navigation links: Compact icons on <981px, Icons + Labels on >=981px */}
            <nav aria-label="Main Navigation" className="flex items-center gap-1 sm:gap-1.5 shrink-0">
              {navItems.map((item) => {
                const Icon = item.icon;
                return (
                  <Link
                    key={item.href}
                    to={item.href}
                    className="p-2 nav:px-3.5 nav:py-1.5 rounded-full font-mono text-meta text-ink-2 hover:text-ink hover:bg-inset transition-colors flex items-center gap-1.5 shrink-0"
                    activeClassName="!text-signal !bg-signal/10 !font-semibold shadow-sm"
                    title={item.label}
                    aria-label={item.label}
                  >
                    <Icon className="w-4 h-4 shrink-0 text-current" />
                    <span className="hidden nav:inline">{item.label}</span>
                  </Link>
                );
              })}
            </nav>

            {/* Right Action Icons: Search, llms.txt, GitHub, Theme */}
            <div className="flex items-center gap-1.5 sm:gap-2 shrink-0">
              {/* Search Trigger: Compact icon below 1100px, with label above */}
              <button
                type="button"
                onClick={() => setIsSearchOpen(true)}
                className="flex items-center gap-2 p-2 min-[1100px]:px-3 min-[1100px]:py-1.5 rounded-full border border-line bg-inset/80 hover:bg-inset text-ink-3 hover:text-ink font-mono text-micro transition-all shadow-sm shrink-0"
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

              {/* GitHub Repository Link: Icon-only below 981px, with label above */}
              <a
                href="https://github.com/genseam/asl"
                target="_blank"
                rel="noreferrer"
                className="flex items-center gap-1.5 p-2 nav:px-3 nav:py-1.5 rounded-full border border-line bg-surface hover:bg-inset text-ink font-mono text-meta font-medium shadow-sm transition-all shrink-0"
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

          {/* Integrated Celestial Arrow Orb tucked under the header */}
          <div className="nav:hidden absolute left-1/2 -translate-x-1/2 -bottom-2.5 z-0 flex items-center justify-center pointer-events-auto">
            <button
              ref={handleRef}
              type="button"
              onClick={() => setIsOpen((prev) => !prev)}
              aria-label={isOpen ? 'Close menu' : 'Open menu'}
              aria-expanded={isOpen}
              className="group flex items-center justify-center w-7 h-7 rounded-full border border-line bg-surface/95 shadow-sm hover:border-signal/50 transition-all duration-200 hover:translate-y-1 active:scale-95 cursor-pointer focus:outline-none"
              title={isOpen ? 'Close menu (Esc)' : 'Open menu'}
            >
              {/* Orb with integrated arrow & orbital satellite */}
              <svg viewBox="0 0 28 28" className="w-4 h-4 text-ink-3 group-hover:text-signal transition-colors">
                {/* Subtle orbit ring */}
                <ellipse
                  cx="14"
                  cy="14"
                  rx="11"
                  ry="4.5"
                  stroke="currentColor"
                  strokeWidth="0.9"
                  strokeDasharray="2 2"
                  className="opacity-40 -rotate-25 origin-center"
                />
                {/* Orbit satellite beacon dot */}
                <circle cx="22" cy="11" r="1.3" className="fill-signal" />
                {/* Arrow smoothly integrated inside the orb */}
                <path
                  d={isOpen ? 'M9.5 16l4.5-4.5 4.5 4.5' : 'M9.5 12l4.5 4.5 4.5-4.5'}
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.8"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  className="transition-all duration-200"
                />
              </svg>
            </button>
          </div>

          {/* Clean Streamlined Curtain Menu Drawer */}
          {isOpen && (
            <div
              ref={curtainRef}
              className="nav:hidden pointer-events-auto mt-4 w-full rounded-3xl border border-line bg-surface/95 backdrop-blur-2xl p-4 sm:p-5 shadow-e3 transition-all duration-300 max-h-[82vh] overflow-y-auto"
            >
              {/* Subtle Header with mini easter-egg badge */}
              <div className="flex items-center justify-between pb-3 border-b border-line mb-3.5">
                <div className="flex items-center gap-2">
                  <span className="w-1.5 h-1.5 rounded-full bg-signal" />
                  <span className="font-mono text-micro uppercase tracking-wider text-ink font-semibold">
                    Orbit Relay
                  </span>
                  <span className="px-2 py-0.5 rounded-full bg-signal/10 text-signal font-mono text-[10px] font-medium border border-signal/20">
                    v0.2.0 • 107 builtins
                  </span>
                </div>
                <button
                  type="button"
                  onClick={() => setIsOpen(false)}
                  className="p-1 rounded-lg text-ink-3 hover:text-ink hover:bg-inset transition-colors"
                  aria-label="Close menu"
                  title="Close (Esc)"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>

              {/* Clean navigation grid */}
              <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 mb-3.5">
                {navItems.map((item) => {
                  const Icon = item.icon;
                  return (
                    <Link
                      key={item.href}
                      to={item.href}
                      onClick={() => setIsOpen(false)}
                      className="flex items-center gap-2.5 p-2.5 rounded-xl border border-line/60 bg-inset/40 hover:bg-inset hover:border-line text-ink transition-all group"
                      activeClassName="!border-signal/50 !bg-signal/10 shadow-sm"
                    >
                      <div className="p-1.5 rounded-lg bg-surface border border-line text-ink-2 group-hover:text-signal transition-colors">
                        <Icon className="w-3.5 h-3.5" />
                      </div>
                      <span className="font-mono text-meta font-medium text-ink group-hover:text-signal transition-colors">
                        {item.label}
                      </span>
                    </Link>
                  );
                })}
              </div>

              {/* Quick links & Model Spec footer */}
              <div className="pt-3 border-t border-line flex flex-wrap items-center justify-between gap-2.5 font-mono text-micro text-ink-3">
                <div className="flex items-center gap-2">
                  <a
                    href="/llms.txt"
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-signal/10 hover:bg-signal/20 text-signal font-medium transition-colors"
                  >
                    <Sparkles className="w-3 h-3" />
                    <span>llms.txt</span>
                  </a>
                  <a
                    href="/llms-full.txt"
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-inset hover:bg-surface border border-line text-ink-2 hover:text-ink font-medium transition-colors"
                  >
                    <span>llms-full.txt</span>
                  </a>
                </div>

                <div className="flex items-center gap-3">
                  <span className="hidden sm:inline text-ink-4">⌘K for search</span>
                  <a
                    href="https://github.com/genseam/asl"
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-1 text-ink-2 hover:text-ink transition-colors"
                  >
                    <span>GitHub</span>
                    <ExternalLink className="w-3 h-3" />
                  </a>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Search Modal */}
      <SearchModal isOpen={isSearchOpen} onClose={() => setIsSearchOpen(false)} />
    </>
  );
};



