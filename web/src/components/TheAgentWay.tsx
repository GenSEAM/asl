import React from 'react';
import { Compass, CheckCircle2, XCircle } from 'lucide-react';

export const TheAgentWay: React.FC = () => {
  const timelineEpochs = [
    {
      era: '1990s',
      name: 'Object-Oriented Programming (OOP)',
      summary: 'Syntax for Compilers',
      desc: 'Humans writing manual classes, inheritance hierarchies, and verbose boilerplate line-by-line.',
      badge: 'Manual Era',
      badgeColor: 'text-craft-500 border-craft-300 dark:border-craft-800 bg-craft-100 dark:bg-craft-900',
      accent: 'border-craft-300 dark:border-craft-800',
      active: false,
    },
    {
      era: '2010s',
      name: 'Functional Programming (FP)',
      summary: 'Mathematical Transformations',
      desc: 'Immutability, pure functions, and monads to manage concurrent state safely.',
      badge: 'Declarative Era',
      badgeColor: 'text-blue-500 border-blue-500/30 bg-blue-500/10',
      accent: 'border-blue-500/30',
      active: false,
    },
    {
      era: '2023 – 2025',
      name: 'Prompt-and-Pray Generation',
      summary: 'The Fragile Transition',
      desc: 'Feeding natural language prompts into LLMs and getting hallucinated indentation, broken brackets, and 4–8 repair loops.',
      badge: 'High Friction',
      badgeColor: 'text-rose-500 border-rose-500/30 bg-rose-500/10',
      accent: 'border-rose-500/30',
      active: false,
      flaws: ['Indentation crashes', 'Type drift in loops', 'Context window bloat'],
    },
    {
      era: '2026+',
      name: 'Agentic Programming (AgP) — The Agent Way',
      summary: 'The True Paradigm of Machine Agency',
      desc: 'Deterministic single-pass S-expression contracts, A2A wire streams, and verified swarm consensus. Crafted for AI agents from first principles.',
      badge: 'The Agent Way',
      badgeColor: 'text-craft-accent border-cyan-500/40 bg-cyan-500/10 shadow-[0_0_15px_rgba(6,182,212,0.25)]',
      accent: 'border-craft-accent shadow-[0_0_30px_rgba(6,182,212,0.15)] bg-gradient-to-b from-white dark:from-white/[0.04] to-craft-50 dark:to-white/[0.01]',
      active: true,
      perks: [
        'Single-pass deterministic contracts (0 parsing crashes)',
        '–78% prompt token context reduction',
        'A2A Wire Protocol with sub-millisecond execution',
      ],
    },
  ];

  return (
    <section id="agent-way" className="relative py-28 border-b border-craft-200/60 dark:border-white/[0.06] bg-white dark:bg-[#05070a] transition-colors">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Section Header */}
        <div className="max-w-3xl mx-auto text-center mb-16">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-cyan-500/10 border border-cyan-500/30 text-cyan-600 dark:text-cyan-400 text-xs font-mono mb-4">
            <Compass className="w-3.5 h-3.5" />
            <span>The Evolutionary Timeline</span>
          </div>

          <h2 className="text-3xl sm:text-5xl font-extrabold tracking-[-0.04em] text-craft-900 dark:text-white font-sans leading-tight">
            The Agent Way.
          </h2>

          <p className="mt-4 text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans leading-relaxed tracking-[-0.01em]">
            Programming languages evolve to meet the dominant computing paradigm. Here is how we arrived at <strong>Agentic Programming (AgP)</strong>.
          </p>
        </div>

        {/* Chronological Evolutionary Timeline */}
        <div className="relative border-l-2 border-craft-200 dark:border-white/[0.1] ml-4 sm:ml-32 space-y-10 text-left">
          {timelineEpochs.map((epoch) => (
            <div key={epoch.era} className="relative pl-6 sm:pl-10 group">
              
              {/* Timeline Marker Dot */}
              <div className={`absolute -left-[9px] top-6 w-4 h-4 rounded-full border-2 bg-white dark:bg-[#05070a] transition-all duration-300 ${
                epoch.active
                  ? 'border-craft-accent bg-craft-accent shadow-[0_0_12px_#06b6d4] scale-125'
                  : 'border-craft-400 dark:border-craft-600 group-hover:border-craft-200'
              }`} />

              {/* Timestamp on Desktop Margin */}
              <div className="hidden sm:block absolute -left-32 top-5 w-24 text-right font-mono text-xs font-bold text-craft-400 dark:text-craft-500">
                {epoch.era}
              </div>

              {/* Epoch Card */}
              <div className={`p-6 sm:p-8 rounded-3xl border ${epoch.accent} backdrop-blur-2xl transition-all ${
                epoch.active
                  ? 'bg-craft-50/80 dark:bg-white/[0.03]'
                  : 'bg-white/60 dark:bg-white/[0.01] hover:border-craft-400 dark:hover:border-white/[0.15]'
              }`}>
                <div className="flex flex-wrap items-center justify-between gap-2 mb-2">
                  <span className="sm:hidden font-mono text-xs font-bold text-craft-accent">
                    {epoch.era}
                  </span>
                  <span className={`px-3 py-1 rounded-full text-[10px] font-mono font-bold uppercase tracking-wider border ${epoch.badgeColor}`}>
                    {epoch.badge}
                  </span>
                </div>

                <h3 className={`text-xl sm:text-2xl font-bold font-sans tracking-tight ${
                  epoch.active ? 'text-craft-900 dark:text-white' : 'text-craft-800 dark:text-craft-200'
                }`}>
                  {epoch.name}
                </h3>
                
                <p className="text-xs sm:text-sm font-mono text-craft-accent font-semibold mt-0.5 mb-2">
                  // {epoch.summary}
                </p>

                <p className="text-sm text-craft-600 dark:text-craft-300 font-sans leading-relaxed">
                  {epoch.desc}
                </p>

                {/* Specific Flaws (for 2023 Prompt & Pray) */}
                {epoch.flaws && (
                  <div className="mt-4 pt-3 border-t border-rose-500/20 flex flex-wrap gap-2 text-xs font-mono text-rose-500">
                    {epoch.flaws.map((flaw) => (
                      <span key={flaw} className="flex items-center gap-1 bg-rose-500/10 px-2.5 py-1 rounded-lg border border-rose-500/20">
                        <XCircle className="w-3.5 h-3.5" />
                        <span>{flaw}</span>
                      </span>
                    ))}
                  </div>
                )}

                {/* Specific Perks (for 2026+ AgP) */}
                {epoch.perks && (
                  <div className="mt-5 pt-4 border-t border-craft-accent/30 space-y-2 text-xs sm:text-sm font-sans text-craft-800 dark:text-craft-100 font-medium">
                    {epoch.perks.map((perk) => (
                      <div key={perk} className="flex items-center gap-2 text-emerald-600 dark:text-emerald-400">
                        <CheckCircle2 className="w-4 h-4 shrink-0" />
                        <span>{perk}</span>
                      </div>
                    ))}
                  </div>
                )}

              </div>
            </div>
          ))}
        </div>

      </div>
    </section>
  );
};
