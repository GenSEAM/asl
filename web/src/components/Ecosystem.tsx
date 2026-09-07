import React from 'react';
import { Section, SectionHeader } from './ui/primitives';
import { 
  Layers, 
  Sparkles, 
  CheckCircle2, 
  Cpu, 
  Globe2, 
  Terminal, 
  FileCode2, 
  ArrowRight,
  ShieldCheck,
  Bot
} from 'lucide-react';

const ECOSYSTEM_TARGETS = [
  {
    name: 'WebAssembly (Wasm)',
    role: 'Edge & In-Browser Sandbox',
    badge: 'Zero-Leak Sandbox',
    desc: 'Compiles to standalone wasm32-wasip1 modules. Executes inside Cloudflare Workers, Fastly Compute, or sandboxed browser agent runtimes.',
    icon: Globe2,
  },
  {
    name: 'Rust',
    role: 'High-Performance Systems',
    badge: 'Zero-Cost Memory',
    desc: 'Translates to idiomatic, memory-safe Rust with static type checks and bare-metal native binary compilation via rustc.',
    icon: Cpu,
  },
  {
    name: 'TypeScript & JavaScript',
    role: 'Web & Host Integration',
    badge: 'Seamless Host Interop',
    desc: 'Emits modern ESM TypeScript modules for seamless embedding into Node.js, Deno, Bun, and browser extensions without wrappers.',
    icon: FileCode2,
  },
  {
    name: 'Go',
    role: 'High-Concurrency Services',
    badge: 'Microsecond Latency',
    desc: 'Generates concurrent Go routines and channels for high-throughput distributed agent swarms and microservices.',
    icon: Terminal,
  },
  {
    name: 'Python',
    role: 'ML & AI Orchestration',
    badge: 'Data Science Native',
    desc: 'Direct interoperability with PyTorch, LangChain, DSPy, and scientific workflows via clean, standard AST lowering.',
    icon: Sparkles,
  },
  {
    name: 'Relational SQL AST',
    role: 'Cross-Dialect Query Engine',
    badge: 'Provable Invariants',
    desc: 'Parametric AST lowering supporting PostgreSQL, SQLite, DuckDB, and MySQL with zero SQL injection risk and formal dialect guarantees.',
    icon: Layers,
  },
];

