import React, { useState } from 'react';
import { Eye, Binary, Sparkles, Layers, Cpu } from 'lucide-react';

export const VisualCognition: React.FC = () => {
  const [viewPlane, setViewPlane] = useState<'human' | 'agent'>('human');

  return (
    <section id="cognition" className="relative py-28 border-b border-craft-200/60 dark:border-white/[0.06] bg-white dark:bg-[#04060a] transition-colors">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        
        {/* Section Header */}
        <div className="max-w-3xl mx-auto text-center mb-12">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-purple-500/10 border border-purple-500/30 text-purple-600 dark:text-purple-400 text-xs font-mono mb-4">
            <Layers className="w-3.5 h-3.5" />
            <span>Dual-Plane Architecture</span>
          </div>

          <h2 className="text-3xl sm:text-5xl font-extrabold tracking-[-0.04em] text-craft-900 dark:text-white font-sans leading-tight">
            Design for Humans. Metadata for Agents.
          </h2>

          <p className="mt-4 text-base sm:text-lg text-craft-600 dark:text-craft-300 font-sans leading-relaxed tracking-[-0.01em]">
            Humans think in spatial hierarchy, emotional aesthetics, and tactile rhythm. AI agents think in structured contracts and semantic schemas. ASL bridges both worlds seamlessly.
          </p>
        </div>

        {/* Dual-Plane Switcher Capsule */}
        <div className="flex justify-center mb-10">
          <div className="p-1.5 rounded-full border border-craft-200 dark:border-white/[0.1] bg-craft-100/80 dark:bg-white/[0.03] backdrop-blur-2xl flex gap-1 shadow-lg font-mono text-xs">
            <button
              onClick={() => setViewPlane('human')}
              className={`px-5 py-2 rounded-full transition-all flex items-center gap-2 ${
                viewPlane === 'human'
                  ? 'bg-craft-accent text-craft-950 font-bold shadow-[0_0_15px_rgba(6,182,212,0.35)]'
                  : 'text-craft-600 dark:text-craft-400 hover:text-craft-900 dark:hover:text-white'
              }`}
            >
              <Eye className="w-4 h-4" />
              <span>Human Visual Plane</span>
            </button>
            <button
              onClick={() => setViewPlane('agent')}
              className={`px-5 py-2 rounded-full transition-all flex items-center gap-2 ${
                viewPlane === 'agent'
                  ? 'bg-purple-500 text-white font-bold shadow-[0_0_15px_rgba(168,85,247,0.35)]'
                  : 'text-craft-600 dark:text-craft-400 hover:text-craft-900 dark:hover:text-white'
              }`}
            >
              <Binary className="w-4 h-4" />
              <span>Agent Semantic Plane</span>
            </button>
          </div>
        </div>

        {/* Interactive Dual-Plane Viewport */}
        <div className="p-8 sm:p-10 rounded-[2.5rem] border border-craft-200 dark:border-white/[0.08] bg-white/60 dark:bg-white/[0.02] backdrop-blur-2xl shadow-2xl text-left transition-all">
          
          {viewPlane === 'human' ? (
            <div className="space-y-6 animate-fadeIn">
              <div className="flex items-center justify-between border-b border-craft-200 dark:border-white/[0.08] pb-4">
                <div className="font-mono text-xs font-bold text-craft-accent uppercase tracking-wider flex items-center gap-2">
                  <Sparkles className="w-4 h-4" />
                  <span>The Human Experience: Optical Perfection</span>
                </div>
                <span className="text-[11px] font-mono text-craft-400">Visceral Impact &lt;50ms</span>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-3 gap-6">
                <div className="p-6 rounded-2xl bg-craft-50 dark:bg-[#06080d] border border-craft-200 dark:border-white/[0.06]">
                  <h4 className="font-bold text-base text-craft-900 dark:text-white mb-2">
                    Negative Optical Tracking
                  </h4>
                  <p className="text-xs text-craft-600 dark:text-craft-300 leading-relaxed font-sans">
                    Display headlines dynamically compensate letter spacing (<code className="text-craft-accent">-0.045em</code>) to create monolithic typographic harmony.
                  </p>
                </div>

                <div className="p-6 rounded-2xl bg-craft-50 dark:bg-[#06080d] border border-craft-200 dark:border-white/[0.06]">
                  <h4 className="font-bold text-base text-craft-900 dark:text-white mb-2">
                    Volumetric Caustics
                  </h4>
                  <p className="text-xs text-craft-600 dark:text-craft-300 leading-relaxed font-sans">
                    Multi-layered atmospheric fog and tactile 3D quantum processor cores provide instant subconscious depth.
                  </p>
                </div>

                <div className="p-6 rounded-2xl bg-craft-50 dark:bg-[#06080d] border border-craft-200 dark:border-white/[0.06]">
                  <h4 className="font-bold text-base text-craft-900 dark:text-white mb-2">
                    Dynamic Island Controls
                  </h4>
                  <p className="text-xs text-craft-600 dark:text-craft-300 leading-relaxed font-sans">
                    Floating frosted-glass capsules offer frictionless tactile feedback with zero visual clutter.
                  </p>
                </div>
              </div>
            </div>
          ) : (
            <div className="space-y-6 animate-fadeIn font-mono text-xs">
              <div className="flex items-center justify-between border-b border-craft-200 dark:border-white/[0.08] pb-4">
                <div className="font-mono text-xs font-bold text-purple-400 uppercase tracking-wider flex items-center gap-2">
                  <Cpu className="w-4 h-4" />
                  <span>The Agent Substrate: Machine-Readable Schemas</span>
                </div>
                <span className="text-[11px] text-emerald-400">100% Single-Pass Parsable</span>
              </div>

              <div className="p-5 rounded-2xl bg-[#06080d] border border-purple-500/30 overflow-x-auto text-purple-300 space-y-2 shadow-inner">
                <div><span className="text-craft-500">;; Manifest Endpoint:</span> <span className="text-cyan-300 font-bold">https://aslang.dev/llms.txt</span></div>
                <div><span className="text-craft-500">;; Protocol Handshake:</span> <span className="text-amber-300 font-bold">(?agent/probe :proto "asl/1.0" :caps [wasm schema stream])</span></div>
                <div><span className="text-craft-500">;; JSON-LD Schema:</span> <span className="text-emerald-300 font-bold">&#123;"@context": "https://schema.org", "@type": "SoftwareApplication"&#125;</span></div>
                <div><span className="text-craft-500">;; Native Wire Frame:</span> <span className="text-purple-300 font-bold">(! agent-coder :ok (dfe State (:case active [(t I64)])))</span></div>
              </div>

              <div className="flex flex-wrap items-center justify-between gap-4 text-[11px] text-craft-400 pt-2 border-t border-craft-200 dark:border-white/[0.06]">
                <span>Zero DOM scraping overhead</span>
                <span>Direct LLM context injection ready</span>
                <a href="/llms.txt" target="_blank" className="text-craft-accent hover:underline flex items-center gap-1">
                  View raw /llms.txt &rarr;
                </a>
              </div>
            </div>
          )}

        </div>

      </div>
    </section>
  );
};
