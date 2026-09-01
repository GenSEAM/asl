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
  perks?: string[];
  isCurrent?: boolean;
}

export const TheAgentWay: React.FC = () => {
  const [activeId, setActiveId] = useState<string>('agp');

  const epochs: HistoricalEpoch[] = [
    {
      id: 'oop',
      era: '1990s',
      name: 'Object-Oriented Programming (OOP)',
      summary: 'Syntax for Compilers',
      desc: 'Humans writing manual classes, inheritance hierarchies, and verbose boilerplate line-by-line.',
      badge: 'Manual Era',
      badgeColor: 'text-craft-500 border-craft-300 dark:border-craft-800 bg-craft-100 dark:bg-craft-900',
      flaws: ['Rigid inheritance hierarchies', 'State mutation hazards', 'Human typing friction'],
    },
    {
      id: 'fp',
      era: '2010s',
      name: 'Functional Programming (FP)',
      summary: 'Mathematical Transformations',
      desc: 'Immutability, pure functions, and monads to manage concurrent state safely.',
      badge: 'Declarative Era',
      badgeColor: 'text-blue-500 border-blue-500/30 bg-blue-500/10',
      flaws: ['Complex type acrobatics', 'Performance overhead in naive runtimes'],
    },
    {
      id: 'prompt',
      era: '2023 – 2025',
      name: 'Prompt-and-Pray Generation',
      summary: 'The Fragile Transition',
      desc: 'Feeding natural language prompts into LLMs and getting hallucinated indentation, broken brackets, and 4–8 repair loops.',
      badge: 'High Friction',
      badgeColor: 'text-rose-500 border-rose-500/30 bg-rose-500/10',
      flaws: ['Indentation syntax crashes', 'Silent semantic drift in loops', 'Context window explosion'],
    },
    {
      id: 'agp',
      era: '2026+',
      name: 'Agentic Programming (AgP) — The Agent Way',
      summary: 'The True Paradigm of Machine Agency',
      desc: 'Deterministic single-pass S-expression contracts, A2A wire streams, and verified swarm consensus. Crafted for AI agents from first principles.',
      badge: 'Current Paradigm',
      badgeColor: 'text-cyan-400 border-cyan-500/30 bg-cyan-500/10',
      isCurrent: true,
      perks: [
        'Single-pass deterministic contracts (0 parsing crashes)',
        '–78% prompt token context reduction',
        'A2A Wire Protocol with sub-millisecond execution',
        'Minimizes hallucination drift with mathematical proof'
      ],
    },
  ];

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
            Hover or click any epoch tab in the deck to reveal its historical constraints. The cards above and below smoothly shift to keep all navigation visible.
          </p>
        </div>

        {/* Dynamic Physical Archive Deck */}
        <div 
          className="flex flex-col gap-3 text-left"
          onMouseLeave={() => setActiveId('agp')}
        >
          {epochs.map((epoch) => {
            const isExpanded = activeId === epoch.id;

            return (
              <div
                key={epoch.id}
                onMouseEnter={() => setActiveId(epoch.id)}
                onClick={() => setActiveId(epoch.id)}
                className={`rounded-3xl border transition-all duration-300 backdrop-blur-2xl cursor-pointer ${
                  isExpanded
                    ? epoch.isCurrent
                      ? 'border-cyan-500/60 bg-gradient-to-b from-white dark:from-[#0d121c] via-craft-50 dark:via-[#090c14] to-white dark:to-[#07090e] shadow-[0_20px_50px_rgba(0,0,0,0.4)]'
                      : 'border-craft-400 dark:border-white/[0.25] bg-craft-50/90 dark:bg-[#0c101a] shadow-xl'
                    : 'border-craft-200 dark:border-white/[0.08] bg-craft-100/60 dark:bg-[#07090e]/80 hover:border-craft-300 dark:hover:border-white/[0.15] opacity-85 hover:opacity-100'
                }`}
              >
                {/* Archive Folder Header Tab */}
                <div className="px-6 py-4 flex items-center justify-between gap-4">
                  <div className="flex items-center gap-3">
                    {epoch.isCurrent && (
                      <span className="w-2.5 h-2.5 rounded-full bg-cyan-400 shrink-0" />
                    )}
                    <span className="font-mono text-xs font-bold text-craft-400 dark:text-craft-500 w-24 shrink-0">
                      {epoch.era}
                    </span>
                    <span className={`font-sans font-bold text-sm sm:text-base ${
                      isExpanded && epoch.isCurrent
                        ? 'text-cyan-600 dark:text-cyan-300'
                        : 'text-craft-800 dark:text-craft-200'
                    }`}>
                      {epoch.name}
                    </span>
                  </div>

                  <div className="flex items-center gap-3">
                    <span className={`hidden sm:inline-block px-2.5 py-0.5 rounded-full text-[10px] font-mono font-bold uppercase tracking-wider border ${epoch.badgeColor}`}>
                      {epoch.badge}
                    </span>
                    {isExpanded ? (
                      <ChevronUp className="w-4 h-4 text-cyan-400" />
                    ) : (
                      <ChevronDown className="w-4 h-4 text-craft-400" />
                    )}
                  </div>
                </div>

                {/* Sliding Archive Drawer Content */}
                <div
                  className={`overflow-hidden transition-all duration-300 ease-out ${
                    isExpanded ? 'max-h-96 px-6 pb-6 pt-1 opacity-100' : 'max-h-0 px-6 pb-0 pt-0 opacity-0'
                  }`}
                >
                  <div className="pt-3 border-t border-craft-200 dark:border-white/[0.06] text-xs sm:text-sm space-y-3 font-sans">
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

                    {epoch.perks && (
                      <div className="pt-3 grid grid-cols-1 sm:grid-cols-2 gap-2 text-xs font-medium text-emerald-600 dark:text-emerald-400">
                        {epoch.perks.map((perk) => (
                          <div key={perk} className="flex items-center gap-2">
                            <CheckCircle2 className="w-4 h-4 shrink-0" />
                            <span>{perk}</span>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                </div>

              </div>
            );
          })}
        </div>

      </div>
    </section>
  );
};
