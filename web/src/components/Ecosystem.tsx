import React from 'react';
import { Section, SectionHeader } from './ui/primitives';
import { Layers, Terminal, Sparkles } from 'lucide-react';

const targets = [
  { name: 'WebAssembly', note: 'wasm32-wasip1 · <0.04ms' },
  { name: 'Native Rust', note: 'rustc clean · Zero GC' },
  { name: 'TypeScript', note: 'tsc clean · Node & Browser' },
  { name: 'Go', note: 'go vet clean · Concurrent' },
  { name: 'Python', note: 'py_compile clean · Async' },
  { name: 'Interpreter', note: 'Reference Tree-Walk' },
];

const surfaces = [
  {
    name: 'Developer MCP Server',
    body: 'The ASL toolchain exposed to agents as structured tools — check, evaluate, format, and compress modules to their interface.',
    cmd: 'asl mcp',
    icon: Sparkles,
  },
  {
    name: 'Wasm Native Compiler',
    body: 'One source to any of the six targets, or straight into the in-memory WASI preview1 runner with no host disk dependencies.',
    cmd: 'asl run --target wasm app.asl',
    icon: Layers,
  },
  {
    name: 'Deterministic Formatter',
    body: 'A canonical layout that is idempotent over the corpus, plus structural search over the ASL grammar.',
    cmd: 'asl fmt',
    icon: Terminal,
  },
];

// Six curves from one origin. Drawn, not photographed — the diagram is the argument.
const FanOut: React.FC = () => (
  <svg
    aria-hidden
    viewBox="0 0 100 100"
    preserveAspectRatio="none"
    className="absolute inset-0 w-full h-full text-line-strong"
  >
    {targets.map((_, i) => {
      const y = ((i + 0.5) / targets.length) * 100;
      return (
        <path
          key={i}
          d={`M0,50 C40,50 55,${y} 100,${y}`}
          fill="none"
          stroke="currentColor"
          strokeWidth="1.2"
          vectorEffect="non-scaling-stroke"
          opacity={0.4}
        />
      );
    })}
  </svg>
);

export const Ecosystem: React.FC = () => (
  <Section id="toolchain" labelledBy="toolchain-title" className="bg-dot-grid overflow-hidden">
    {/* Atmospheric Glow */}
    <div className="glow-orb top-1/2 -right-48 w-96 h-96" aria-hidden="true" />

    <SectionHeader
      id="toolchain-title"
      index="03"
      eyebrow="The Ecosystem"
      title="One program. Six runtimes that are made to agree."
      lead="Portability is a claim until something enforces it. Every fixture runs through all six targets and the build fails if any two of them disagree on a result — which is why the language can promise a program means the same thing wherever it lands."
    />

    <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,22rem)_1fr] gap-10 lg:gap-0 items-center">
      <div className="rounded-3xl border border-line bg-surface/90 backdrop-blur-xl p-8 shadow-e3">
        <div className="flex items-center justify-between pb-4 border-b border-line">
          <span className="font-mono text-micro uppercase text-ink-3">Format Standard</span>
          <span className="font-mono text-micro text-signal uppercase font-bold">ASL Nano</span>
        </div>
        <div className="mt-6 space-y-3">
          <h3 className="text-h3 font-bold text-ink">Single-Pass AST</h3>
          <p className="text-body text-ink-2 leading-relaxed">
            Byte-reproducible native code emission across every target with zero intermediate runtime drift.
          </p>
        </div>
        <div className="mt-8 pt-5 border-t border-line flex items-center justify-between font-mono text-micro uppercase">
          <span className="text-ink-3">Verification</span>
          <span className="text-signal font-semibold">Differential Lockstep</span>
        </div>
      </div>

      <div className="relative grid grid-cols-1 sm:grid-cols-[1fr_minmax(0,20rem)]">
        <div className="relative hidden sm:block min-h-[20rem]">
          <FanOut />
        </div>
        <ul className="divide-y divide-line border-y border-line rounded-2xl bg-surface/40 backdrop-blur-sm">
          {targets.map((t) => (
            <li key={t.name} className="flex items-baseline justify-between gap-4 py-4 sm:pl-6 sm:pr-4">
              <span className="text-body font-semibold text-ink">{t.name}</span>
              <span className="font-mono text-micro uppercase text-ink-3 text-right">{t.note}</span>
            </li>
          ))}
        </ul>
      </div>
    </div>

    <div className="mt-24 grid grid-cols-1 md:grid-cols-3 border-t border-line">
      {surfaces.map((s) => (
        <div
          key={s.name}
          className="pt-8 pb-8 md:pr-8 md:pl-8 first:md:pl-0 last:md:pr-0 border-b md:border-b-0 md:border-r last:md:border-r-0 border-line"
        >
          <div className="flex items-center gap-2.5">
            <s.icon className="w-5 h-5 text-signal" />
            <h3 className="text-h3 font-bold text-ink">{s.name}</h3>
          </div>
          <p className="mt-4 text-body text-ink-2 leading-relaxed">{s.body}</p>
          <code className="mt-6 block font-mono text-meta text-ink-3 overflow-x-auto whitespace-nowrap p-3 rounded-xl bg-ground border border-line">
            <span className="text-signal font-semibold">$ </span>
            {s.cmd}
          </code>
        </div>
      ))}
    </div>
  </Section>
);
