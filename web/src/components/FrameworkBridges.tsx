import React, { useState } from 'react';
import { Layers, Copy, Check, Terminal, Zap, CheckCircle2 } from 'lucide-react';

interface FrameworkOption {
  id: 'react' | 'vue' | 'angular' | 'svelte';
  name: string;
  badge: string;
  filename: string;
  snippet: string;
  highlight: string;
}

export const FrameworkBridges: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'react' | 'vue' | 'angular' | 'svelte'>('react');
  const [copied, setCopied] = useState(false);

  const FRAMEWORKS: Record<'react' | 'vue' | 'angular' | 'svelte', FrameworkOption> = {
    react: {
      id: 'react',
      name: 'React 19',
      badge: 'Hooks & Server Components',
      filename: 'useAslEngine.ts',
      highlight: 'Direct React Hook integration with Wasm edge acceleration',
      snippet: `import { useState, useEffect } from 'react';
import { runWasmInBrowser } from './wasm_runner';

export function useAslSpatialEngine(nodes: number[]) {
  const [coords, setCoords] = useState<number[]>([]);

  useEffect(() => {
    async function execute() {
      // 0-cost WebAssembly in-memory sandbox (<0.04ms)
      const wasm = await fetch('/modules/spatial.wasm').then(r => r.arrayBuffer());
      const res = await runWasmInBrowser(new Uint8Array(wasm), ["spatial", JSON.stringify(nodes)]);
      setCoords(JSON.parse(res.stdout));
    }
    execute();
  }, [nodes]);

  return coords;
}`
    },
    vue: {
      id: 'vue',
      name: 'Vue 3',
      badge: 'Composition API & Pinia',
      filename: 'useAslStore.ts',
      highlight: 'Reactive composables backed by 100% typed ASL domain models',
      snippet: `import { ref, computed } from 'vue';
import { calculateDiscount, Product } from './generated/pricing'; // Direct ASL TS emission

export function usePricingStore() {
  const cart = ref<Product[]>([]);
  
  const totalPrice = computed(() => {
    return cart.value.reduce((acc, item) => {
      return acc + calculateDiscount(item.price, item.discountRate);
    }, 0);
  });

  return { cart, totalPrice };
}`
    },
    angular: {
      id: 'angular',
      name: 'Angular 18+',
      badge: 'Injectable Services & Signals',
      filename: 'asl-engine.service.ts',
      highlight: 'Enterprise injectable services with signal-driven UI updates',
      snippet: `import { Injectable, signal } from '@angular/core';
import { runWasmInBrowser } from './wasm_runner';

@Injectable({ providedIn: 'root' })
export class AslEngineService {
  private outputSignal = signal<string>('');

  async runCalculations(payload: string) {
    const wasm = await fetch('/modules/core.wasm').then(r => r.arrayBuffer());
    const res = await runWasmInBrowser(new Uint8Array(wasm), ["calc", payload]);
    this.outputSignal.set(res.stdout.trim());
  }

  get output() {
    return this.outputSignal.asReadonly();
  }
}`
    },
    svelte: {
      id: 'svelte',
      name: 'Svelte 5',
      badge: 'Runes & Fine-Grained Reactivity',
      filename: 'AslComponent.svelte',
      highlight: 'Fine-grained $state runes reading directly from compiled ASL functions',
      snippet: `<script lang="ts">
  import { calculateVdomStats } from './lib/ui_vdom_gen'; // Direct ASL export

  let nodeCount = $state(10n);
  let renderBudget = $derived(calculateVdomStats(nodeCount));
</script>

<div class="card">
  <h3>Nodes: {nodeCount}</h3>
  <p>Render Budget: {renderBudget} µs</p>
  <button onclick={() => nodeCount += 5n}>Scale Tree</button>
</div>`
    }
  };

  const current = FRAMEWORKS[activeTab];

  const handleCopy = () => {
    navigator.clipboard.writeText(current.snippet);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <section id="frameworks" className="py-16 border-b border-craft-800 bg-craft-950 font-mono">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-8 gap-4">
          <div className="max-w-3xl">
            <div className="inline-flex items-center gap-2 px-2.5 py-1 rounded bg-craft-900 border border-craft-700 text-xs text-craft-accent mb-3">
              <Layers className="w-3.5 h-3.5" />
              <span>Universal Framework Interoperability</span>
            </div>
            <h2 className="text-3xl font-bold text-craft-50 tracking-tight">
              One Core Logic Layer. Any UI Framework.
            </h2>
            <p className="text-sm text-craft-400 mt-1 font-sans">
              Never rewrite your domain logic during framework migrations. Author state machines and math in ASL once, compile to Wasm & TypeScript, and consume seamlessly across React, Vue, Angular, and Svelte.
            </p>
          </div>

          <div className="flex items-center gap-2 px-3 py-1.5 rounded bg-craft-900 border border-craft-700 text-xs text-craft-emerald">
            <Zap className="w-4 h-4 text-craft-accent" />
            <span>Wasm Latency: &lt; 0.04 ms</span>
          </div>
        </div>

        {/* Framework Tabs */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 mb-6">
          {(Object.keys(FRAMEWORKS) as Array<'react' | 'vue' | 'angular' | 'svelte'>).map((key) => {
            const fw = FRAMEWORKS[key];
            const isActive = activeTab === key;
            return (
              <button
                key={key}
                onClick={() => setActiveTab(key)}
                className={`p-3.5 rounded-xl border text-left transition-all ${
                  isActive
                    ? 'bg-craft-900 border-craft-accent shadow-lg shadow-craft-accent/5'
                    : 'bg-craft-900/30 border-craft-800 hover:border-craft-700'
                }`}
              >
                <div className="flex items-center justify-between mb-1">
                  <span className={`text-sm font-bold ${isActive ? 'text-craft-50' : 'text-craft-300'}`}>
                    {fw.name}
                  </span>
                  {isActive && <CheckCircle2 className="w-3.5 h-3.5 text-craft-accent" />}
                </div>
                <p className="text-[10px] text-craft-500 font-mono truncate">{fw.badge}</p>
              </button>
            );
          })}
        </div>

        {/* Code Viewport */}
        <div className="rounded-xl border border-craft-800 bg-craft-900/40 p-6 shadow-2xl">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-4 mb-4 border-b border-craft-800 gap-2">
            <div>
              <span className="text-xs text-craft-accent font-semibold">{current.filename}</span>
              <p className="text-xs text-craft-400 font-sans mt-0.5">{current.highlight}</p>
            </div>
            <button
              onClick={handleCopy}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded bg-craft-800 border border-craft-700 text-craft-200 hover:text-craft-50 hover:border-craft-600 text-xs transition-colors self-start sm:self-auto"
            >
              {copied ? <Check className="w-3.5 h-3.5 text-craft-emerald" /> : <Copy className="w-3.5 h-3.5" />}
              <span>{copied ? 'Copied' : 'Copy Integration'}</span>
            </button>
          </div>

          <div className="rounded-lg border border-craft-800 bg-craft-950 p-4 text-xs overflow-x-auto">
            <div className="flex items-center justify-between text-[11px] text-craft-500 mb-2 border-b border-craft-800/80 pb-1.5">
              <span className="flex items-center gap-1.5 text-craft-400">
                <Terminal className="w-3.5 h-3.5 text-craft-accent" />
                <span>Framework Adapter Pattern</span>
              </span>
              <span>TYPESCRIPT</span>
            </div>
            <pre className="text-craft-200 leading-relaxed font-mono">
              {current.snippet}
            </pre>
          </div>
        </div>
      </div>
    </section>
  );
};
