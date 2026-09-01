import React, { useState } from 'react';
import { ArrowRight, Terminal, Check, Brain, Network, Compass } from 'lucide-react';

export const Hero: React.FC = () => {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText('curl -fsSL https://aslang.dev/install.sh | bash');
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <section className="relative pt-16 pb-28 border-b border-craft-200/80 dark:border-craft-800/80 bg-white dark:bg-craft-950 grid-mesh overflow-hidden transition-colors">
      {/* Dynamic Ambient Glow Cones */}
      <div className="absolute top-0 right-1/4 w-[700px] h-[450px] bg-craft-accent/15 blur-[150px] rounded-full pointer-events-none" />
      <div className="absolute top-1/3 left-5 w-[500px] h-[350px] bg-purple-500/10 blur-[130px] rounded-full pointer-events-none" />

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Two-Column Asymmetrical Grid: Human Intent & Manifesto on Left, Golden Spiral Society on Right */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12 items-center">
          
          {/* Left Column: Conceptual Manifesto */}
          <div className="lg:col-span-7 space-y-6 text-left">
            {/* Live Telemetry Pill */}
            <div className="inline-flex items-center gap-2.5 px-4 py-1.5 rounded-full border border-craft-200 dark:border-craft-700/80 bg-craft-100/90 dark:bg-craft-900/90 backdrop-blur-xl text-xs font-mono text-craft-800 dark:text-craft-accent shadow-sm">
              <span className="relative flex h-2 w-2">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-craft-accent opacity-75" />
                <span className="relative inline-flex rounded-full h-2 w-2 bg-craft-accent" />
              </span>
              <span className="font-semibold tracking-wide">ECOSYSTEM OF MIND // THE AGENT SOCIETY</span>
            </div>

            {/* Monumental Display Headline */}
            <h1 className="text-4xl sm:text-6xl lg:text-[4.2rem] font-extrabold tracking-[-0.04em] font-sans leading-[1.06] text-craft-900 dark:text-craft-50">
              The Universal Language for the{' '}
              <span className="bg-gradient-to-r from-craft-accent via-teal-400 to-emerald-400 bg-clip-text text-transparent">
                Agent Society.
              </span>
            </h1>

            {/* High-Concept Vision Narrative */}
            <p className="text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans leading-relaxed max-w-xl">
              <strong>ASL</strong> is the infrastructure glue uniting human intent with self-organizing societies of autonomous agents. Expanding the boundaries of human thought through radical agent autonomy, mathematical proof, and friction-free symbiosis.
            </p>

            {/* Fast-Track 1-Line Installer Card */}
            <div className="p-3.5 rounded-2xl border border-craft-200 dark:border-craft-800 bg-craft-50/90 dark:bg-craft-900/90 backdrop-blur-xl shadow-xl max-w-xl transition-all">
              <div className="flex items-center justify-between text-[11px] text-craft-500 dark:text-craft-400 mb-2 px-1 border-b border-craft-200 dark:border-craft-800/80 pb-2">
                <span className="flex items-center gap-1.5 font-bold font-mono text-craft-800 dark:text-craft-200">
                  <Terminal className="w-3.5 h-3.5 text-craft-accent" />
                  <span>Instant Installation</span>
                </span>
                <span className="font-mono text-craft-400 dark:text-craft-500 text-[10px]">macOS / Linux / WSL</span>
              </div>
              
              <div className="flex items-center justify-between gap-3 bg-white dark:bg-craft-950 px-3.5 py-2.5 rounded-xl border border-craft-200 dark:border-craft-800 shadow-inner">
                <code className="text-craft-900 dark:text-craft-accent font-mono text-xs sm:text-sm select-all overflow-x-auto whitespace-nowrap">
                  curl -fsSL https://aslang.dev/install.sh | bash
                </code>
                <button
                  onClick={handleCopy}
                  className="px-3.5 py-1.5 rounded-lg bg-craft-200 dark:bg-craft-800 hover:bg-craft-300 dark:hover:bg-craft-700 text-craft-800 dark:text-craft-100 font-mono text-xs transition-all flex items-center gap-1.5 shrink-0"
                >
                  {copied ? (
                    <>
                      <Check className="w-3.5 h-3.5 text-craft-emerald" />
                      <span className="text-craft-emerald font-semibold">Copied!</span>
                    </>
                  ) : (
                    <span>Copy</span>
                  )}
                </button>
              </div>
            </div>

            {/* Primary Action Buttons */}
            <div className="flex flex-wrap gap-4 items-center font-mono pt-2">
              <a
                href="#eddie"
                className="px-6 py-3.5 rounded-xl bg-craft-accent text-craft-950 font-bold text-sm hover:bg-craft-accent/90 hover:scale-[1.02] active:scale-[0.98] transition-all flex items-center gap-2 shadow-glow-md"
              >
                <span>Explore the Agent Swarm</span>
                <ArrowRight className="w-4 h-4" />
              </a>
              <a
                href="#skills"
                className="px-6 py-3.5 rounded-xl bg-craft-100 dark:bg-craft-900 border border-craft-200 dark:border-craft-700/80 text-craft-800 dark:text-craft-100 text-sm hover:border-craft-accent hover:text-craft-accent transition-all flex items-center gap-2"
              >
                <Compass className="w-4 h-4 text-craft-accent" />
                <span>Ecosystem Skills Hub</span>
              </a>
            </div>
          </div>

          {/* Right Column: The Golden Spiral Agent Society Artwork with Holographic HUD */}
          <div className="lg:col-span-5 relative">
            <div className="relative rounded-3xl border border-craft-200 dark:border-craft-800/90 bg-craft-100/40 dark:bg-craft-900/60 p-3.5 backdrop-blur-2xl shadow-2xl overflow-hidden group">
              <img
                src="/assets/images/agent_society.jpg"
                alt="Interconnected Autonomous Agent Society"
                className="w-full h-auto rounded-2xl object-cover shadow-inner group-hover:scale-105 transition-transform duration-700"
              />

              {/* Floating Overlapping Telemetry Pills */}
              <div className="absolute top-7 left-7 p-3 rounded-2xl bg-white/90 dark:bg-craft-950/90 backdrop-blur-xl border border-craft-200/80 dark:border-craft-700/80 shadow-xl text-left font-mono">
                <div className="flex items-center gap-2 text-[10px] text-craft-accent font-bold">
                  <Brain className="w-3.5 h-3.5 text-craft-cyan animate-pulse" />
                  <span>COLLECTIVE INTELLIGENCE</span>
                </div>
                <div className="text-[11px] text-craft-800 dark:text-craft-100 font-semibold mt-0.5">
                  100+ SPECIALIZED AGENTS
                </div>
                <div className="text-[9px] text-craft-emerald font-medium">HARMONIOUS SYNERGY</div>
              </div>

              <div className="absolute bottom-7 right-7 p-3 rounded-2xl bg-white/90 dark:bg-craft-950/90 backdrop-blur-xl border border-craft-200/80 dark:border-craft-700/80 shadow-xl text-right font-mono">
                <div className="flex items-center justify-end gap-1.5 text-[10px] text-purple-500 font-bold">
                  <Network className="w-3.5 h-3.5 text-craft-purple animate-pulse" />
                  <span>ASL GLUE PROTOCOL</span>
                </div>
                <div className="text-[11px] text-craft-800 dark:text-craft-100 font-semibold mt-0.5">
                  ZERO-LOSS COGNITION
                </div>
                <div className="text-[9px] text-craft-accent font-medium">DISPATCH &lt;0.04ms</div>
              </div>
            </div>

            {/* Ambient Radial Accent */}
            <div className="absolute -bottom-8 -right-8 w-40 h-40 bg-purple-500/20 blur-3xl rounded-full pointer-events-none" />
          </div>

        </div>

      </div>
    </section>
  );
};
