import React from 'react';
import { Section, SectionHeader } from '../components/ui/primitives';
import { Ecosystem } from '../components/Ecosystem';
import { Zap, Cpu, Globe2 } from 'lucide-react';

export const EcosystemView: React.FC = () => (
  <div className="pt-28 pb-20">
    <Ecosystem />
    
    <Section id="runtime-matrix" ground="sunken">
      <SectionHeader
        id="matrix-title"
        index="Runtimes"
        eyebrow="Target Matrix"
        title="Certified Equivalence Across Six Production Targets"
        lead="Portability is not an assumption in AgentScript — it is an enforced mathematical property validated by automated differential testing across every release."
      />

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <div className="p-6 rounded-3xl border border-line bg-surface shadow-e1 space-y-4">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-xl bg-purple-500/10 text-signal border border-signal/20">
              <Globe2 className="w-5 h-5" />
            </div>
            <div>
              <h3 className="font-bold text-ink text-base">wasm32-wasip1</h3>
              <p className="font-mono text-micro text-ink-3">Zero-Leak WebAssembly Sandbox</p>
            </div>
          </div>
          <p className="text-meta text-ink-2 leading-relaxed">
            Lightweight Wasm bytecode compiled via LLVM backend. Tested under node:wasi and in-browser Web Workers with strict directory jailing.
          </p>
          <div className="pt-3 border-t border-line/60 flex items-center justify-between font-mono text-micro text-ink-3">
            <span>Startup: &lt;0.05ms</span>
            <span className="text-green-400 font-semibold">Tier-A Target</span>
          </div>
        </div>

        <div className="p-6 rounded-3xl border border-line bg-surface shadow-e1 space-y-4">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-xl bg-purple-500/10 text-signal border border-signal/20">
              <Cpu className="w-5 h-5" />
            </div>
            <div>
              <h3 className="font-bold text-ink text-base">Native Rust (rustc)</h3>
              <p className="font-mono text-micro text-ink-3">Bare-Metal Systems Engine</p>
            </div>
          </div>
          <p className="text-meta text-ink-2 leading-relaxed">
            Generates memory-safe Rust with static type guarantees. Compiles directly to native machine binaries for maximum throughput.
          </p>
          <div className="pt-3 border-t border-line/60 flex items-center justify-between font-mono text-micro text-ink-3">
            <span>Zero GC Overheads</span>
            <span className="text-green-400 font-semibold">Tier-A Target</span>
          </div>
        </div>

        <div className="p-6 rounded-3xl border border-line bg-surface shadow-e1 space-y-4">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-xl bg-purple-500/10 text-signal border border-signal/20">
              <Zap className="w-5 h-5" />
            </div>
            <div>
              <h3 className="font-bold text-ink text-base">TypeScript & ESM</h3>
              <p className="font-mono text-micro text-ink-3">Web & Node.js Native</p>
            </div>
          </div>
          <p className="text-meta text-ink-2 leading-relaxed">
            Clean idiomatic TypeScript modules with accurate type definitions. Enables instant integration with existing web stacks.
          </p>
          <div className="pt-3 border-t border-line/60 flex items-center justify-between font-mono text-micro text-ink-3">
            <span>ESM Standard</span>
            <span className="text-green-400 font-semibold">Tier-A Target</span>
          </div>
        </div>
      </div>
    </Section>
  </div>
);
