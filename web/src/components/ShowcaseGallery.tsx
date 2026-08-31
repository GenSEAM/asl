import React, { useState } from 'react';
import { Sparkles, Database, GitFork, ShieldCheck, ExternalLink, Terminal, Layers } from 'lucide-react';

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
      id: 'asl-mem',
      name: 'asl-mem (Vector Semantic Memory)',
      badge: 'Edge AI & Agents',
      tagline: 'Zero-server in-memory vector database running in 64KB Wasm',
      description: 'Provides autonomous AI agents with instant long-term semantic memory and cosine similarity search directly inside browser tabs or mobile apps without calling external vector APIs.',
      tokens: '380 tokens',
      latency: '0.038ms search',
      icon: <Database className="w-5 h-5 text-craft-accent" />,
      codeSnippet: `(module asl-mem/store
  :doc "In-memory cosine vector similarity index"
  :export [dot-product cosine-similarity top-k]
  
  (defun dot-product [(a (List Float64)) (b (List Float64))] -> Float64
    (fold-l (zip-with * a b) 0.0 +))
    
  (defun cosine-similarity [(a (List Float64)) (b (List Float64))] -> Float64
    (let [(dot (dot-product a b))
          (norm-a (sqrt (dot-product a a)))
          (norm-b (sqrt (dot-product b b)))]
      (if (or (== norm-a 0.0) (== norm-b 0.0))
          0.0
          (/ dot (* norm-a norm-b))))))`
    },
    {
      id: 'asl-fsm',
      name: 'asl-fsm (Exhaustive State Machine)',
      badge: 'Architecture & UI',
      tagline: 'Zero-bug algebraic state transitions with compiler-checked exhaustiveness',
      description: 'Guarantees that autonomous workflows, payment pipelines, and complex UI screens can never enter an undefined or unhandled state.',
      tokens: '290 tokens',
      latency: '<0.01ms dispatch',
      icon: <GitFork className="w-5 h-5 text-craft-emerald" />,
      codeSnippet: `(module asl-fsm/agent-state
  :export [State Event transition]
  
  (defenum State
    (:case idle [])
    (:case planning [(goal String)])
    (:case executing [(step Int64) (total Int64)])
    (:case finished [(result String)]))
    
  (defenum Event
    (:case start [(goal String)])
    (:case next-step [])
    (:case done [(output String)]))
    
  (defun transition [(s State) (e Event)] -> State
    (match [s e]
      [((idle) (start g)) (planning g)]
      [((planning g) (next-step)) (executing 1 5)]
      [((executing cur tot) (done out)) (finished out)]
      [(_ _) s])))`
    },
    {
      id: 'asl-vdom',
      name: 'asl-vdom (Universal Declarative UI)',
      badge: 'Frontend Core',
      tagline: 'Single logic core driving React 19, Vue 3, Svelte 5, and Angular',
      description: 'Write application UI logic once in pure S-expressions. Lower seamlessly to React JSX, Vue templates, or native Canvas without rewriting components.',
      tokens: '410 tokens',
      latency: '0.02ms render',
      icon: <Layers className="w-5 h-5 text-craft-amber" />,
      codeSnippet: `(module ui/metrics-card
  :export [render-metrics]
  
  (defschema Metric (:field label String) (:field value Float64) (:field status String))
  
  (defun render-metrics [(metrics (List Metric))] -> (List String)
    (map (fn [(m Metric)]
           (s/concat [(.label m) ": " (to-string (.value m)) " [" (.status m) "]"]))
         metrics)))`
    },
    {
      id: 'asl-guard',
      name: 'asl-guard (LLM Structured Decoders)',
      badge: 'Agentic Safety',
      tagline: 'Deterministic grammar guards & JSON schema enforcers for LLMs',
      description: 'Eliminates hallucinated JSON fields and invalid API payloads with strict compile-time schema conformance checking.',
      tokens: '240 tokens',
      latency: '0.005ms check',
      icon: <ShieldCheck className="w-5 h-5 text-craft-accent" />,
      codeSnippet: `(module asl-guard/validator
  :export [AgentPlan validate-plan]
  
  (defschema Step (:field tool String) (:field args (List String)))
  (defschema AgentPlan (:field reasoning String) (:field steps (List Step)))
  
  (defun validate-plan [(plan AgentPlan)] -> (Result Unit String)
    (if (== (length (.steps plan)) 0)
        (err "Plan must contain at least 1 actionable step")
        (ok unit))))`
    }
  ];

  const [activeProject, setActiveProject] = useState<ShowcaseProject>(PROJECTS[0]);

  return (
    <section id="showcases" className="py-16 border-b border-craft-800 bg-craft-950 font-mono">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Section Header */}
        <div className="max-w-3xl mb-10">
          <div className="inline-flex items-center gap-2 px-2.5 py-1 rounded bg-craft-900 border border-craft-700 text-xs text-craft-accent mb-3">
            <Sparkles className="w-3.5 h-3.5" />
            <span>Flagship Ecosystem Showcase</span>
          </div>
          <h2 className="text-3xl font-bold text-craft-50 tracking-tight">
            Built with ASL: The New Standard for Agent Software
          </h2>
          <p className="text-sm text-craft-400 mt-1 font-sans">
            Real, viral open-source building blocks designed for autonomous agent architectures and modern vibe-coders.
          </p>
        </div>

        {/* Interactive Showcase Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
          {/* Left Project Selector Column */}
          <div className="lg:col-span-5 space-y-3">
            {PROJECTS.map((proj) => (
              <button
                key={proj.id}
                onClick={() => setActiveProject(proj)}
                className={`w-full text-left p-4 rounded-xl border transition-all flex items-start gap-4 ${
                  activeProject.id === proj.id
                    ? 'bg-craft-900 border-craft-accent shadow-lg shadow-craft-accent/5'
                    : 'bg-craft-900/30 border-craft-800 hover:border-craft-700'
                }`}
              >
                <div className="p-2.5 rounded-lg bg-craft-950 border border-craft-800 shrink-0">
                  {proj.icon}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between text-xs mb-1">
                    <span className="text-[11px] font-bold text-craft-200">
                      {proj.name}
                    </span>
                    <span className="px-2 py-0.5 rounded bg-craft-800/80 text-[10px] text-craft-accent">
                      {proj.badge}
                    </span>
                  </div>
                  <p className="text-xs text-craft-400 font-sans line-clamp-2">
                    {proj.tagline}
                  </p>
                </div>
              </button>
            ))}

            {/* Quick Scaffold Callout */}
            <div className="p-4 rounded-xl border border-craft-800 bg-craft-950/60 mt-4 text-xs">
              <div className="flex items-center gap-2 text-craft-200 font-bold mb-1">
                <Terminal className="w-3.5 h-3.5 text-craft-accent" />
                <span>Scaffold a new project in 1 command</span>
              </div>
              <code className="text-[11px] text-craft-accent block bg-craft-900 p-2 rounded border border-craft-800 mt-2">
                pnpm dlx aslang init my-app --template wasm
              </code>
            </div>
          </div>

          {/* Right Code & Details Viewport */}
          <div className="lg:col-span-7 rounded-xl border border-craft-800 bg-craft-900/40 p-6 shadow-2xl">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-craft-800 pb-4 mb-4">
              <div>
                <h3 className="text-lg font-bold text-craft-50 flex items-center gap-2">
                  <span>{activeProject.name}</span>
                </h3>
                <p className="text-xs text-craft-400 font-sans mt-0.5">
                  {activeProject.description}
                </p>
              </div>
              <div className="flex items-center gap-2 shrink-0">
                <span className="px-2 py-1 rounded bg-craft-950 border border-craft-800 text-[11px] text-craft-accent">
                  {activeProject.tokens}
                </span>
                <span className="px-2 py-1 rounded bg-craft-950 border border-craft-800 text-[11px] text-craft-emerald">
                  {activeProject.latency}
                </span>
              </div>
            </div>

            {/* Code Snippet Window */}
            <div className="rounded-lg bg-craft-950 border border-craft-800 p-4 overflow-x-auto text-xs font-mono">
              <pre className="text-craft-200">
                <code>{activeProject.codeSnippet}</code>
              </pre>
            </div>

            <div className="mt-4 flex items-center justify-between text-xs text-craft-500 font-mono">
              <span>Zero external runtime dependencies • Compiles to Wasm</span>
              <a
                href="#playground"
                className="text-craft-accent hover:underline flex items-center gap-1 font-sans"
              >
                <span>Run in Playground</span>
                <ExternalLink className="w-3.5 h-3.5" />
              </a>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
