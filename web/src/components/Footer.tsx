import React, { useState } from 'react';
import { Logo } from './ui/Logo';

interface ChameleonPose {
  quote: string;
  badge: string;
  transform: string;
  filter: string;
  glow: string;
}

const CHAMELEON_POSES: ChameleonPose[] = [
  {
    quote: "Psst! You made it all the way to the end of the runtime.",
    badge: "Resting on AST Branch",
    transform: "scale(1) rotate(0deg) translate(0px, 0px)",
    filter: "hue-rotate(0deg) brightness(1)",
    glow: "rgba(168, 85, 247, 0.25)",
  },
  {
    quote: "Turning around to scan the left flank... 👀",
    badge: "Scanning Left Flank",
    transform: "scale(-1, 1) rotate(6deg) translate(0px, -8px)",
    filter: "hue-rotate(95deg) brightness(1.1)", // Emerald
    glow: "rgba(16, 185, 129, 0.3)",
  },
  {
    quote: "Cyber Camouflage active! Blending into the syntax tree.",
    badge: "Cyber Cyan Camouflage",
    transform: "scale(-1.08, 1.08) rotate(-8deg) translate(0px, -12px)",
    filter: "hue-rotate(165deg) brightness(1.15)", // Cyan
    glow: "rgba(6, 182, 212, 0.35)",
  },
  {
    quote: "Stretching upward on the branch! Ergonomic posture checked.",
    badge: "Amber Sunbathing",
    transform: "scale(1.12) rotate(-10deg) translate(0px, -10px)",
    filter: "hue-rotate(245deg) brightness(1.1)", // Gold/Amber
    glow: "rgba(245, 158, 11, 0.3)",
  },
  {
    quote: "Caught a memory leak with my sticky tongue! 🪰",
    badge: "Bug Catcher Stance",
    transform: "scale(0.95) rotate(14deg) translate(0px, 4px)",
    filter: "hue-rotate(315deg) brightness(1.1)", // Ruby Pink
    glow: "rgba(244, 63, 94, 0.3)",
  },
  {
    quote: "Tail curled tight! Formal verification reaches EOF. 🦎",
    badge: "Zero-Heap Totality",
    transform: "scale(1.06) rotate(3deg) translate(0px, -4px)",
    filter: "hue-rotate(0deg) saturate(1.4)", // Deep ASL Purple
    glow: "rgba(168, 85, 247, 0.35)",
  },
];

export const Footer: React.FC = () => {
  const [poseIndex, setPoseIndex] = useState(0);
  const [isBouncing, setIsBouncing] = useState(false);

  const currentPose = CHAMELEON_POSES[poseIndex];

  const handleChameleonClick = () => {
    setIsBouncing(true);
    setPoseIndex((prev) => (prev + 1) % CHAMELEON_POSES.length);
    setTimeout(() => setIsBouncing(false), 450);
  };

  return (
    <footer className="relative pt-12 pb-14 border-t border-line bg-sunken/60">
      {/* Interactive Animated Chameleon Easter Egg */}
      <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 mb-8 flex flex-col items-center justify-center">
        <button
          type="button"
          onClick={handleChameleonClick}
          className="group relative flex flex-col items-center focus:outline-none cursor-pointer select-none"
          title="Click to poke the chameleon and watch him move!"
          aria-label="AgentScript Mascot Chameleon Easter Egg - Click to interact"
        >
          {/* Emergent Speech Bubble */}
          <div className="opacity-0 group-hover:opacity-100 transition-all duration-300 transform translate-y-1 group-hover:translate-y-0 mb-3 px-3.5 py-1.5 rounded-2xl bg-surface/95 backdrop-blur-xl border border-line shadow-e2 text-micro font-mono text-ink flex items-center gap-2 pointer-events-none z-20">
            <span className="w-1.5 h-1.5 rounded-full bg-signal animate-pulse shrink-0" />
            <span>{currentPose.quote}</span>
          </div>

          <div className="relative">
            {/* Ambient dynamic glow changing with chameleon color */}
            <div
              className="absolute inset-0 rounded-full blur-2xl transition-all duration-500 scale-125 pointer-events-none"
              style={{ backgroundColor: currentPose.glow }}
            />

            {/* Chameleon with springy multi-pose transform & color camouflaging */}
            <img
              src="/chameleon.png"
              alt="AgentScript Mascot Chameleon"
              width="130"
              height="138"
              className={`relative z-10 w-24 sm:w-28 h-auto select-none drop-shadow-[0_12px_24px_rgba(0,0,0,0.25)] ${
                isBouncing ? 'animate-bounce' : ''
              }`}
              style={{
                transform: currentPose.transform,
                filter: currentPose.filter,
                transition: 'transform 0.45s cubic-bezier(0.34, 1.56, 0.64, 1), filter 0.6s ease',
              }}
            />
          </div>

          {/* Interactive hint & current pose badge */}
          <div className="mt-3 flex items-center gap-1.5 font-mono text-2xs uppercase tracking-wider text-ink-3 group-hover:text-signal transition-colors">
            <span className="font-semibold">{currentPose.badge}</span>
            <span className="text-ink-4">• click to poke 🦎</span>
          </div>
        </button>
      </div>

      <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 flex flex-col md:flex-row md:items-center justify-between gap-6">
      <div className="flex items-center gap-3">
        <Logo className="w-7 h-7 text-signal" />
        <span className="flex items-baseline gap-2">
          <span className="font-sans font-semibold text-ink text-brand">
            aslang<span className="text-signal">.dev</span>
          </span>
          <span className="font-mono text-meta text-ink-3">ASL Agent Core</span>
        </span>
      </div>

      <nav aria-label="Footer" className="flex flex-wrap items-center gap-6 font-mono text-meta">
        <a href="#agent-way" className="text-ink-2 hover:text-ink transition-colors">
          Specification
        </a>
        <a href="#capabilities" className="text-ink-2 hover:text-ink transition-colors">
          Capabilities
        </a>
        <a href="#toolchain" className="text-ink-2 hover:text-ink transition-colors">
          Ecosystem
        </a>
        <a href="https://github.com/genseam/asl" target="_blank" rel="noreferrer" className="text-ink-2 hover:text-ink transition-colors">
          GitHub
        </a>
        <a href="/llms.txt" className="text-ink-2 hover:text-ink transition-colors">
          Security
        </a>
      </nav>

      <a
        href="/llms.txt"
        className="font-mono text-micro text-ink-3 hover:text-signal transition-colors flex items-center gap-1.5"
      >
        <span className="w-1.5 h-1.5 rounded-full bg-signal" />
        <span>Agent Spec (llms.txt)</span>
      </a>
    </div>

    <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 mt-8 pt-6 border-t border-line/60 flex flex-col sm:flex-row items-center justify-between gap-4 font-mono text-micro text-ink-3">
      <p>MIT licensed. Single-pass S-expression language for autonomous agents.</p>
      <p>Formally verified determinism across runtimes.</p>
    </div>
  </footer>
  );
};
