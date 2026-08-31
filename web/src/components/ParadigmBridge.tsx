import React, { useState } from 'react';
import { Network, Layers, Cpu, Shield, Sparkles, CheckCircle2, Code } from 'lucide-react';
import { oop, functional, procedural, formatBridgeName, calculateTokenSavings } from '../lib/ecosystem_gen';

export const ParadigmBridge: React.FC = () => {
  const [activeParadigm, setActiveParadigm] = useState<'oop' | 'functional' | 'procedural'>('functional');
  const [calcModules, setCalcModules] = useState(30);

  const getParadigmObject = () => {
    switch (activeParadigm) {
      case 'oop': return oop();
      case 'functional': return functional();
      case 'procedural': return procedural();
    }
  };

  // Calling our actual transpiled AgentScript function!
  const bridgeTitle = formatBridgeName(getParadigmObject());
  const tokenSavingsMillion = Number(calculateTokenSavings(BigInt(calcModules), 1000n));

  return (
    <section className="py-16 border-b border-craft-800 bg-craft-950 font-mono">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-10 gap-4">
          <div className="max-w-3xl">
            <div className="inline-flex items-center gap-2 px-2.5 py-1 rounded bg-craft-900 border border-craft-700 text-xs text-craft-accent mb-3">
              <Sparkles className="w-3.5 h-3.5" />
              <span>Ecosystem Glue & Native Dogfooding</span>
            </div>
            <h2 className="text-3xl font-bold text-craft-50 tracking-tight">
              The Multi-Paradigm Interop Bridge
            </h2>
            <p className="text-sm text-craft-400 mt-1 font-sans">
              AgentScript acts as the universal glue between Object-Oriented, Functional, and Procedural worlds. This very component is executing business logic written in <code className="text-craft-accent">ecosystem.agentscript</code> and transpiled directly into TypeScript.
            </p>
          </div>

          <div className="flex items-center gap-2">
            <span className="px-3 py-1 rounded bg-craft-900 border border-craft-700 text-craft-emerald text-xs flex items-center gap-1.5">
              <CheckCircle2 className="w-3.5 h-3.5" />
              <span>Transpiled via to_typescript.py</span>
            </span>
          </div>
        </div>

        {/* 3-Way Paradigm Switcher */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-12">
          {/* OOP Bridge */}
          <div
            onClick={() => setActiveParadigm('oop')}
            className={`p-6 rounded-xl border cursor-pointer transition-all ${
              activeParadigm === 'oop'
                ? 'bg-craft-900 border-craft-accent shadow-xl shadow-craft-accent/5'
                : 'bg-craft-900/30 border-craft-800 hover:border-craft-700'
            }`}
          >
            <div className="w-9 h-9 rounded bg-craft-800 border border-craft-700 flex items-center justify-center text-craft-amber mb-3">
              <Layers className="w-5 h-5" />
            </div>
            <h3 className="text-base font-bold text-craft-100 mb-2">Object-Oriented Bridge</h3>
            <p className="text-xs text-craft-400 font-sans leading-relaxed mb-4">
              <code className="text-craft-accent">(defschema ...)</code> compiles directly into immutable Classes in TypeScript/Python, Structs with trait implementations in Rust/Go, and native Swift structs without inheritance ambiguity.
            </p>
            <div className="text-[11px] text-craft-500 font-mono">
              OOP Targets: TypeScript · Swift · Python · Kotlin
            </div>
          </div>

          {/* Functional Bridge */}
          <div
            onClick={() => setActiveParadigm('functional')}
            className={`p-6 rounded-xl border cursor-pointer transition-all ${
              activeParadigm === 'functional'
                ? 'bg-craft-900 border-craft-accent shadow-xl shadow-craft-accent/5'
                : 'bg-craft-900/30 border-craft-800 hover:border-craft-700'
            }`}
          >
            <div className="w-9 h-9 rounded bg-craft-800 border border-craft-700 flex items-center justify-center text-craft-accent mb-3">
              <Network className="w-5 h-5" />
            </div>
            <h3 className="text-base font-bold text-craft-100 mb-2">Pure Functional Bridge</h3>
            <p className="text-xs text-craft-400 font-sans leading-relaxed mb-4">
              Algebraic sum types <code className="text-craft-accent">(defenum ...)</code>, exhaustive pattern matching, and single-pass expressions guarantee mathematical totality and zero runtime null-pointer crashes.
            </p>
            <div className="text-[11px] text-craft-500 font-mono">
              Functional Targets: WebAssembly · Rust · TypeScript
            </div>
          </div>

          {/* Procedural Bridge */}
          <div
            onClick={() => setActiveParadigm('procedural')}
            className={`p-6 rounded-xl border cursor-pointer transition-all ${
              activeParadigm === 'procedural'
                ? 'bg-craft-900 border-craft-accent shadow-xl shadow-craft-accent/5'
                : 'bg-craft-900/30 border-craft-800 hover:border-craft-700'
            }`}
          >
            <div className="w-9 h-9 rounded bg-craft-800 border border-craft-700 flex items-center justify-center text-craft-emerald mb-3">
              <Cpu className="w-5 h-5" />
            </div>
            <h3 className="text-base font-bold text-craft-100 mb-2">Procedural Effect Bridge</h3>
            <p className="text-xs text-craft-400 font-sans leading-relaxed mb-4">
              Functions with host interactions (I/O, network, disk, CLI) are strictly tracked via the <code className="text-craft-accent">!</code> effect marker, mapping to clean goroutines in Go and async runtimes in Node/WASI.
            </p>
            <div className="text-[11px] text-craft-500 font-mono">
              Procedural Targets: Go · Rust · Node/WASI
            </div>
          </div>
        </div>

        {/* Live Evaluated Badge from Transpiled AgentScript */}
        <div className="p-4 rounded-xl border border-craft-800 bg-craft-900/80 flex flex-col md:flex-row items-center justify-between gap-4 text-xs">
          <div className="flex items-center gap-3">
            <Code className="w-5 h-5 text-craft-accent" />
            <div>
              <span className="text-craft-400">AgentScript Transpiled Evaluator:</span>{' '}
              <strong className="text-craft-100">{bridgeTitle}</strong>
            </div>
          </div>

          <div className="flex items-center gap-4 text-craft-300">
            <span>Modules: <strong className="text-craft-accent">{calcModules}</strong></span>
            <span>Saved / mo: <strong className="text-craft-emerald">{tokenSavingsMillion}M tokens</strong></span>
            <input
              type="range"
              min="5"
              max="100"
              value={calcModules}
              onChange={(e) => setCalcModules(Number(e.target.value))}
              className="w-24 accent-craft-accent cursor-pointer"
            />
          </div>
        </div>

        {/* Target Roadmap Matrix */}
        <div className="mt-12">
          <h3 className="text-lg font-bold text-craft-100 mb-4 flex items-center gap-2">
            <Shield className="w-4 h-4 text-craft-accent" />
            <span>Target Ecosystem Compatibility Matrix</span>
          </h3>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            {/* Target 1 */}
            <div className="p-4 rounded-lg border border-craft-800 bg-craft-900/40">
              <div className="flex items-center justify-between mb-2">
                <span className="font-bold text-craft-50">WebAssembly</span>
                <span className="px-2 py-0.5 rounded text-[10px] bg-craft-emerald/10 text-craft-emerald border border-craft-emerald/20">Active</span>
              </div>
              <p className="text-xs text-craft-400 font-sans">Zero-cost sandbox, in-browser execution, edge runtime.</p>
            </div>

            {/* Target 2 */}
            <div className="p-4 rounded-lg border border-craft-800 bg-craft-900/40">
              <div className="flex items-center justify-between mb-2">
                <span className="font-bold text-craft-50">TypeScript</span>
                <span className="px-2 py-0.5 rounded text-[10px] bg-craft-emerald/10 text-craft-emerald border border-craft-emerald/20">Active</span>
              </div>
              <p className="text-xs text-craft-400 font-sans">Direct React/Next.js frontend transpilation, Node.js.</p>
            </div>

            {/* Target 3 */}
            <div className="p-4 rounded-lg border border-craft-800 bg-craft-900/40">
              <div className="flex items-center justify-between mb-2">
                <span className="font-bold text-craft-50">Rust</span>
                <span className="px-2 py-0.5 rounded text-[10px] bg-craft-emerald/10 text-craft-emerald border border-craft-emerald/20">Active</span>
              </div>
              <p className="text-xs text-craft-400 font-sans">Zero-overhead native binaries, compiler self-hosting.</p>
            </div>

            {/* Target 4 */}
            <div className="p-4 rounded-lg border border-craft-800 bg-craft-900/40">
              <div className="flex items-center justify-between mb-2">
                <span className="font-bold text-craft-50">Go</span>
                <span className="px-2 py-0.5 rounded text-[10px] bg-craft-emerald/10 text-craft-emerald border border-craft-emerald/20">Active</span>
              </div>
              <p className="text-xs text-craft-400 font-sans">Cloud-native microservices, goroutine integration.</p>
            </div>

            {/* Target 5 */}
            <div className="p-4 rounded-lg border border-craft-800 bg-craft-900/40">
              <div className="flex items-center justify-between mb-2">
                <span className="font-bold text-craft-50">Python</span>
                <span className="px-2 py-0.5 rounded text-[10px] bg-craft-emerald/10 text-craft-emerald border border-craft-emerald/20">Active</span>
              </div>
              <p className="text-xs text-craft-400 font-sans">AI pipelines, PyTorch dataflow, and reference tests.</p>
            </div>

            {/* Target 6: Swift */}
            <div className="p-4 rounded-lg border border-craft-accent/30 bg-craft-900/60">
              <div className="flex items-center justify-between mb-2">
                <span className="font-bold text-craft-accent">Swift</span>
                <span className="px-2 py-0.5 rounded text-[10px] bg-craft-amber/10 text-craft-amber border border-craft-amber/20">In Progress</span>
              </div>
              <p className="text-xs text-craft-400 font-sans">Native Apple Silicon, iOS edge agents, macOS tools.</p>
            </div>

            {/* Target 7: Kotlin */}
            <div className="p-4 rounded-lg border border-craft-800 bg-craft-900/20 opacity-70">
              <div className="flex items-center justify-between mb-2">
                <span className="font-bold text-craft-300">Kotlin</span>
                <span className="px-2 py-0.5 rounded text-[10px] bg-craft-700 text-craft-400">Planned</span>
              </div>
              <p className="text-xs text-craft-400 font-sans">Android runtime and JVM enterprise agent integration.</p>
            </div>

            {/* Target 8: C# / .NET */}
            <div className="p-4 rounded-lg border border-craft-800 bg-craft-900/20 opacity-70">
              <div className="flex items-center justify-between mb-2">
                <span className="font-bold text-craft-300">C# / .NET</span>
                <span className="px-2 py-0.5 rounded text-[10px] bg-craft-700 text-craft-400">Planned</span>
              </div>
              <p className="text-xs text-craft-400 font-sans">Cross-platform .NET 9 unified runtime glue.</p>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
