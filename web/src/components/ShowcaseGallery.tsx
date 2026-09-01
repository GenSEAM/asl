import React, { useState } from 'react';
import { Sparkles, Database, GitFork, ShieldCheck, Terminal, Layers, Globe } from 'lucide-react';

interface ShowcaseProject {
  id: string;
  name: string;
  badge: string;
  tagline: string;
  description: string;
  tokens: string;
  latency: string;
  codeSnippet: string;
  icon: React.ReactNode;
}

export const ShowcaseGallery: React.FC = () => {
  const PROJECTS: ShowcaseProject[] = [
    {
      id: 'asl-search',
      name: 'asl-search (SearXNG & Proxy Pool)',
      badge: 'Agent Metasearch',
      tagline: 'Decentralized SearXNG aggregator with zero-drop proxy rotation',
      description: 'Gives autonomous AI agents multi-engine search capabilities (Google, Bing, arXiv, GitHub) with automatic proxy pool health checks, URL deduplication, and token-compressed RAG summaries.',
      tokens: '180 tokens (Nano)',
      latency: '<40ms aggregation',
      icon: <Globe className="w-5 h-5 text-craft-cyan" />,
      codeSnippet: `(module search/engine
  :export [Proxy ProxyStatus SearchResult select-proxy deduplicate-results]
  :import [(core/strings :as s)])

(dfe ProxyStatus
  (:case active   []            "Healthy proxy")
  (:case degraded [(fails I64)] "Degraded with fail count")
  (:case dead     []            "Dead proxy"))

(dfs Proxy
  (:field endpoint Str "Host:Port")
  (:field latency F64 "Ping ms")
  (:field status ProxyStatus "Health"))

(df select-proxy [(pool (List Proxy))] -> (Option Proxy)
  (match pool
    ((list) (none))
    ((cons head tail)
      (match (.-status head)
        ((active) (some head))
        ((degraded f) (if (< f 3) (some head) (select-proxy tail)))
        ((dead) (select-proxy tail))))))`
    },
    {
      id: 'asl-mem',
      name: 'asl-mem (Vector Semantic Memory)',
      badge: 'Edge AI & Agents',
      tagline: 'Zero-server in-memory vector database running in 64KB Wasm',
      description: 'Provides autonomous AI agents with instant long-term semantic memory and cosine similarity search directly inside browser tabs or mobile apps without calling external vector APIs.',
      tokens: '210 tokens (Nano)',
      latency: '0.038ms search',
      icon: <Database className="w-5 h-5 text-craft-accent" />,
      codeSnippet: `(module asl-mem/store
  :doc "In-memory cosine vector similarity index in ASL Nano"
  :export [dot-product cosine-similarity top-k]
  
  (df dot-product [(a (List F64)) (b (List F64))] -> F64
    (list-sum (list-zip-with * a b)))
    
  (df cosine-similarity [(a (List F64)) (b (List F64))] -> F64
    (let [(dot (dot-product a b))
          (norm-a (sqrt (dot-product a a)))
          (norm-b (sqrt (dot-product b b)))]
      (if (or (= norm-a 0.0) (= norm-b 0.0))
          0.0
          (/ dot (* norm-a norm-b))))))`
    },
    {
      id: 'asl-fsm',
      name: 'asl-fsm (Exhaustive State Machine)',
      badge: 'Architecture & UI',
      tagline: 'Zero-bug algebraic state transitions with compiler-checked exhaustiveness',
      description: 'Guarantees that autonomous workflows, payment pipelines, and complex UI screens can never enter an undefined or unhandled state.',
      tokens: '160 tokens (Nano)',
      latency: '<0.01ms dispatch',
      icon: <GitFork className="w-5 h-5 text-craft-emerald" />,
      codeSnippet: `(module asl-fsm/agent-state
  :export [State Event transition]
  
  (dfe State
    (:case idle [])
    (:case planning [(goal Str)])
    (:case executing [(step I64) (total I64)])
    (:case finished [(result Str)]))
    
  (dfe Event
    (:case start [(goal Str)])
    (:case next-step [])
    (:case done [(output Str)]))
    
  (df transition [(s State) (e Event)] -> State
    (match s
      ((idle)
       (match e
         ((start g) (:planning g))
         (_ s)))
      ((planning g)
       (match e
         ((next-step) (:executing 1 5))
         (_ s)))
      (_ s))))`
    },
    {
      id: 'asl-vdom',
      name: 'asl-vdom (Declarative Virtual DOM)',
      badge: 'Full-Stack UI',
      tagline: 'Pure S-expression Virtual DOM rendering directly to React/Vue/Svelte and Wasm Canvas',
      description: 'Allows writing entire UI tree components with single-pass S-expressions without JSX runtime dependencies, transpiling cleanly into typed React 19 hooks or solid HTML.',
      tokens: '190 tokens (Nano)',
      latency: '0.02ms render',
      icon: <Layers className="w-5 h-5 text-craft-purple" />,
      codeSnippet: `(module ui/dashboard
  :export [render-header stat-card]
  :import [(asl/vdom :as v)])
  
(dfs Metric
  (:field label Str "Metric name")
  (:field value F64 "Metric value")
  (:field unit Str "Unit of measure"))

(df stat-card [(m Metric)] -> v/VNode
  (v/element "div" [("class" "p-4 bg-craft-900 border rounded-lg")]
    [(v/element "h4" [("class" "text-xs font-mono text-craft-400")] [(v/text (.-label m))])
     (v/element "div" [("class" "text-2xl font-bold text-craft-100 font-mono mt-1")]
       [(v/text (string-from-float64 (.-value m))) (v/text (.-unit m))])]))`
    },
    {
      id: 'asl-guard',
      name: 'asl-guard (Zero-Allocation Guard Validator)',
      badge: 'Security & Schema',
      tagline: 'Deterministic payload validation without regex ReDoS vulnerabilities',
      description: 'Guarantees that user inputs and external LLM JSON completions match exact structural constraints before triggering database writes or payments.',
      tokens: '140 tokens (Nano)',
      latency: '0.015ms validation',
      icon: <ShieldCheck className="w-5 h-5 text-craft-rose" />,
      codeSnippet: `(module security/guard
  :export [UserPayload validate-payload]
  :import [(core/strings :as s)])

(dfs UserPayload
  (:field email Str "Validated email")
  (:field age I64 "User age")
  (:field verified Bool "Verified badge"))

(df validate-payload [(raw-email Str) (raw-age I64)] -> (Result UserPayload Str)
  (if (or (< raw-age 18) (> raw-age 120))
      (err "Invalid age range [18..120]")
      (if (not (s/contains? raw-email "@"))
          (err "Malformed email format")
          (ok (UserPayload :email raw-email :age raw-age :verified true)))))`
    }
  ];

  const [selectedId, setSelectedId] = useState<string>(PROJECTS[0].id);
  const active = PROJECTS.find((p) => p.id === selectedId) || PROJECTS[0];

  return (
    <section id="showcases" className="py-16 border-b border-craft-800 bg-craft-950">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-8 gap-4">
          <div>
            <div className="flex items-center gap-2 text-craft-accent font-mono text-xs uppercase tracking-wider mb-2">
              <Sparkles className="w-4 h-4" />
              <span>Flagship Ecosystem Showcase</span>
            </div>
            <h2 className="text-3xl font-bold font-mono text-craft-50 tracking-tight">
              Built with ASL Nano: Real-World Standards
            </h2>
            <p className="text-sm text-craft-400 mt-1 font-mono">
              Production-ready, zero-dependency building blocks designed for autonomous agent architectures.
            </p>
          </div>
        </div>

        {/* Interactive Master-Detail Showcase Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
          {/* Left Column: Project Selector Cards */}
          <div className="lg:col-span-5 space-y-3">
            {PROJECTS.map((project) => {
              const isSelected = project.id === selectedId;
              return (
                <div
                  key={project.id}
                  onClick={() => setSelectedId(project.id)}
                  className={`p-4 rounded-xl border transition-all cursor-pointer ${
                    isSelected
                      ? 'border-craft-accent bg-craft-900 shadow-md ring-1 ring-craft-accent/30'
                      : 'border-craft-800/80 bg-craft-900/40 hover:bg-craft-900/80 hover:border-craft-700'
                  }`}
                >
                  <div className="flex items-start justify-between">
                    <div className="flex items-center gap-3">
                      <div className="p-2 rounded-lg bg-craft-950 border border-craft-800">
                        {project.icon}
                      </div>
                      <div>
                        <div className="flex items-center gap-2">
                          <h3 className="font-mono font-bold text-sm text-craft-100">{project.name}</h3>
                        </div>
                        <span className="text-[10px] font-mono font-semibold text-craft-accent uppercase tracking-wider">
                          {project.badge}
                        </span>
                      </div>
                    </div>
                    <div className="text-right">
                      <span className="text-[11px] font-mono px-2 py-0.5 rounded bg-craft-950 border border-craft-800 text-craft-cyan">
                        {project.latency}
                      </span>
                    </div>
                  </div>
                  <p className="mt-2 text-xs text-craft-300 font-sans line-clamp-2">
                    {project.description}
                  </p>
                </div>
              );
            })}
          </div>

          {/* Right Column: Code & Architecture Detail View */}
          <div className="lg:col-span-7 flex flex-col rounded-xl border border-craft-800 bg-craft-900/70 p-5 shadow-2xl">
            <div className="flex items-center justify-between border-b border-craft-800 pb-3 mb-4">
              <div className="flex items-center gap-2.5">
                {active.icon}
                <div>
                  <h4 className="font-mono font-bold text-base text-craft-100">{active.name}</h4>
                  <p className="text-xs text-craft-400 font-mono">{active.tagline}</p>
                </div>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-[11px] font-mono text-craft-accent bg-craft-950 px-2.5 py-1 rounded border border-craft-800">
                  {active.tokens}
                </span>
              </div>
            </div>

            {/* Code Snippet Box */}
            <div className="flex-1 relative rounded-lg border border-craft-800 bg-craft-950 overflow-hidden font-mono text-xs">
              <div className="h-8 px-3 bg-craft-900/90 border-b border-craft-800 flex items-center justify-between">
                <div className="flex items-center gap-2 text-craft-400">
                  <Terminal className="w-3.5 h-3.5 text-craft-accent" />
                  <span className="text-[11px]">{active.id}.asl</span>
                </div>
                <span className="text-[10px] text-craft-500">ASL Nano 1.0</span>
              </div>
              <pre className="p-4 text-craft-200 overflow-x-auto leading-relaxed h-80">
                <code>{active.codeSnippet}</code>
              </pre>
            </div>

            {/* Scaffold CLI command */}
            <div className="mt-4 pt-3 border-t border-craft-800 flex items-center justify-between text-xs font-mono">
              <span className="text-craft-400">Scaffold this package:</span>
              <code className="px-2.5 py-1 rounded bg-craft-950 border border-craft-800 text-craft-accent">
                asl init my-project --template {active.id.replace('asl-', '')}
              </code>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
