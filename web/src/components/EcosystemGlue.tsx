import React from 'react';
import { Sparkles, Brain, Network, HeartHandshake, Compass, Users } from 'lucide-react';

export const EcosystemGlue: React.FC = () => {
  return (
    <section className="relative py-28 border-b border-craft-200 dark:border-craft-800/80 bg-white dark:bg-craft-950 overflow-hidden transition-colors">
      {/* Ambient Neural Backlight */}
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[800px] h-[500px] bg-purple-500/10 dark:bg-purple-500/15 blur-[160px] rounded-full pointer-events-none" />

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Section Manifesto Heading */}
        <div className="max-w-3xl mx-auto text-center mb-16">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-purple-500/10 border border-purple-500/30 text-purple-600 dark:text-purple-400 text-xs font-mono mb-4">
            <Compass className="w-3.5 h-3.5" />
            <span>The Substrate of Collective Intelligence</span>
          </div>

          <h2 className="text-3xl sm:text-5xl font-extrabold tracking-[-0.035em] text-craft-900 dark:text-craft-50 font-sans leading-tight">
            Language as the Ecosystem Glue.
          </h2>

          <p className="mt-4 text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans leading-relaxed">
            Programming is no longer about solitary manual syntax. It is the art of giving agency to thought, binding diverse autonomous minds into a harmonious society that amplifies human creativity.
          </p>
        </div>

        {/* 4-Tier Symbiosis Bento Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
          
          {/* Tile 1: Human Intent & Cognition */}
          <div className="lg:col-span-4 p-8 rounded-3xl border border-craft-200 dark:border-craft-800/80 bg-craft-50/70 dark:bg-craft-900/50 backdrop-blur-xl hover:border-craft-accent/50 hover:shadow-glow-md transition-all text-left flex flex-col justify-between group">
            <div>
              <div className="w-12 h-12 rounded-2xl bg-craft-100 dark:bg-craft-800 border border-craft-200 dark:border-craft-700 flex items-center justify-center text-craft-accent mb-6 group-hover:scale-110 transition-transform">
                <Brain className="w-6 h-6 text-craft-cyan" />
              </div>
              <span className="text-xs font-mono uppercase tracking-wider text-craft-accent font-bold">Tier 01 // Intent</span>
              <h3 className="text-xl font-bold text-craft-900 dark:text-craft-100 mt-1 mb-3">
                Human Will & Vision
              </h3>
              <p className="text-sm text-craft-600 dark:text-craft-300 leading-relaxed font-sans">
                You provide the direction, values, and creative spark. Voice streams, concepts, and high-level aspirations become actionable prompts.
              </p>
            </div>
            <div className="mt-6 pt-4 border-t border-craft-200 dark:border-craft-800/80 text-xs font-mono text-craft-500 flex items-center gap-2">
              <HeartHandshake className="w-4 h-4 text-craft-emerald" />
              <span>Zero-Friction Ergonomics</span>
            </div>
          </div>

          {/* Tile 2: The Universal ASL Substrate */}
          <div className="lg:col-span-4 p-8 rounded-3xl border border-craft-accent/50 bg-gradient-to-b from-craft-100 dark:from-craft-900/90 to-white dark:to-craft-950 backdrop-blur-xl shadow-glow-sm hover:shadow-glow-lg transition-all text-left flex flex-col justify-between relative overflow-hidden group">
            <div className="absolute top-0 right-0 p-3 opacity-20 group-hover:opacity-40 transition-opacity">
              <span className="font-mono text-6xl font-black text-craft-accent">λ</span>
            </div>
            <div>
              <div className="w-12 h-12 rounded-2xl bg-craft-accent text-craft-950 flex items-center justify-center font-mono font-bold text-xl mb-6 shadow-glow-sm group-hover:scale-110 transition-transform">
                λ
              </div>
              <span className="text-xs font-mono uppercase tracking-wider text-craft-accent font-bold">Tier 02 // Language Substrate</span>
              <h3 className="text-xl font-bold text-craft-900 dark:text-craft-100 mt-1 mb-3">
                ASL Nano Ecosystem Glue
              </h3>
              <p className="text-sm text-craft-600 dark:text-craft-300 leading-relaxed font-sans">
                The single-pass mathematical contract. It eliminates hallucinated syntax, encodes type invariants, and lets agents communicate without ambiguity.
              </p>
            </div>
            <div className="mt-6 pt-4 border-t border-craft-200 dark:border-craft-800 text-xs font-mono text-craft-accent font-semibold flex items-center gap-2">
              <Sparkles className="w-4 h-4" />
              <span>100% Deterministic Contract</span>
            </div>
          </div>

          {/* Tile 3: Autonomous Agent Society */}
          <div className="lg:col-span-4 p-8 rounded-3xl border border-craft-200 dark:border-craft-800/80 bg-craft-50/70 dark:bg-craft-900/50 backdrop-blur-xl hover:border-craft-accent/50 hover:shadow-glow-md transition-all text-left flex flex-col justify-between group">
            <div>
              <div className="w-12 h-12 rounded-2xl bg-craft-100 dark:bg-craft-800 border border-craft-200 dark:border-craft-700 flex items-center justify-center text-purple-500 mb-6 group-hover:scale-110 transition-transform">
                <Users className="w-6 h-6 text-craft-purple" />
              </div>
              <span className="text-xs font-mono uppercase tracking-wider text-craft-purple font-bold">Tier 03 // Society</span>
              <h3 className="text-xl font-bold text-craft-900 dark:text-craft-100 mt-1 mb-3">
                Autonomous Agent Society
              </h3>
              <p className="text-sm text-craft-600 dark:text-craft-300 leading-relaxed font-sans">
                Specialized subagents (Planners, Coders, Gate Auditors, Metasearchers) collaborate concurrently, refining work through verified peer consensus.
              </p>
            </div>
            <div className="mt-6 pt-4 border-t border-craft-200 dark:border-craft-800/80 text-xs font-mono text-craft-500 flex items-center gap-2">
              <Network className="w-4 h-4 text-purple-400" />
              <span>Inter-Agent SSE Mesh</span>
            </div>
          </div>

        </div>

        {/* Vision Quote Banner */}
        <div className="mt-12 p-8 rounded-3xl border border-craft-200 dark:border-craft-800 bg-gradient-to-r from-craft-100/60 dark:from-craft-900/60 via-craft-50 dark:via-craft-950 to-craft-100/60 dark:to-craft-900/60 backdrop-blur-xl text-center">
          <p className="text-base sm:text-xl font-sans font-medium text-craft-800 dark:text-craft-200 max-w-3xl mx-auto italic">
            "When tools share a common language of intent and proof, complexity ceases to be a barrier. Human beings are freed to imagine, explore, and create at the speed of thought."
          </p>
          <div className="mt-3 font-mono text-xs text-craft-accent font-semibold">
            — The ASL Ecosystem Manifesto
          </div>
        </div>

      </div>
    </section>
  );
};