export const Ecosystem: React.FC = () => (
  <Section id="toolchain" labelledBy="toolchain-title" variant="surface" className="overflow-hidden">
    
    <SectionHeader
      id="toolchain-title"
      index="01"
      eyebrow="Multi-Runtime Interoperability"
      title="One language. Compatible with every ecosystem your agents touch."
      lead="Agents should not have to rewrite their logic for every deployment target. AgentScript compiles deterministically into native binaries, web sandboxes, and host scripting languages with mathematically proven equivalence."
    />

    {/* Status Clarity Banner */}
    <div className="flex justify-center -mt-6 mb-10">
      <span className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full border border-amber-500/30 bg-amber-500/10 text-amber-300 font-mono text-micro font-semibold uppercase tracking-wide">
        <span className="w-1.5 h-1.5 rounded-full bg-amber-400" />
        Core Language & Wire Protocol: Stable · Extended Compilers: Under Development
      </span>
    </div>

    {/* Architecture Flow Visualizer (Conceptual, Zero Code) */}
    <div className="mb-14 p-6 sm:p-8 rounded-3xl border border-line bg-surface/90 backdrop-blur-2xl shadow-e3">
      <div className="flex flex-col lg:flex-row items-center justify-between gap-6 pb-6 border-b border-line">
        <div>
          <span className="font-mono text-micro uppercase text-signal font-semibold">
            Architectural Guarantees
          </span>
          <h3 className="mt-1 text-h3 font-bold text-ink">
            Differential Verification & Cross-Runtime Equivalence
          </h3>
        </div>
        <div className="flex items-center gap-2 px-4 py-2 rounded-full border border-signal/30 bg-signal/10 text-signal font-mono text-meta font-medium">
          <ShieldCheck className="w-4 h-4" />
          <span>7-Gate Verified Equivalence</span>
        </div>
      </div>

      {/* Visual Flow Diagram */}
      <div className="mt-8 grid grid-cols-1 md:grid-cols-3 gap-6 items-center">
        
        {/* Step 1 */}
        <div className="p-5 rounded-2xl border border-line bg-ground/80 text-center flex flex-col items-center">
          <div className="w-12 h-12 rounded-2xl bg-signal/10 border border-signal/30 flex items-center justify-center text-signal mb-3">
            <Bot className="w-6 h-6" />
          </div>
          <h4 className="font-semibold text-ink text-body">1. Model Generates Once</h4>
          <p className="mt-1.5 text-meta text-ink-3 leading-relaxed">
            The agent writes one concise, balanced S-expression. Single-pass LL(1) grammar eliminates syntax repairs.
          </p>
        </div>

        {/* Step 2 */}
        <div className="p-5 rounded-2xl border border-signal/40 bg-surface text-center flex flex-col items-center shadow-e2 relative">
          <div className="w-12 h-12 rounded-2xl bg-gradient-to-tr from-purple-700 to-indigo-600 text-white flex items-center justify-center mb-3 shadow-md">
            <Layers className="w-6 h-6" />
          </div>
          <h4 className="font-semibold text-ink text-body">2. Canonical Lowering</h4>
          <p className="mt-1.5 text-meta text-ink-2 leading-relaxed">
            Multi-target AST lowering translates the program into the host target while preserving exact formal semantics.
          </p>
        </div>

        {/* Step 3 */}
        <div className="p-5 rounded-2xl border border-line bg-ground/80 text-center flex flex-col items-center">
          <div className="w-12 h-12 rounded-2xl bg-signal/10 border border-signal/30 flex items-center justify-center text-signal mb-3">
            <CheckCircle2 className="w-6 h-6" />
          </div>
          <h4 className="font-semibold text-ink text-body">3. Verified Execution</h4>
          <p className="mt-1.5 text-meta text-ink-3 leading-relaxed">
            Identical results on WebAssembly, native systems, or host runtimes verified by differential testing.
          </p>
        </div>

      </div>
    </div>

    {/* 6 Target Ecosystems Grid */}
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
      {ECOSYSTEM_TARGETS.map((target) => (
        <div
          key={target.name}
          className="group p-6 sm:p-7 rounded-3xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1 hover:shadow-purple-500/10 hover:border-signal/40 transition-all flex flex-col justify-between"
        >
          <div>
            <div className="flex items-center justify-between gap-3">
              <div className="p-3 rounded-2xl bg-inset border border-line group-hover:border-signal/30 transition-colors">
                <target.icon className="w-5 h-5 text-signal" />
              </div>
              <span className="px-2.5 py-1 rounded-full bg-inset border border-line font-mono text-[10px] uppercase font-semibold text-ink-3">
                {target.badge}
              </span>
            </div>

            <h3 className="mt-5 text-lg font-bold text-ink">
              {target.name}
            </h3>
            <p className="font-mono text-micro text-signal uppercase mt-0.5">
              {target.role}
            </p>

            <p className="mt-3 text-meta text-ink-2 leading-relaxed">
              {target.desc}
            </p>
          </div>

          <div className="mt-6 pt-4 border-t border-line/60 flex items-center justify-between text-micro font-mono text-ink-3">
            <span>Verified Target</span>
            <CheckCircle2 className="w-3.5 h-3.5 text-green-400" />
          </div>
        </div>
      ))}
    </div>

    {/* Machine-Readable Specs for Agents (Humans get visual beauty, Agents get formal specs) */}
    <div className="mt-14 p-6 sm:p-8 rounded-3xl border border-line bg-gradient-to-r from-surface via-surface/90 to-surface/60 backdrop-blur-2xl shadow-e3 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6">
      <div className="space-y-1.5 max-w-2xl">
        <div className="flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-signal" />
          <span className="font-mono text-micro uppercase text-signal font-semibold">
            Engineered for Agents · Documented for Models
          </span>
        </div>
        <h3 className="text-xl font-bold text-ink">
          Need full AST tables, grammar invariants, or MCP endpoints?
        </h3>
        <p className="text-meta text-ink-2 leading-relaxed">
          While humans explore visual concepts on this page, autonomous agents and LLMs consume our complete formal grammar and machine-readable specs directly via <code className="text-signal font-mono">/llms.txt</code> and Model Context Protocol.
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-3 shrink-0">
        <a
          href="/llms.txt"
          target="_blank"
          rel="noreferrer"
          className="inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-surface border border-line hover:border-signal/40 text-ink font-mono text-meta font-medium shadow-sm transition-all"
        >
          <span>/llms.txt</span>
          <ArrowRight className="w-3.5 h-3.5 text-signal" />
        </a>
        <a
          href="/llms-full.txt"
          target="_blank"
          rel="noreferrer"
          className="inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-gradient-to-r from-purple-700 to-indigo-600 text-white font-mono text-meta font-medium shadow-sm hover:opacity-95 transition-opacity"
        >
          <span>Full Spec</span>
          <ArrowRight className="w-3.5 h-3.5" />
        </a>
      </div>
    </div>

  </Section>
);
