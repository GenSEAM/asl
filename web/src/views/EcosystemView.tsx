import React from 'react';
import { Section, SectionHeader, Eyebrow } from '../components/ui/primitives';
import { Ecosystem } from '../components/Ecosystem';
import { UnifiedPackageMatrix } from '../components/UnifiedPackageMatrix';
import { ShieldCheck } from 'lucide-react';

export const EcosystemView: React.FC = () => {
  return (
    <div className="pt-24 sm:pt-28 pb-24">
      {/* Top Hero / Header Section */}
      <section className="relative pt-8 sm:pt-12 pb-16 sm:pb-20">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="max-w-3xl">
            <Eyebrow index="Stages 1–3">Complete Ecosystem Architecture</Eyebrow>
            <h1 className="mt-6 text-h2 sm:text-display font-bold text-ink tracking-tight text-balance">
              The Unified Package Matrix & Multi-Runtime Engine
            </h1>
            <p className="mt-6 text-lead text-ink-2 max-w-prose">
              Autonomous agents require more than a syntax parser. AgentScript provides a comprehensive, mathematically verified suite of 9 official packages spanning foundational ASN codecs, process isolation, onion middleware, high-speed A2A buses, and dual-perception VDOM.
            </p>
          </div>

          {/* Architecture DAG Flow Banner */}
          <div className="mt-12 p-6 sm:p-8 rounded-3xl border border-line bg-surface/85 backdrop-blur-2xl shadow-e3">
            <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 pb-6 border-b border-line">
              <div>
                <span className="font-mono text-micro uppercase text-signal font-semibold">
                  Architectural Progression DAG
                </span>
                <h2 className="mt-1 text-h3 font-bold text-ink">
                  Strict Sequential Milestone Pipeline
                </h2>
              </div>
              <div className="flex items-center gap-2 px-3.5 py-1.5 rounded-full border border-signal/30 bg-signal/10 text-signal font-mono text-micro font-medium">
                <ShieldCheck className="w-4 h-4" />
                <span>Zero External Runtime Dependencies</span>
              </div>
            </div>

            {/* Stages 1 -> 2 -> 3 DAG Graphic */}
            <div className="mt-8 grid grid-cols-1 md:grid-cols-3 gap-6 relative">
              {/* Stage 1 Card */}
              <div className="p-5 rounded-2xl border border-blue-500/30 bg-ground/80 flex flex-col justify-between space-y-4">
                <div>
                  <div className="flex items-center justify-between">
                    <span className="font-mono text-micro font-bold text-blue-400 px-2 py-0.5 rounded-md bg-blue-500/10 border border-blue-500/20">
                      Stage 1: CORE
                    </span>
                    <span className="font-mono text-[10px] text-ink-3 uppercase">Foundations</span>
                  </div>
                  <h3 className="mt-3 text-base font-bold text-ink">Foundational Language & Data Substrate</h3>
                  <p className="mt-1.5 text-meta text-ink-2 leading-relaxed">
                    Closed, single-pass LL(1) grammar, universal ASN codec with 57%–65% token compaction, and guarded process automation.
                  </p>
                </div>
                <div className="pt-3 border-t border-line/60 space-y-1 font-mono text-micro">
                  <div className="text-blue-300 font-semibold">• @genseam/asl-codec</div>
                  <div className="text-blue-300 font-semibold">• @genseam/asl-sh</div>
                </div>
              </div>

              {/* Stage 2 Card */}
              <div className="p-5 rounded-2xl border border-purple-500/40 bg-surface shadow-e2 flex flex-col justify-between space-y-4 relative">
                <div>
                  <div className="flex items-center justify-between">
                    <span className="font-mono text-micro font-bold text-signal px-2 py-0.5 rounded-md bg-purple-500/10 border border-signal/30">
                      Stage 2: HARNESS
                    </span>
                    <span className="font-mono text-[10px] text-signal uppercase font-semibold">Autonomous Core</span>
                  </div>
                  <h3 className="mt-3 text-base font-bold text-ink">Agent Engine & Execution Matrix</h3>
                  <p className="mt-1.5 text-meta text-ink-2 leading-relaxed">
                    Composable onion middleware, sub-100ms sandboxed voice & ReAct loops, &lt;0.04ms Unix/SSE mesh bus, and 64KB Wasm vector memory.
                  </p>
                </div>
                <div className="pt-3 border-t border-line/60 space-y-1 font-mono text-micro">
                  <div className="text-purple-300 font-semibold">• @genseam/asl-agent-core</div>
                  <div className="text-purple-300 font-semibold">• @genseam/asl-eddie</div>
                  <div className="text-purple-300 font-semibold">• @genseam/asl-agent-bus</div>
                  <div className="text-purple-300 font-semibold">• @genseam/asl-mem</div>
                  <div className="text-purple-300 font-semibold">• @genseam/asl-web-search</div>
                </div>
              </div>

              {/* Stage 3 Card */}
              <div className="p-5 rounded-2xl border border-emerald-500/30 bg-ground/80 flex flex-col justify-between space-y-4">
                <div>
                  <div className="flex items-center justify-between">
                    <span className="font-mono text-micro font-bold text-emerald-400 px-2 py-0.5 rounded-md bg-emerald-500/10 border border-emerald-500/20">
                      Stage 3: VISUAL
                    </span>
                    <span className="font-mono text-[10px] text-ink-3 uppercase">Perception & UI</span>
                  </div>
                  <h3 className="mt-3 text-base font-bold text-ink">Perception, UI Dialect & Browser Copilot</h3>
                  <p className="mt-1.5 text-meta text-ink-2 leading-relaxed">
                    Dual perception AXTree + D2Snap DOM downsampler (-75% prompt tokens), TSX declarative dialect, and Manifest V3 in-tab WASI runner.
                  </p>
                </div>
                <div className="pt-3 border-t border-line/60 space-y-1 font-mono text-micro">
                  <div className="text-emerald-300 font-semibold">• @genseam/asl-vdom</div>
                  <div className="text-emerald-300 font-semibold">• @genseam/asl-browser-plugin</div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Package Matrix Section */}
      <Section id="package-matrix" variant="surface" labelledBy="matrix-packages-title">
        <SectionHeader
          id="matrix-packages-title"
          index="Packages"
          eyebrow="Unified Package Matrix"
          title="Eight Official Packages. One Cohesive Substrate."
          lead="Every tool an autonomous agent needs to parse, sandbox, coordinate, recall, and interact with the physical and visual world — compiled with mathematical equivalence."
        />
        <UnifiedPackageMatrix />
      </Section>

      {/* Multi-Runtime Interoperability (6 Target Matrix) */}
      <Ecosystem />
    </div>
  );
};
