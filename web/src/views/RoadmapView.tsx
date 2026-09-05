import React from 'react';
import { Section, SectionHeader } from '../components/ui/primitives';
import { CheckCircle2, Clock, Sparkles } from 'lucide-react';

interface Milestone {
  status: 'completed' | 'active' | 'upcoming';
  tag: string;
  title: string;
  desc: string;
  items: string[];
}

const MILESTONES: Milestone[] = [
  {
    status: 'completed',
    tag: 'v0.3-Core',
    title: 'Formal Grammar & Differential Backends',
    desc: 'Establish closed, deterministic S-expression language with 107 safe pure builtins and differential compilation targets.',
    items: [
      'Single-pass LL(1) balanced S-expression parser',
      'Differential verification gates (Python, Rust, Wasm, TypeScript)',
      'Cross-backend IoError & numeric parity testing',
      'Compact coordinate protocol (asl/coord)',
    ],
  },
  {
    status: 'completed',
    tag: 'SeamBus-Mesh',
    title: 'Resilient Multi-Agent Mesh & Wire Protocol',
    desc: 'High-frequency sub-millisecond agent-to-agent protocol and state coordination mesh.',
    items: [
      'A2A structured machine frame serialization',
      'Zero-copy in-memory Unix socket & SSE message bus (<0.04ms latency)',
      'Asymmetric negotiation and protocol handshakes',
      'Context snapshot compression (-78% token bloat reduction)',
    ],
  },
  {
    status: 'active',
    tag: 'Self-Hosted Runtime',
    title: '100% Pure AgentScript Parser & Lexer',
    desc: 'Self-hosting compiler pipeline written entirely in pure AgentScript with zero external dependency overhead.',
    items: [
      'Native tokenizer and S-expression reader in pure ASL',
      'Typed AST schemas (ModuleNode, SchemaNode, DefunNode)',
      'CLI command: asl parse for high-speed AST inspections',
      'Autonomous anti-pattern linter and AST repair doctor',
    ],
  },
  {
    status: 'upcoming',
    tag: 'Autonomous Swarms',
    title: 'Meta-Agent Harness & Speculative Task Pools',
    desc: 'Production-grade orchestration engine for autonomous agent swarms with formal circuit breakers.',
    items: [
      'Zero-leak jailed sandbox execution with path jailing',
      'Decentralized agent search & memory recall matrix',
      'Autonomous multi-model routing (Claude, Gemini, OpenAI)',
      'Self-healing AST execution with formal verification gates',
    ],
  },
];

export const RoadmapView: React.FC = () => (
  <div className="pt-28 pb-20">
    <Section id="roadmap" labelledBy="roadmap-title">
      <SectionHeader
        id="roadmap-title"
        index="Strategic Trajectory"
        eyebrow="Canons & Roadmaps"
        title="Engineering the Foundation for the Autonomous Agent Era"
        lead="Our phased development roadmap tracks core language evolution, resilient agent-to-agent mesh buses, self-hosted compilation, and zero-leak sandboxing."
      />

      <div className="space-y-8 max-w-4xl mx-auto">
        {MILESTONES.map((m, idx) => (
          <div
            key={m.title}
            className={`p-6 sm:p-8 rounded-3xl border transition-all ${
              m.status === 'active'
                ? 'border-signal/50 bg-surface shadow-purple-500/10 shadow-e3 relative overflow-hidden'
                : m.status === 'completed'
                ? 'border-line bg-surface/70'
                : 'border-line/60 bg-surface/40'
            }`}
          >
            {m.status === 'active' && (
              <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-purple-500 via-signal to-indigo-500" />
            )}

            <div className="flex items-center justify-between gap-4 pb-4 border-b border-line/60">
              <div className="flex items-center gap-3">
                <span className="font-mono text-micro font-bold text-signal px-2.5 py-1 rounded-full bg-signal/10 border border-signal/20">
                  {m.tag}
                </span>
                <span className="font-mono text-micro uppercase text-ink-3">Phase 0{idx + 1}</span>
              </div>

              <span
                className={`font-mono text-micro uppercase font-semibold flex items-center gap-1.5 ${
                  m.status === 'completed'
                    ? 'text-green-400'
                    : m.status === 'active'
                    ? 'text-signal'
                    : 'text-ink-3'
                }`}
              >
                {m.status === 'completed' ? (
                  <>
                    <CheckCircle2 className="w-4 h-4" /> Completed
                  </>
                ) : m.status === 'active' ? (
                  <>
                    <Clock className="w-4 h-4 animate-pulse" /> Active Development
                  </>
                ) : (
                  <>
                    <Sparkles className="w-4 h-4" /> Planned
                  </>
                )}
              </span>
            </div>

            <h3 className="mt-5 text-xl font-bold text-ink">{m.title}</h3>
            <p className="mt-2 text-body text-ink-2 leading-relaxed">{m.desc}</p>

            <ul className="mt-6 grid grid-cols-1 sm:grid-cols-2 gap-2.5">
              {m.items.map((item) => (
                <li key={item} className="flex items-start gap-2 text-meta text-ink-2">
                  <span className="w-1.5 h-1.5 rounded-full bg-signal mt-1.5 shrink-0" />
                  <span>{item}</span>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </Section>
  </div>
);
