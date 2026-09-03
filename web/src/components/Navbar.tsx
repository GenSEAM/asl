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
  Radio,
  Rocket,
  Compass,
  Cpu,
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

const AUTOPILOT_MODES = [
  { id: 'mars', label: 'Mars Sol-42 Relay', icon: Rocket, status: 'Active (Olympus Mons)' },
  { id: 'swarm', label: 'Neural Swarm Mesh', icon: Radio, status: 'Synchronized (8 nodes)' },
  { id: 'orbit', label: 'LEO Deep Autopilot', icon: Compass, status: 'Telemetry Nominal' },
];

export const Navbar: React.FC = () => {
  const [isOpen, setIsOpen] = useState(false);
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const [easterEggActive, setEasterEggActive] = useState(false);
  const [autopilotIndex, setAutopilotIndex] = useState(0);
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

  const currentMode = AUTOPILOT_MODES[autopilotIndex];
  const ModeIcon = currentMode.icon;

  return (
    <>
      <div className="fixed top-3 left-0 right-0 z-50 flex justify-center px-2 sm:px-4 pointer-events-none">
        <div className="relative pointer-events-auto max-w-6xl w-full">
          {/* Main Top Header Toolbar */}
          <header
            onTouchStart={handleTouchStart}
            onTouchMove={handleTouchMove}
            onTouchEnd={handleTouchEnd}
            className="w-full rounded-full border border-line/80 bg-surface/90 backdrop-blur-2xl px-2.5 sm:px-4 h-14 flex items-center justify-between shadow-e2 transition-all relative"
          >
            {/* Logo / Wordmark */}
            <Link to="/" className="rounded-full shrink-0 flex items-center pr-1 sm:pr-2" title="aslang.dev home">
              <Wordmark />
            </Link>

            {/* Navigation links: Compact icons on <1040px, Icons + Labels on >=1040px */}
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

              {/* GitHub Repository Link: Icon-only below 1040px, with label above */}
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

          {/* Cosmic Orb & Emergent Arrow Pull-Down Handle */}
          <div className="absolute -bottom-5 left-1/2 -translate-x-1/2 flex items-center justify-center pointer-events-auto z-20">
            <button
              ref={handleRef}
              type="button"
              onClick={() => setIsOpen((prev) => !prev)}
              aria-label={isOpen ? 'Stow Navigation Matrix' : 'Deploy Autonomous Navigator & Mars Relay'}
              aria-expanded={isOpen}
              className="group flex flex-col items-center cursor-pointer focus:outline-none"
              title={isOpen ? 'Close curtain (Esc)' : 'Deploy Autonomous Navigation Matrix & Mars Relay'}
            >
              {/* Glowing Halo Aura on hover */}
              <div className="absolute -inset-1 rounded-full bg-gradient-to-r from-rose-500/25 via-signal/35 to-amber-500/25 blur-md opacity-70 group-hover:opacity-100 transition-opacity duration-300 pointer-events-none" />

              {/* Celestial Orb (Mars / Cosmic Moon sphere) */}
              <div className="relative w-7 h-7 sm:w-8 sm:h-8 rounded-full border border-line-strong bg-surface p-0.5 shadow-e2 backdrop-blur-2xl flex items-center justify-center transition-all duration-300 group-hover:scale-110 group-hover:border-signal">
                <div className="w-full h-full rounded-full overflow-hidden relative bg-gradient-to-br from-rose-500/50 via-purple-600/40 to-amber-500/40 flex items-center justify-center shadow-inner">
                  {/* Planetary craters & coordinates SVG */}
                  <svg viewBox="0 0 32 32" className="w-full h-full fill-none">
                    <circle cx="16" cy="16" r="14" stroke="rgba(244,63,94,0.4)" strokeWidth="0.8" strokeDasharray="2 3" />
                    <circle cx="10" cy="11" r="2.5" fill="rgba(251,146,60,0.35)" />
                    <circle cx="21" cy="18" r="2" fill="rgba(192,132,252,0.4)" />
                    <circle cx="14" cy="22" r="1.5" fill="rgba(244,63,94,0.35)" />
                    <path d="M 5 17 Q 16 23 27 15" stroke="rgba(255,255,255,0.45)" strokeWidth="0.6" strokeDasharray="1 2" />
                  </svg>

                  {/* Inclined Orbital Satellite Ring */}
                  <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
                    <div className="w-9 h-3.5 rounded-[100%] border border-signal/60 -rotate-25 scale-y-75 group-hover:border-signal transition-colors" />
                  </div>

                  {/* Satellite Beacon Dot */}
                  <div className="absolute top-1 right-1.5 w-1.5 h-1.5 rounded-full bg-rose-400 animate-pulse shadow-sm shadow-rose-400" />
                </div>
              </div>

              {/* Emergent Arrow below the Orb */}
              <div className="relative -mt-1.5 px-2 py-0.5 rounded-full bg-surface/95 border border-line/90 shadow-md backdrop-blur-xl flex items-center justify-center group-hover:border-signal/70 group-hover:bg-surface transition-all duration-300">
                <ChevronDown
                  className={`w-3.5 h-3.5 text-signal transition-transform duration-300 ${
                    isOpen ? 'rotate-180 -translate-y-0.5' : 'translate-y-0 group-hover:translate-y-0.5 animate-bounce'
                  }`}
                />
              </div>
            </button>
          </div>

          {/* Curtain Menu Drawer */}
          {isOpen && (
            <div
              ref={curtainRef}
              className="pointer-events-auto mt-7 w-full rounded-3xl border border-line bg-surface/95 backdrop-blur-2xl p-4 sm:p-5 shadow-e4 transition-all duration-300 max-h-[82vh] overflow-y-auto"
            >
              {/* Mars Autopilot Header & Easter Egg Banner */}
              <div className="flex flex-wrap items-center justify-between gap-3 pb-3.5 border-b border-line mb-4">
                {/* Left: Mars Relay & Interactive Coordinates */}
                <div
                  onClick={() => setEasterEggActive((prev) => !prev)}
                  className="flex items-center gap-2.5 cursor-pointer group px-2 py-1 -ml-1 rounded-xl hover:bg-inset transition-colors"
                  title="Click to toggle Mars Telemetry Console & Autopilot link"
                >
                  <div className="relative flex items-center justify-center">
                    <span className="w-2.5 h-2.5 rounded-full bg-rose-500 animate-ping absolute" />
                    <span className="w-2.5 h-2.5 rounded-full bg-rose-500 relative" />
                  </div>
                  <div>
                    <div className="flex items-center gap-1.5 font-mono text-micro uppercase tracking-wider text-ink font-semibold">
                      <span>Mars Sol-42 Orbit Relay</span>
                      <span className="px-1.5 py-0.2 rounded bg-rose-500/10 text-rose-400 text-[10px] font-bold border border-rose-500/20">
                        18.65°N 226.2°E
                      </span>
                    </div>
                    <div className="font-sans text-[11px] text-ink-3 group-hover:text-signal transition-colors">
                      Autonomous Flight Computer // Tap to open telemetry ⚡
                    </div>
                  </div>
                </div>

                {/* Right: Interactive Autopilot Mode Switcher */}
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => setAutopilotIndex((prev) => (prev + 1) % AUTOPILOT_MODES.length)}
                    className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl border border-signal/30 bg-signal/10 hover:bg-signal/20 text-signal font-mono text-micro font-medium transition-all cursor-pointer"
                    title="Switch Agent Autopilot Mode"
                  >
                    <ModeIcon className="w-3.5 h-3.5 shrink-0" />
                    <span className="hidden xs:inline">{currentMode.label}</span>
                    <span className="xs:hidden">Autopilot</span>
                  </button>

                  <button
                    type="button"
                    onClick={() => setIsOpen(false)}
                    className="p-1.5 rounded-lg text-ink-3 hover:text-ink hover:bg-inset transition-colors"
                    aria-label="Close curtain"
                    title="Close (Esc)"
                  >
                    <X className="w-4 h-4" />
                  </button>
                </div>
              </div>

              {/* Easter Egg: Autonomous Telemetry & Route Matrix */}
              {easterEggActive && (
                <div className="mb-4 p-3.5 rounded-2xl bg-ground/80 border border-signal/30 font-mono text-micro text-ink-2 space-y-2 animate-in fade-in slide-in-from-top-2">
                  <div className="flex items-center justify-between text-signal font-semibold">
                    <div className="flex items-center gap-2">
                      <Cpu className="w-3.5 h-3.5" />
                      <span>AUTONOMOUS AGENT AUTOPILOT // SOL-42 OLYMPUS MONS STATION</span>
                    </div>
                    <span className="text-meta text-emerald-400">STATUS: ONLINE (0.00% TOKEN TAX)</span>
                  </div>
                  <p className="text-ink-3 text-meta leading-relaxed">
                    Agent trajectory locked: <span className="text-ink font-medium">Earth (aslang.dev) ➔ WASI In-Memory Sandbox ➔ SkyLoom Swarm ➔ Mars Outpost</span>.
                    All 107 builtins verified. Memory matrix isolated via zero-leak sandboxing.
                  </p>
                  <div className="flex flex-wrap items-center gap-4 text-ink-4 pt-1.5 border-t border-line/40 text-[10px]">
                    <span>LATENCY: 0.04ms (In-Memory)</span>
                    <span>CARRIER: ASL/Coord Protocol</span>
                    <span>TARGET: Multi-Agent Mesh</span>
                  </div>
                </div>
              )}

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
                      activeClassName="!border-signal/50 !bg-signal/10 shadow-sm"
                    >
                      <div className="p-2 rounded-xl bg-surface border border-line text-ink-2 group-hover:text-signal group-hover:scale-105 transition-all">
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


