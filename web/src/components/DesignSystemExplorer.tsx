import React, { useState } from 'react';
import { Sliders, Code2, Copy, Check } from 'lucide-react';

interface Archetype {
  id: string;
  name: string;
  category: string;
  formula: string;
  description: string;
  previewCode: string;
}

export const DesignSystemExplorer: React.FC = () => {
  const [activeArchetype, setActiveArchetype] = useState<string>('asymmetric-hero');
  const [copiedCode, setCopiedCode] = useState(false);

  const archetypes: Archetype[] = [
    {
      id: 'asymmetric-hero',
      name: 'Asymmetric Hero Canvas',
      category: 'Layout Archetype',
      formula: 'Left: Editorial (ΔL ≈ 12%) + Right: Borderless 3D Artifact',
      description: 'Eliminates rectangular enclosing boxes. Text lives on the left while a 3D artifact emerges seamlessly on the right with orbiting frosted HUD chips.',
      previewCode: `<section className="relative min-h-[90vh] flex items-center bg-[#04060a]">
  <div className="grid grid-cols-12 gap-12 items-center">
    <div className="col-span-7 space-y-6 text-left">
      <h1 className="text-6xl font-extrabold tracking-[-0.045em] leading-[1.02]">
        The Architecture of Autonomous Thought.
      </h1>
      <FrostedInlineTerminal command="curl -fsSL https://aslang.dev/install.sh | bash" />
    </div>
    <div className="col-span-5 relative">
      <Borderless3DCore src="/assets/images/quantum_core.jpg" />
      <FloatingHudChip title="SINGLE-PASS CONTRACT" value="-78% Tokens" />
    </div>
  </div>
</section>`
    },
    {
      id: 'capsule-header',
      name: 'Floating Capsule (Dynamic Island)',
      category: 'Navigation Archetype',
      formula: 'Rounded-Full + Frosted Backdrop + <5% Screen Height',
      description: 'Centers navigation in a sleek, floating frosted glass capsule that frees up 95% of screen real estate for immersive visual storytelling.',
      previewCode: `<div className="fixed top-4 left-0 right-0 z-50 flex justify-center px-4 pointer-events-none">
  <header className="pointer-events-auto max-w-4xl w-full rounded-full border border-white/[0.12] bg-[#06080d]/80 backdrop-blur-2xl px-6 h-14 flex items-center justify-between shadow-2xl">
    <BrandLogo glyph="λ" label="ASL" />
    <CapsuleNavLinks links={navItems} />
    <TacticalThemeReactor />
  </header>
</div>`
    },
    {
      id: 'evolutionary-timeline',
      name: 'Evolutionary Timeline',
      category: 'Narrative Archetype',
      formula: 'Vertical Chronology + Active Glowing Node + Flaw/Perk Badges',
      description: 'Communicates paradigm shifts chronologically (OOP 1990s -> FP 2010s -> Prompt & Pray 2023 -> AgP 2026+) with visceral visual progression.',
      previewCode: `<div className="relative border-l-2 border-white/[0.1] ml-32 space-y-10">
  {epochs.map(epoch => (
    <TimelineNode 
      key={epoch.era} 
      era={epoch.era} 
      active={epoch.active}
      perks={epoch.perks}
      flaws={epoch.flaws} 
    />
  ))}
</div>`
    },
    {
      id: 'dual-plane',
      name: 'Dual-Plane Perception Viewport',
      category: 'Cognitive Archetype',
      formula: 'Plane 1: Human Sensory (<50ms) | Plane 2: Agent Schema (1-Pass)',
      description: 'Explicit separation of human visual aesthetics from machine-readable metadata (JSON-LD, llms.txt, and typed S-expressions).',
      previewCode: `<DualPlaneProvider>
  <HumanPlane>
    <NegativeTrackingHeadline tracking="-0.045em" />
    <VolumetricAtmosphericFog />
  </HumanPlane>
  <AgentPlane>
    <LlmManifestLink href="/llms.txt" />
    <JsonLdSchema type="SoftwareApplication" />
    <SExpressionWireFrame proto="asl/1.0" />
  </AgentPlane>
</DualPlaneProvider>`
    }
  ];

  const current = archetypes.find(a => a.id === activeArchetype) || archetypes[0];

  const handleCopyCode = () => {
    navigator.clipboard.writeText(current.previewCode);
    setCopiedCode(true);
    setTimeout(() => setCopiedCode(false), 2000);
  };

  return (
    <section id="design-system" className="relative py-28 border-b border-craft-200/60 dark:border-white/[0.06] bg-craft-50/50 dark:bg-[#030508] transition-colors">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Section Header */}
        <div className="max-w-3xl mx-auto text-center mb-12">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-cyan-500/10 border border-cyan-500/30 text-cyan-600 dark:text-cyan-400 text-xs font-mono mb-4">
            <Sliders className="w-3.5 h-3.5" />
            <span>Formal Design System & Visual Grammar</span>
          </div>

          <h2 className="text-3xl sm:text-5xl font-extrabold tracking-[-0.04em] text-craft-900 dark:text-white font-sans leading-tight">
            Reproducible Component Archetypes.
          </h2>

          <p className="mt-4 text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans leading-relaxed tracking-[-0.01em]">
            A formalized visual design system codified into agent skills. Enabling humans and autonomous AI agents to construct Apple-grade interfaces with mathematical reproducibility.
          </p>
        </div>

        {/* Archetype Selector Capsule Navigation */}
        <div className="flex justify-center mb-10 overflow-x-auto">
          <div className="p-1.5 rounded-full border border-craft-200 dark:border-white/[0.1] bg-white dark:bg-white/[0.03] backdrop-blur-2xl flex gap-1 shadow-lg font-mono text-xs max-w-full">
            {archetypes.map((arch) => (
              <button
                key={arch.id}
                onClick={() => setActiveArchetype(arch.id)}
                className={`px-4 py-2 rounded-full transition-all whitespace-nowrap ${
                  activeArchetype === arch.id
                    ? 'bg-craft-accent text-craft-950 font-bold shadow-[0_0_15px_rgba(6,182,212,0.35)]'
                    : 'text-craft-600 dark:text-craft-400 hover:text-craft-900 dark:hover:text-white'
                }`}
              >
                {arch.name}
              </button>
            ))}
          </div>
        </div>

        {/* Archetype Inspector Studio Card */}
        <div className="max-w-5xl mx-auto rounded-[2.5rem] border border-craft-200 dark:border-white/[0.08] bg-white dark:bg-[#06080d] p-6 sm:p-10 backdrop-blur-2xl shadow-2xl text-left">
          
          {/* Header Info */}
          <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 border-b border-craft-200 dark:border-white/[0.08] pb-6 mb-6">
            <div>
              <div className="flex items-center gap-2 mb-1">
                <span className="px-3 py-0.5 rounded-full text-[10px] font-mono font-bold uppercase tracking-wider bg-cyan-500/10 text-craft-accent border border-cyan-500/30">
                  {current.category}
                </span>
                <span className="font-mono text-xs text-craft-400">
                  Formula: <code className="text-craft-800 dark:text-craft-200 font-bold">{current.formula}</code>
                </span>
              </div>
              <h3 className="text-2xl font-bold text-craft-900 dark:text-white font-sans tracking-tight">
                {current.name}
              </h3>
            </div>

            <button
              onClick={handleCopyCode}
              className="px-4 py-2 rounded-xl bg-craft-100 dark:bg-white/[0.04] border border-craft-200 dark:border-white/[0.1] hover:border-craft-accent text-xs font-mono text-craft-800 dark:text-craft-200 flex items-center gap-2 transition-all shadow-sm"
            >
              {copiedCode ? (
                <>
                  <Check className="w-3.5 h-3.5 text-emerald-500" />
                  <span className="text-emerald-500 font-bold">Copied Spec!</span>
                </>
              ) : (
                <>
                  <Copy className="w-3.5 h-3.5 text-craft-accent" />
                  <span>Copy TSX Archetype</span>
                </>
              )}
            </button>
          </div>

          <p className="text-sm text-craft-600 dark:text-craft-300 font-sans leading-relaxed mb-6">
            {current.description}
          </p>

          {/* TSX Code Architecture Box */}
          <div className="relative rounded-2xl bg-craft-50 dark:bg-[#030508] border border-craft-200 dark:border-white/[0.06] p-4 sm:p-6 font-mono text-xs overflow-x-auto shadow-inner">
            <div className="flex items-center justify-between text-[10px] text-craft-400 mb-3 border-b border-craft-200 dark:border-white/[0.06] pb-2">
              <span className="flex items-center gap-1.5">
                <Code2 className="w-3.5 h-3.5 text-craft-accent" />
                <span>ARCHETYPE TSX SPECIFICATION</span>
              </span>
              <span className="text-emerald-400">REPRODUCIBLE BY AI AGENTS</span>
            </div>
            <pre className="text-cyan-400 dark:text-cyan-300 leading-relaxed font-mono">
              <code>{current.previewCode}</code>
            </pre>
          </div>

          {/* Skill Integration Footer */}
          <div className="mt-6 pt-4 border-t border-craft-200 dark:border-white/[0.06] flex flex-wrap items-center justify-between gap-2 text-xs font-mono text-craft-500 dark:text-craft-400">
            <span>Installed as agent skill: <code className="text-craft-accent">visual-cognition-design</code></span>
            <span>Compatible with: Claude Code, Cursor, Antigravity, OpenDevin</span>
          </div>

        </div>

      </div>
    </section>
  );
};
