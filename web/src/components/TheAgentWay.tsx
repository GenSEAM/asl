import React, { useState } from 'react';
import { Compass, CheckCircle2, XCircle, ChevronDown, ChevronUp, Sparkles } from 'lucide-react';

interface HistoricalEpoch {
  era: string;
  name: string;
  summary: string;
  desc: string;
  badge: string;
  badgeColor: string;
  flaws?: string[];
}

export const TheAgentWay: React.FC = () => {
  const [hoveredEpoch, setHoveredEpoch] = useState<string | null>(null);
  const [expandedEpoch, setExpandedEpoch] = useState<string | null>(null);

  const history: HistoricalEpoch[] = [
    {
      era: '1990s',
      name: 'Object-Oriented Programming (OOP)',
      summary: 'Syntax for Compilers',
      desc: 'Humans writing manual classes, inheritance hierarchies, and verbose boilerplate line-by-line.',
      badge: 'Manual Era',
      badgeColor: 'text-craft-500 border-craft-300 dark:border-craft-800 bg-craft-100 dark:bg-craft-900',
    },
    {
      era: '2010s',
      name: 'Functional Programming (FP)',
      summary: 'Mathematical Transformations',
      desc: 'Immutability, pure functions, and monads to manage concurrent state safely.',
      badge: 'Declarative Era',
      badgeColor: 'text-blue-500 border-blue-500/30 bg-blue-500/10',
    },
    {
      era: '2023 – 2025',
      name: 'Prompt-and-Pray Generation',
      summary: 'The Fragile Transition',
      desc: 'Feeding natural language prompts into LLMs and getting hallucinated indentation, broken brackets, and 4–8 repair loops.',
      badge: 'High Friction',
      badgeColor: 'text-rose-500 border-rose-500/30 bg-rose-500/10',
      flaws: ['Indentation crashes', 'Type drift in loops', 'Context window bloat'],
    },
  ];

  const currentEra = {
    era: '2026+',
    name: 'Agentic Programming (AgP) — The Agent Way',
    summary: 'The True Paradigm of Machine Agency',
    desc: 'Deterministic single-pass S-expression contracts, A2A wire streams, and verified swarm consensus. Crafted for AI agents from first principles.',
    perks: [
      'Single-pass deterministic contracts (0 parsing crashes)',
      '–78% prompt token context reduction',
      'A2A Wire Protocol with sub-millisecond execution',
      'Minimizes hallucination drift with mathematical proof'
    ],
  };

  return (
    <section id="agent-way" className="relative py-28 border-b border-craft-200/60 dark:border-white/[0.06] bg-white dark:bg-[#05070a] transition-colors">
      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Section Header */}
        <div className="max-w-3xl mx-auto text-center mb-16">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-cyan-500/10 border border-cyan-500/30 text-cyan-600 dark:text-cyan-400 text-xs font-mono mb-4">
            <Compass className="w-3.5 h-3.5" />
            <span>Interactive Layered Timeline</span>
          </div>

          <h2 className="text-3xl sm:text-5xl font-extrabold tracking-[-0.04em] text-craft-900 dark:text-white font-sans leading-tight">
            The Agent Way.
          </h2>

          <p className="mt-4 text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans leading-relaxed tracking-[-0.01em]">
            Hover or tap previous epochs to inspect how software development evolved into <strong>Agentic Programming (AgP)</strong>.
          </p>
        </div>

        {/* Layered Interactive Deck Container */}
        <div className="space-y-3 text-left">
          
          {/* Stacked Historical Epochs Deck */}
          <div className="space-y-2.5">
            {history.map((epoch) => {
              const isOpen = hoveredEpoch === epoch.era || expandedEpoch === epoch.era;

              return (
                <div
                  key={epoch.era}
                  onMouseEnter={() => setHoveredEpoch(epoch.era)}
                  onMouseLeave={() => setHoveredEpoch(null)}
                  onClick={() => setExpandedEpoch(expandedEpoch === epoch.era ? null : epoch.era)}
                  className={`rounded-2xl border transition-all duration-300 cursor-pointer overflow-hidden backdrop-blur-xl ${
                    isOpen
                      ? 'border-craft-400 dark:border-white/[0.2] bg-white dark:bg-white/[0.03] shadow-lg'
                      : 'border-craft-200 dark:border-white/[0.06] bg-craft-50/70 dark:bg-white/[0.01] hover:border-craft-300 dark:hover:border-white/[0.12] opacity-80 hover:opacity-100'
                  }`}
                >
                  {/* Collapsed Header Strip */}
                  <div className="px-5 py-3.5 flex items-center justify-between gap-4">
                    <div className="flex items-center gap-3">
                      <span className="font-mono text-xs font-bold text-craft-400 dark:text-craft-500 w-20 shrink-0">
                        {epoch.era}
                      </span>
                      <span className="font-sans font-semibold text-sm text-craft-800 dark:text-craft-200">
                        {epoch.name}
                      </span>
                    </div>

                    <div className="flex items-center gap-3">
                      <span className={`hidden sm:inline-block px-2.5 py-0.5 rounded-full text-[10px] font-mono font-bold uppercase tracking-wider border ${epoch.badgeColor}`}>
                        {epoch.badge}
                      </span>
                      {isOpen ? (
                        <ChevronUp className="w-4 h-4 text-craft-400" />
                      ) : (
                        <ChevronDown className="w-4 h-4 text-craft-400" />
                      )}
                    </div>
                  </div>

                  {/* Expanded Drawer Details */}
                  {isOpen && (
                    <div className="px-5 pb-5 pt-2 border-t border-craft-200 dark:border-white/[0.06] text-xs space-y-3 animate-fadeIn">
                      <div className="font-mono text-craft-accent font-semibold">
                        // {epoch.summary}
                      </div>
                      <p className="text-craft-600 dark:text-craft-300 leading-relaxed font-sans">
                        {epoch.desc}
                      </p>

                      {epoch.flaws && (
                        <div className="pt-2 flex flex-wrap gap-2 font-mono text-[11px] text-rose-500">
                          {epoch.flaws.map((flaw) => (
                            <span key={flaw} className="flex items-center gap-1 bg-rose-500/10 px-2 py-0.5 rounded-md border border-rose-500/20">
                              <XCircle className="w-3 h-3" />
                              <span>{flaw}</span>
                            </span>
                          ))}
                        </div>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>

          {/* Spotlight Hero Card: 2026+ The Agent Way (Always Expanded & Elevated at Foreground) */}
          <div className="mt-4 p-8 sm:p-10 rounded-[2.5rem] border border-craft-accent/50 bg-gradient-to-b from-white dark:from-white/[0.05] via-craft-50 dark:via-[#06080d] to-white dark:to-[#04060a] backdrop-blur-2xl shadow-[0_0_50px_rgba(6,182,212,0.18)] relative overflow-hidden z-20 group">
            
            {/* Ambient Corner Glow */}
            <div className="absolute top-0 right-0 p-6 opacity-15 group-hover:opacity-25 transition-opacity">
              <Sparkles className="w-36 h-36 text-craft-accent" />
            </div>

            <div className="flex flex-wrap items-center justify-between gap-2 mb-3">
              <div className="flex items-center gap-2">
                <span className="w-2.5 h-2.5 rounded-full bg-craft-accent shadow-[0_0_10px_#06b6d4] animate-pulse" />
                <span className="font-mono text-sm font-extrabold text-craft-accent tracking-wider">
                  {currentEra.era} // CURRENT EPOCH
                </span>
              </div>
              <span className="px-3 py-1 rounded-full text-[10px] font-mono font-bold uppercase tracking-wider border border-cyan-500/40 bg-cyan-500/10 text-craft-accent shadow-sm">
                The Agent Way
              </span>
            </div>

            <h3 className="text-2xl sm:text-3xl font-extrabold text-craft-900 dark:text-white font-sans tracking-tight mb-1">
              {currentEra.name}
            </h3>

            <p className="text-xs sm:text-sm font-mono text-craft-accent font-bold mb-4">
              // {currentEra.summary}
            </p>

            <p className="text-sm sm:text-base text-craft-600 dark:text-craft-300 font-sans leading-relaxed mb-6 max-w-2xl">
              {currentEra.desc}
            </p>

            {/* Perks Grid */}
            <div className="pt-5 border-t border-craft-accent/30 grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs sm:text-sm font-sans font-medium text-craft-800 dark:text-craft-100">
              {currentEra.perks.map((perk) => (
                <div key={perk} className="flex items-center gap-2.5 text-emerald-600 dark:text-emerald-400">
                  <CheckCircle2 className="w-4 h-4 shrink-0" />
                  <span>{perk}</span>
                </div>
              ))}
            </div>

          </div>

        </div>

      </div>
    </section>
  );
};
