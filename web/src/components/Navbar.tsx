import React, { useEffect, useState, useRef } from 'react';
import {
  Home,
  Terminal,
  Layers,
  Milestone,
  BookOpen,
  Search,
  Sparkles,
  ChevronDown,
  X,
  ExternalLink,
} from 'lucide-react';
import { ThemeToggle } from './ThemeToggle';
import { Wordmark } from './ui/Logo';
import { SearchModal } from './SearchModal';
import { Link } from '../lib/router';

const navItems = [
  { label: 'Home', href: '/', icon: Home, desc: 'Overview, benchmarks & thesis' },
  { label: 'Playground', href: '/playground', icon: Terminal, desc: 'Interactive REPL & sandbox' },
  { label: 'Ecosystem', href: '/ecosystem', icon: Layers, desc: 'Packages, AST & mesh' },
  { label: 'Roadmap', href: '/roadmap', icon: Milestone, desc: 'Language phases & progress' },
  { label: 'Docs', href: '/docs', icon: BookOpen, desc: 'Specification & SQL studio' },
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

  const handleTouchStart = (e: React.TouchEvent) => {
    touchStartY.current = e.touches[0].clientY;
  };

  const handleTouchMove = (e: React.TouchEvent) => {
    if (touchStartY.current === null) return;
    const diff = e.touches[0].clientY - touchStartY.current;
    if (!isOpen && diff > 30) {
      setIsOpen(true);
      touchStartY.current = null;
    } else if (isOpen && diff < -30) {
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
            className="w-full rounded-full border border-line/80 bg-surface/90 backdrop-blur-2xl px-2.5 sm:px-4 h-14 flex items-center justify-between shadow-e2 transition-all"
          >
            {/* Logo / Wordmark */}
            <Link to="/" className="rounded-full shrink-0 flex items-center pr-1 sm:pr-2" title="aslang.dev home">
              <Wordmark />
            </Link>

            {/* Navigation links: Compact icons on <900px, Icons + Labels on >=900px */}
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

              {/* GitHub Repository Link: Icon-only below 900px, with label above */}
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

          {/* Curtain Pull-Down Handle hanging below the header */}
          <div className="absolute -bottom-3 left-1/2 -translate-x-1/2 flex items-center justify-center pointer-events-auto">
            <button
              ref={handleRef}
              type="button"
              onClick={() => setIsOpen((prev) => !prev)}
              aria-label={isOpen ? 'Close menu curtain' : 'Pull down full menu curtain'}
              aria-expanded={isOpen}
              className="group flex items-center gap-1.5 px-3 py-0.5 rounded-full bg-surface/95 hover:bg-surface border border-line/80 shadow-md backdrop-blur-xl text-ink-3 hover:text-ink transition-all hover:scale-105 active:scale-95 cursor-pointer"
              title={isOpen ? 'Close curtain (Esc)' : 'Pull down full menu'}
            >
              <span className="w-4 h-0.5 rounded-full bg-ink-4 group-hover:bg-signal transition-colors" />
              <ChevronDown
                className={`w-3 h-3 transition-transform duration-300 ${
                  isOpen ? 'rotate-180 text-signal' : 'group-hover:translate-y-0.5'
                }`}
              />
            </button>
          </div>

          {/* Curtain Menu Drawer */}
          {isOpen && (
            <div
              ref={curtainRef}
              className="pointer-events-auto mt-4 w-full rounded-3xl border border-line bg-surface/95 backdrop-blur-2xl p-4 sm:p-5 shadow-e3 transition-all duration-300 max-h-[82vh] overflow-y-auto"
            >
              <div className="flex items-center justify-between pb-3 border-b border-line mb-4">
                <div className="flex items-center gap-2">
                  <span className="w-2 h-2 rounded-full bg-signal animate-pulse" />
                  <span className="font-mono text-micro uppercase tracking-wider text-ink-3 font-semibold">
                    AgentScript Navigator
                  </span>
                </div>
                <button
                  type="button"
                  onClick={() => setIsOpen(false)}
                  className="p-1 rounded-lg text-ink-3 hover:text-ink hover:bg-inset transition-colors"
                  aria-label="Close curtain"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>

              {/* Rich navigation grid */}
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2.5 mb-5">
                {navItems.map((item) => {
                  const Icon = item.icon;
                  return (
                    <Link
                      key={item.href}
                      to={item.href}
                      onClick={() => setIsOpen(false)}
                      className="flex items-start gap-3 p-3 rounded-2xl border border-line/60 bg-inset/40 hover:bg-inset hover:border-line text-ink transition-all group"
                      activeClassName="!border-signal/50 !bg-signal/10"
                    >
                      <div className="p-2 rounded-xl bg-surface border border-line text-ink-2 group-hover:text-signal transition-colors">
                        <Icon className="w-4 h-4" />
                      </div>
                      <div>
                        <div className="font-mono text-meta font-medium text-ink group-hover:text-signal transition-colors">
                          {item.label}
                        </div>
                        <div className="font-sans text-micro text-ink-3 leading-relaxed mt-0.5">
                          {item.desc}
                        </div>
                      </div>
                    </Link>
                  );
                })}
              </div>

              {/* Quick links & Model Spec footer */}
              <div className="pt-4 border-t border-line flex flex-wrap items-center justify-between gap-3 font-mono text-micro text-ink-3">
                <div className="flex items-center gap-2.5">
                  <a
                    href="/llms.txt"
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-signal/10 hover:bg-signal/20 text-signal font-medium transition-colors"
                  >
                    <Sparkles className="w-3.5 h-3.5" />
                    <span>llms.txt (Short)</span>
                  </a>
                  <a
                    href="/llms-full.txt"
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-inset hover:bg-surface border border-line text-ink-2 hover:text-ink font-medium transition-colors"
                  >
                    <span>llms-full.txt (Full Spec)</span>
                  </a>
                </div>

                <div className="flex items-center gap-4">
                  <span className="hidden sm:inline text-ink-4">Press ⌘K for instant search</span>
                  <a
                    href="https://github.com/genseam/asl"
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-1 text-ink-2 hover:text-ink transition-colors"
                  >
                    <span>github.com/genseam/asl</span>
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

