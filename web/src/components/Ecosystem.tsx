import React from 'react';
import { Section, SectionHeader } from './ui/primitives';
import { Layers, Terminal, Sparkles, CheckCircle2 } from 'lucide-react';

const targets = [
  { name: 'WebAssembly', note: 'Edge & In-Browser Sandbox' },
  { name: 'Native Systems', note: 'Compiled Native Binaries' },
  { name: 'Managed Runtimes', note: 'TypeScript & Python' },
  { name: 'Concurrent Targets', note: 'Go & High-Concurrency Services' },
  { name: 'Dynamic Evaluation', note: 'Reference Tree-Walk Runtime' },
];

const surfaces = [
  {
    name: 'Model Context Protocol',
    body: 'The ASL toolchain exposed directly to models as structured agent tools — check, evaluate, format, and inspect.',
    cmd: 'asl mcp',
    icon: Sparkles,
  },
  {
    name: 'Universal Compiler',
    body: 'One source compiling to WebAssembly, native systems, and host scripting languages without manual rewriting.',
    cmd: 'asl run app.asl',
    icon: Layers,
  },
  {
    name: 'Deterministic Formatter',
    body: 'Canonical code formatting and structural AST search that guarantees clean, idempotent files every pass.',
    cmd: 'asl fmt',
    icon: Terminal,
  },
];

export const Ecosystem: React.FC = () => (
  <Section id="toolchain" labelledBy="toolchain-title" className="bg-dot-grid overflow-hidden">

    <SectionHeader
      id="toolchain-title"
      index="03"
      eyebrow="The Ecosystem"
      title="A language built for agents. An ecosystem growing around it."
      lead="We are developing the complete tooling layer to empower autonomous agents: universal compilation across diverse runtime targets, dedicated developer tooling, and native model integration."
    />

    <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,22rem)_1fr] gap-10 lg:gap-8 items-center">
      <div className="rounded-2xl border border-line bg-surface/90 backdrop-blur-xl p-8 shadow-e3">
        <div className="flex items-center justify-between pb-4 border-b border-line">
          <span className="font-mono text-micro uppercase text-ink-3">Core Thesis</span>
          <span className="font-mono text-micro text-ink-3 uppercase font-semibold">Universal Core</span>
        </div>
        <div className="mt-6 space-y-3">
          <h3 className="text-h3 font-semibold text-ink">Single Source of Truth</h3>
          <p className="text-body text-ink-2 leading-relaxed">
            An agent generates code in one concise, unambiguous representation. The compiler translates it to the exact target environment needed.
          </p>
        </div>
        <div className="mt-8 pt-5 border-t border-line flex items-center justify-between font-mono text-micro uppercase">
          <span className="text-ink-3">Guarantee</span>
          <span className="text-ink-2 font-semibold flex items-center gap-1.5">
            <CheckCircle2 className="w-3.5 h-3.5" />
            Verified Equivalence
          </span>
        </div>
      </div>

      <div className="rounded-2xl border border-line bg-surface/60 backdrop-blur-xl p-6 sm:p-8">
        <p className="font-mono text-micro uppercase text-ink-3 font-semibold pb-4 border-b border-line">
          Target Environments
        </p>
        <ul className="mt-4 divide-y divide-line">
          {targets.map((t) => (
            <li key={t.name} className="flex items-baseline justify-between gap-4 py-3.5 first:pt-0 last:pb-0">
              <span className="text-body font-semibold text-ink">{t.name}</span>
              <span className="font-mono text-micro uppercase text-ink-3 text-right">{t.note}</span>
            </li>
          ))}
        </ul>
      </div>
    </div>

    <div className="mt-20 grid grid-cols-1 md:grid-cols-3 gap-6">
      {surfaces.map((s) => (
        <div
          key={s.name}
          className="p-7 rounded-2xl border border-line bg-surface/80 backdrop-blur-md shadow-e1 hover:border-line-strong transition-all flex flex-col justify-between"
        >
          <div>
            <div className="flex items-center gap-2.5">
              <s.icon className="w-5 h-5 text-ink-3" />
              <h3 className="text-h3 font-semibold text-ink">{s.name}</h3>
            </div>
            <p className="mt-4 text-body text-ink-2 leading-relaxed">{s.body}</p>
          </div>
          <div className="mt-6 pt-5 border-t border-line">
            <code className="block font-mono text-meta text-ink-2 px-3 py-2 rounded-2xl bg-ground border border-line">
              <span className="text-signal font-semibold">$ </span>
              {s.cmd}
            </code>
          </div>
        </div>
      ))}
    </div>
  </Section>
);
