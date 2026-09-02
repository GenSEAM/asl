import React from 'react';
import { Eyebrow } from './ui/primitives';

/**
 * Key Capabilities & Tooling Section
 * Recreated with high-fidelity blueprint vector graphics inspired by the reference design.
 */
export const KeyCapabilities: React.FC = () => {
  return (
    <section id="capabilities" className="relative py-24 sm:py-32 bg-sunken/40 border-t border-line">
      <div className="max-w-6xl mx-auto px-5 sm:px-6 lg:px-8">
        
        {/* Section Header */}
        <div className="mb-14">
          <Eyebrow index="00">Architectural Core</Eyebrow>
          <h2 className="mt-4 text-h2 font-bold text-ink tracking-tight">
            Key Capabilities & Tooling
          </h2>
          <p className="mt-3 text-lead text-ink-2 max-w-2xl">
            A comprehensive suite of formal verification, real-time observability, and high-frequency developer workflows designed for autonomous agent swarms.
          </p>
        </div>

        {/* 3 Blueprint Cards Grid */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 lg:gap-8">
          
          {/* Card 1: Architect-First Observability */}
          <div className="group rounded-3xl border border-line bg-surface/90 backdrop-blur-xl p-6 sm:p-7 shadow-e2 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between">
            <div>
              <h3 className="text-xl font-bold text-ink tracking-tight">
                Architect-First Observability
              </h3>

              {/* Rich Blueprint Illustration: Magnifying Glass, Waveform, Connector */}
              <div className="mt-6 w-full h-48 rounded-2xl bg-ground/80 border border-line/80 relative overflow-hidden flex items-center justify-center p-3">
                {/* Blueprint Grid Lines */}
                <svg className="absolute inset-0 w-full h-full opacity-20 pointer-events-none" xmlns="http://www.w3.org/2000/svg">
                  <defs>
                    <pattern id="card1Grid" width="16" height="16" patternUnits="userSpaceOnUse">
                      <path d="M 16 0 L 0 0 0 16" fill="none" stroke="currentColor" strokeWidth="0.5" className="text-signal" />
                    </pattern>
                  </defs>
                  <rect width="100%" height="100%" fill="url(#card1Grid)" />
                </svg>

                {/* Vector Schematic: Graph, Wave, Lens & Pipeline */}
                <svg viewBox="0 0 240 140" className="w-full h-full relative z-10" fill="none" xmlns="http://www.w3.org/2000/svg">
                  {/* Pipeline Conduit */}
                  <path d="M 150 110 L 220 110" stroke="rgb(var(--signal))" strokeWidth="2" strokeDasharray="4 3" opacity="0.6" />
                  <rect x="190" y="98" width="16" height="24" rx="3" stroke="rgb(var(--signal-soft))" strokeWidth="1.5" fill="rgb(var(--surface))" />
                  <line x1="198" y1="102" x2="198" y2="118" stroke="rgb(var(--signal))" strokeWidth="1.5" />

                  {/* Waveform Trace */}
                  <path
                    d="M 20 80 Q 40 40, 60 75 T 100 70 T 140 85 T 180 60"
                    stroke="rgb(var(--signal))"
                    strokeWidth="1.5"
                    strokeLinecap="round"
                    opacity="0.5"
                  />

                  {/* Target Node Graph */}
                  <circle cx="35" cy="70" r="4" fill="rgb(var(--signal))" />
                  <circle cx="65" cy="55" r="5" fill="rgb(var(--signal-soft))" />
                  <circle cx="95" cy="75" r="4" fill="rgb(var(--signal))" />
                  <line x1="35" y1="70" x2="65" y2="55" stroke="rgb(var(--signal-soft))" strokeWidth="1.2" />
                  <line x1="65" y1="55" x2="95" y2="75" stroke="rgb(var(--signal-soft))" strokeWidth="1.2" />

                  {/* Magnifying Glass Lens Frame */}
                  <circle cx="85" cy="65" r="32" stroke="rgb(var(--signal-soft))" strokeWidth="2.5" fill="rgb(var(--signal) / 0.08)" />
                  <circle cx="85" cy="65" r="28" stroke="rgb(var(--signal))" strokeWidth="0.8" strokeDasharray="3 3" opacity="0.7" />

                  {/* Inside the lens: Amplified Wave & Invariant Target */}
                  <path
                    d="M 62 65 Q 75 42, 85 65 T 108 65"
                    stroke="rgb(var(--signal-soft))"
                    strokeWidth="2.2"
                    strokeLinecap="round"
                  />
                  <circle cx="85" cy="65" r="3.5" fill="rgb(var(--signal-soft))" />
                  
                  {/* Lens Handle */}
                  <line x1="108" y1="88" x2="135" y2="115" stroke="rgb(var(--signal-soft))" strokeWidth="3.5" strokeLinecap="round" />
                  <line x1="114" y1="94" x2="132" y2="112" stroke="rgb(var(--signal))" strokeWidth="1.5" strokeLinecap="round" />
                  
                  {/* Coordinate Dimension Ticks */}
                  <line x1="20" y1="125" x2="100" y2="125" stroke="rgb(var(--ink-3))" strokeWidth="0.7" />
                  <line x1="20" y1="122" x2="20" y2="128" stroke="rgb(var(--ink-3))" strokeWidth="0.7" />
                  <line x1="100" y1="122" x2="100" y2="128" stroke="rgb(var(--ink-3))" strokeWidth="0.7" />
                  <text x="45" y="133" fill="rgb(var(--ink-3))" fontSize="7" fontFamily="monospace">Δt = 4.2ms</text>
                </svg>
              </div>
            </div>

            <p className="mt-5 text-meta text-ink-2 leading-relaxed">
              See patterns, flows, and states without reading code. Formal validation from the design up with real-time AST invariants.
            </p>
          </div>

          {/* Card 2: Accelerate Development Flow (Terminal Frame) */}
          <div className="group rounded-3xl border border-line bg-surface/90 backdrop-blur-xl p-6 sm:p-7 shadow-e2 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between">
            <div>
              <h3 className="text-xl font-bold text-ink tracking-tight">
                Accelerate Development Flow
              </h3>

              {/* Realistic macOS/Linux Terminal Mockup */}
              <div className="mt-6 w-full h-48 rounded-2xl bg-ground border border-line/90 relative overflow-hidden p-3.5 flex flex-col justify-between font-mono shadow-inner">
                
                {/* Terminal Window Header with 3 Window Buttons */}
                <div className="flex items-center justify-between pb-2.5 border-b border-line/60">
                  <div className="flex items-center gap-1.5">
                    <span className="w-2.5 h-2.5 rounded-full bg-red-500/80 inline-block" />
                    <span className="w-2.5 h-2.5 rounded-full bg-yellow-500/80 inline-block" />
                    <span className="w-2.5 h-2.5 rounded-full bg-green-500/80 inline-block" />
                  </div>
                  <span className="text-[10px] text-ink-3">asl-cli — zsh</span>
                  <div className="w-8" />
                </div>

                {/* Commands Stream */}
                <div className="space-y-1.5 text-[11px] sm:text-xs text-ink-2 py-1 flex-1 flex flex-col justify-center">
                  <div className="flex items-center gap-2">
                    <span className="text-signal font-semibold">$</span>
                    <span className="text-ink">asl init application</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-signal font-semibold">$</span>
                    <span className="text-ink">asl lint --fix</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-signal font-semibold">$</span>
                    <span className="text-ink">asl fmt</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-signal font-semibold">$</span>
                    <span className="text-purple-300">asl test --all</span>
                    <span className="inline-block w-1.5 h-3.5 bg-signal animate-pulse" />
                  </div>
                </div>

                <div className="pt-2 border-t border-line/40 flex items-center justify-between text-[10px] text-ink-3">
                  <span>Target: wasm32 + native</span>
                  <span className="text-green-400">✓ PASS (12/12)</span>
                </div>

              </div>
            </div>

            <p className="mt-5 text-meta text-ink-2 leading-relaxed">
              Unified built-in tools. Maximize utility from the design phase. ESL-compliant. Minimal config.
            </p>
          </div>

          {/* Card 3: Built-in Ecosystem Tools */}
          <div className="group rounded-3xl border border-line bg-surface/90 backdrop-blur-xl p-6 sm:p-7 shadow-e2 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between">
            <div>
              <h3 className="text-xl font-bold text-ink tracking-tight">
                Built-in Ecosystem Tools
              </h3>

              {/* Rich Blueprint Illustration: Calipers, Compass, Crystal Suite */}
              <div className="mt-6 w-full h-48 rounded-2xl bg-ground/80 border border-line/80 relative overflow-hidden flex items-center justify-center p-3">
                {/* Blueprint Grid Lines */}
                <svg className="absolute inset-0 w-full h-full opacity-20 pointer-events-none" xmlns="http://www.w3.org/2000/svg">
                  <defs>
                    <pattern id="card3Grid" width="16" height="16" patternUnits="userSpaceOnUse">
                      <path d="M 16 0 L 0 0 0 16" fill="none" stroke="currentColor" strokeWidth="0.5" className="text-signal" />
                    </pattern>
                  </defs>
                  <rect width="100%" height="100%" fill="url(#card3Grid)" />
                </svg>

                {/* Vector Drafting Compass / Calipers & Crystalline Matrix */}
                <svg viewBox="0 0 240 140" className="w-full h-full relative z-10" fill="none" xmlns="http://www.w3.org/2000/svg">
                  {/* Calipers / Compass Left Leg */}
                  <line x1="60" y1="20" x2="35" y2="100" stroke="rgb(var(--signal-soft))" strokeWidth="2.5" strokeLinecap="round" />
                  {/* Compass Right Leg */}
                  <line x1="60" y1="20" x2="85" y2="100" stroke="rgb(var(--signal-soft))" strokeWidth="2.5" strokeLinecap="round" />
                  {/* Compass Top Hinge */}
                  <circle cx="60" cy="20" r="6" stroke="rgb(var(--signal))" strokeWidth="2" fill="rgb(var(--surface))" />
                  <circle cx="60" cy="20" r="2.5" fill="rgb(var(--signal-soft))" />
                  
                  {/* Angle Measurement Arc */}
                  <path d="M 45 68 A 30 30 0 0 1 75 68" stroke="rgb(var(--signal))" strokeWidth="1.2" strokeDasharray="2 2" />
                  <text x="50" y="80" fill="rgb(var(--signal-soft))" fontSize="8" fontFamily="monospace">60°</text>

                  {/* Calibration Caliper Jaw */}
                  <rect x="95" y="45" width="8" height="55" rx="1.5" stroke="rgb(var(--ink-3))" strokeWidth="1" fill="rgb(var(--surface))" />
                  <line x1="95" y1="55" x2="99" y2="55" stroke="rgb(var(--signal-soft))" strokeWidth="1" />
                  <line x1="95" y1="65" x2="101" y2="65" stroke="rgb(var(--signal-soft))" strokeWidth="1" />
                  <line x1="95" y1="75" x2="99" y2="75" stroke="rgb(var(--signal-soft))" strokeWidth="1" />
                  <line x1="95" y1="85" x2="101" y2="85" stroke="rgb(var(--signal-soft))" strokeWidth="1" />

                  {/* Migration Suite Crystalline Facet Node */}
                  <g transform="translate(150, 35)">
                    {/* Gem / Crystal Outline */}
                    <polygon
                      points="25,0 45,15 45,45 25,60 5,45 5,15"
                      stroke="rgb(var(--signal-soft))"
                      strokeWidth="1.8"
                      fill="rgb(var(--signal) / 0.12)"
                    />
                    <line x1="25" y1="0" x2="25" y2="60" stroke="rgb(var(--signal))" strokeWidth="1" opacity="0.6" />
                    <line x1="5" y1="15" x2="45" y2="15" stroke="rgb(var(--signal))" strokeWidth="1" opacity="0.6" />
                    <line x1="5" y1="45" x2="45" y2="45" stroke="rgb(var(--signal))" strokeWidth="1" opacity="0.6" />

                    {/* Satellite Nodes with Connector Arrows */}
                    <rect x="-22" y="10" width="16" height="12" rx="2" stroke="rgb(var(--signal))" strokeWidth="1" fill="rgb(var(--surface))" />
                    <line x1="-6" y1="16" x2="4" y2="16" stroke="rgb(var(--signal-soft))" strokeWidth="1" strokeDasharray="2 1" />

                    <rect x="52" y="32" width="16" height="12" rx="2" stroke="rgb(var(--signal))" strokeWidth="1" fill="rgb(var(--surface))" />
                    <line x1="46" y1="38" x2="52" y2="38" stroke="rgb(var(--signal-soft))" strokeWidth="1" strokeDasharray="2 1" />
                  </g>
                </svg>
              </div>
            </div>

            {/* Labels Suite from Mockup */}
            <div className="mt-5 space-y-2">
              <div className="flex flex-wrap gap-1.5">
                <span className="px-2 py-0.5 rounded-md bg-inset border border-line text-[11px] font-mono text-ink-2">
                  Verification Tools
                </span>
                <span className="px-2 py-0.5 rounded-md bg-inset border border-line text-[11px] font-mono text-ink-2">
                  Migration Suite
                </span>
              </div>
              <div className="flex flex-wrap gap-1.5">
                <span className="px-2 py-0.5 rounded-md bg-inset border border-line text-[11px] font-mono text-ink-3">
                  Security Extensions
                </span>
                <span className="px-2 py-0.5 rounded-md bg-inset border border-line text-[11px] font-mono text-ink-3">
                  Interoperability Clients
                </span>
              </div>
            </div>

          </div>

        </div>

      </div>
    </section>
  );
};
