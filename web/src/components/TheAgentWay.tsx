import React, { useState } from 'react';
import { CheckCircle2, XCircle, ChevronDown, ChevronUp, Folder } from 'lucide-react';

interface HistoricalEpoch {
  id: string;
  era: string;
  name: string;
  summary: string;
  desc: string;
  badge: string;
  badgeColor: string;
  flaws?: string[];
  tabColor: string;
}

export const TheAgentWay: React.FC = () => {
  const [activeHoverId, setActiveHoverId] = useState<string | null>(null);

  const history: HistoricalEpoch[] = [
    {
      id: 'oop',
      era: '1990s',
      name: 'Object-Oriented Programming (OOP)',
      summary: 'Syntax for Compilers',
      desc: 'Humans writing manual classes, inheritance hierarchies, and verbose boilerplate line-by-line.',
      badge: 'Manual Era',
      badgeColor: 'text-craft-500 border-craft-300 dark:border-craft-800 bg-craft-100 dark:bg-craft-900',
      tabColor: 'border-craft-300 dark:border-white/[0.1] bg-craft-100/90 dark:bg-[#0a0d14]',
    },
    {
      id: 'fp',
      era: '2010s',
      name: 'Functional Programming (FP)',
      summary: 'Mathematical Transformations',
      desc: 'Immutability, pure functions, and monads to manage concurrent state safely.',
      badge: 'Declarative Era',
      badgeColor: 'text-blue-500 border-blue-500/30 bg-blue-500/10',
      tabColor: 'border-blue-500/30 bg-blue-500/5 dark:bg-[#080c18]',
    },
    {
      id: 'prompt',
      era: '2023 – 2025',
      name: 'Prompt-and-Pray Generation',
      summary: 'The Fragile Transition',
      desc: 'Feeding natural language prompts into LLMs and getting hallucinated indentation, broken brackets, and 4–8 repair loops.',
      badge: 'High Friction',
      badgeColor: 'text-rose-500 border-rose-500/30 bg-rose-500/10',
      flaws: ['Indentation crashes', 'Type drift in loops', 'Context window bloat'],
      tabColor: 'border-rose-500/30 bg-rose-500/5 dark:bg-[#140a0e]',
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
            <Folder className="w-3.5 h-3.5" />
            <span>Overlapping Paradigm Archive</span>
          </div>

          <h2 className="text-3xl sm:text-5xl font-extrabold tracking-[-0.04em] text-craft-900 dark:text-white font-sans leading-tight">
            The Agent Way.
          </h2>

          <p className="mt-4 text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans leading-relaxed tracking-[-0.01em]">
            Hover over any archived epoch in the deck to reveal its historical constraints. The culmination at the foreground is <strong>Agentic Programming (AgP)</strong>.
          </p>
        </div>

        {/* Physical Overlapping Archive Stack */}
        <div className="relative pt-6 pb-4 text-left">
          
          {history.map((epoch, idx) => {
            const isHovered = activeHoverId === epoch.id;
            const zIndex = isHovered ? 40 : (idx + 1) * 10;
            const negativeMargin = idx === 0 ? '' : '-mt-10 sm:-mt-12';

            return (
              <div
                key={epoch.id}
                onMouseEnter={() => setActiveHoverId(epoch.id)}
                onMouseLeave={() => setActiveHoverId(null)}
                style={{ zIndex }}
                className={`relative rounded-3xl border ${epoch.tabColor} transition-all duration-500 ease-out shadow-2xl backdrop-blur-2xl ${negativeMargin} ${
                  isHovered
                    ? '-translate-y-6 sm:-translate-y-8 shadow-[0_15px_30px_rgba(0,0,0,0.5)] border-craft-400 dark:border-white/[0.25]'
                    : 'hover:-translate-y-2 opacity-90 hover:opacity-100'
                }`}
              >
                {/* Archive Folder Header Lip */}
                <div className="px-6 py-4 flex items-center justify-between gap-4 cursor-pointer">
                  <div className="flex items-center gap-3">
                    <span className="font-mono text-xs font-bold text-craft-400 dark:text-craft-500 w-24 shrink-0">
                      {epoch.era}
                    </span>
                    <span className="font-sans font-bold text-sm sm:text-base text-craft-800 dark:text-craft-200">
                      {epoch.name}
                    </span>
                  </div>

                  <div className="flex items-center gap-3">
                    <span className={`hidden sm:inline-block px-2.5 py-0.5 rounded-full text-[10px] font-mono font-bold uppercase tracking-wider border ${epoch.badgeColor}`}>
                      {epoch.badge}
                    </span>
                    {isHovered ? (
                      <ChevronUp className="w-4 h-4 text-cyan-400" />
                    ) : (
                      <ChevronDown className="w-4 h-4 text-craft-400" />
                    )}
                  </div>
                </div>

                {/* Sliding Archive Drawer Content */}
                <div
                  className={`overflow-hidden transition-all duration-500 ease-out ${
                    isHovered ? 'max-h-60 px-6 pb-6 pt-1 opacity-100' : 'max-h-0 px-6 pb-0 pt-0 opacity-0'
                  }`}
                >
                  <div className="pt-3 border-t border-craft-200 dark:border-white/[0.06] text-xs space-y-3 font-sans">
                    <div className="font-mono text-cyan-400 font-semibold text-xs">
                      // {epoch.summary}
                    </div>
                    <p className="text-craft-600 dark:text-craft-300 leading-relaxed">
                      {epoch.desc}
                    </p>

                    {epoch.flaws && (
                      <div className="pt-2 flex flex-wrap gap-2 font-mono text-[11px] text-rose-500">
                        {epoch.flaws.map((flaw) => (
                          <span key={flaw} className="flex items-center gap-1 bg-rose-500/10 px-2.5 py-1 rounded-md border border-rose-500/20">
                            <XCircle className="w-3.5 h-3.5" />
                            <span>{flaw}</span>
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              </div>
            );
          })}

          {/* Front Archive Masterpiece: 2026+ The Agent Way (Overlapping on Top & Permanently Expanded) */}
          <div
            style={{ zIndex: 50 }}
            className="relative -mt-10 sm:-mt-12 p-8 sm:p-10 rounded-[2.5rem] border border-cyan-500/40 bg-gradient-to-b from-white dark:from-[#0d121c] via-craft-50 dark:via-[#090c14] to-white dark:to-[#07090e] backdrop-blur-2xl shadow-[0_20px_50px_rgba(0,0,0,0.6)] transition-all"
          >
            <div className="flex flex-wrap items-center justify-between gap-2 mb-3">
              <div className="flex items-center gap-2">
                <span className="w-2.5 h-2.5 rounded-full bg-cyan-400" />
                <span className="font-mono text-sm font-bold text-cyan-400 tracking-wider">
                  {currentEra.era} // CURRENT EPOCH
                </span>
              </div>
              <span className="px-3 py-1 rounded-full text-[10px] font-mono font-bold uppercase tracking-wider border border-cyan-500/30 bg-cyan-500/10 text-cyan-400">
                The Agent Way
              </span>
            </div>

            <h3 className="text-2xl sm:text-3xl font-extrabold text-craft-900 dark:text-white font-sans tracking-tight mb-1">
              {currentEra.name}
            </h3>

            <p className="text-xs sm:text-sm font-mono text-cyan-400 font-semibold mb-4">
              // {currentEra.summary}
            </p>

            <p className="text-sm sm:text-base text-craft-600 dark:text-craft-300 font-sans leading-relaxed mb-6 max-w-2xl">
              {currentEra.desc}
            </p>

            {/* Perks Grid */}
            <div className="pt-5 border-t border-craft-200 dark:border-white/[0.08] grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs sm:text-sm font-sans font-medium text-craft-800 dark:text-craft-100">
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
