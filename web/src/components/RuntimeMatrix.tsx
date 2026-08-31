import React, { useState } from 'react';
import { CheckCircle2, Shield, Globe } from 'lucide-react';

interface EngineItem {
  name: string;
  category: 'wasm' | 'js' | 'python';
  tier: string;
  status: string;
  compliance: string;
  description: string;
}

export const RuntimeMatrix: React.FC = () => {
  const [activeCategory, setActiveCategory] = useState<'all' | 'wasm' | 'js' | 'python'>('all');

  const ENGINES: EngineItem[] = [
    {
      name: 'Wasm3',
      category: 'wasm',
      tier: 'Mobile & Embedded #1',
      status: '100% App Store Safe',
      compliance: 'Pure C Interpreter (No JIT)',
      description: 'The premier WebAssembly engine for iOS and Android apps. Eliminates App Store JIT rejections while delivering ultra-low memory footprint (<64KB).'
    },
    {
      name: 'Browser Native (V8 / JSC)',
      category: 'wasm',
      tier: 'Web Client #1',
      status: 'Built-in OS Engine',
      compliance: 'W3C Standard',
      description: 'Zero-overhead native execution in React, Vue, and Svelte web apps (<0.04ms execution latency).'
    },
    {
      name: 'Wasmtime',
      category: 'wasm',
      tier: 'Cloud Edge #1',
      status: 'Bytecode Alliance Certified',
      compliance: 'WASI Preview1 / Preview2',
      description: 'Industrial server-side WASI host for Cloudflare Workers, Fastly Compute, and Docker Wasm containers.'
    },
    {
      name: 'Bun & Deno & Node.js',
      category: 'js',
      tier: 'JavaScript Triad',
      status: '100% ESM & TypeScript Native',
      compliance: 'Vite / Rollup Tree-Shaking',
      description: 'Standard ES6 named exports support full tree-shaking and dead-code elimination in all modern JS/TS bundlers.'
    },
    {
      name: 'CPython & PyPy',
      category: 'python',
      tier: 'AI & Data Science Standard',
      status: 'PEP 484 Type Annotated',
      compliance: 'PyPy JIT Compatible',
      description: 'Pure immutable functions execute with zero friction in standard CPython and achieve 4x–12x speedups under PyPy JIT.'
    },
    {
      name: 'Cython & Numba',
      category: 'python',
      tier: 'High-Performance Math',
      status: 'JIT Vectorized',
      compliance: '@njit(fastmath=True)',
      description: 'Automatic type decorators compile ASL mathematical algorithms to native C-speed machine code for ML pipelines.'
    }
  ];

  const filtered = activeCategory === 'all'
    ? ENGINES
    : ENGINES.filter((e) => e.category === activeCategory);

  return (
    <section id="runtimes" className="py-16 border-b border-craft-800 bg-craft-950 font-mono">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-8 gap-4">
          <div className="max-w-3xl">
            <div className="inline-flex items-center gap-2 px-2.5 py-1 rounded bg-craft-900 border border-craft-700 text-xs text-craft-accent mb-3">
              <Globe className="w-3.5 h-3.5" />
              <span>Universal Execution Matrix</span>
            </div>
            <h2 className="text-3xl font-bold text-craft-50 tracking-tight">
              Cross-Platform Runtimes & Mobile Policy Compliance
            </h2>
            <p className="text-sm text-craft-400 mt-1 font-sans">
              From iOS App Store-compliant Wasm3 interpreters to Bun, Deno, PyPy, and Numba math acceleration. ASL bridges every tier without rewriting logic.
            </p>
          </div>

          {/* Filter Pills */}
          <div className="flex gap-2">
            {(['all', 'wasm', 'js', 'python'] as const).map((cat) => (
              <button
                key={cat}
                onClick={() => setActiveCategory(cat)}
                className={`px-3 py-1.5 rounded-lg border text-xs uppercase tracking-wider transition-all ${
                  activeCategory === cat
                    ? 'bg-craft-accent text-craft-950 font-bold border-craft-accent shadow-sm'
                    : 'bg-craft-900 border-craft-700 text-craft-300 hover:border-craft-500'
                }`}
              >
                {cat === 'all' ? 'All Runtimes' : cat.toUpperCase()}
              </button>
            ))}
          </div>
        </div>

        {/* Grid of Runtimes */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {filtered.map((engine, idx) => (
            <div
              key={idx}
              className="p-6 rounded-xl border border-craft-800 bg-craft-900/40 hover:border-craft-700 transition-all flex flex-col justify-between shadow-xl"
            >
              <div>
                <div className="flex items-center justify-between text-xs mb-3">
                  <span className="px-2 py-0.5 rounded bg-craft-800 text-craft-accent text-[11px] font-semibold">
                    {engine.tier}
                  </span>
                  <span className="flex items-center gap-1 text-[11px] text-craft-emerald">
                    <CheckCircle2 className="w-3.5 h-3.5" />
                    <span>{engine.status}</span>
                  </span>
                </div>

                <h3 className="text-lg font-bold text-craft-50 mb-1">
                  {engine.name}
                </h3>
                <p className="text-[11px] text-craft-400 font-mono mb-3">
                  {engine.compliance}
                </p>

                <p className="text-xs text-craft-300 font-sans leading-relaxed">
                  {engine.description}
                </p>
              </div>

              <div className="mt-6 pt-3 border-t border-craft-800/80 flex items-center justify-between text-[11px] text-craft-500 font-mono">
                <span>0 Drift Verification</span>
                <Shield className="w-3.5 h-3.5 text-craft-accent" />
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};
