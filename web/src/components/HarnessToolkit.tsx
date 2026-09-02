import React from 'react';
import { Section, SectionHeader } from './ui/primitives';
import { ShieldCheck, GitBranch, Zap, Puzzle, Sliders } from 'lucide-react';

const CAPABILITIES = [
  {
    icon: Puzzle,
    title: 'Dynamic Plugin Architecture',
    subtitle: 'Extensible & Modular',
    desc: 'No rigid, hardcoded agent hierarchies. The harness is entirely modular and customizable through domain-specific plugins, allowing custom subagent graphs and tailor-made workflows.',
  },
  {
    icon: Sliders,
    title: 'Dynamic Agent Escalation',
    subtitle: 'Tiered Reasoning Presets',
    desc: 'Built-in escalation presets route lightweight routine coding to fast models while automatically escalating architectural refactors or persistent failures to heavy-reasoning agents.',
  },
  {
    icon: GitBranch,
    title: 'Separation of Duties',
    subtitle: 'Enforced Quality Isolation',
    desc: 'The agent that writes code never reviews it. Independent planner, implementer, reviewer, and verifier roles run with isolated context under strict file ownership boundaries.',
  },
  {
    icon: Zap,
    title: 'Structured Mesh Bus',
    subtitle: 'Low-Latency Interop',
    desc: 'Inter-agent communication over high-speed in-memory Unix domain sockets and SSE, exchanging compact S-expression frames without conversational bloat.',
  },
];

export const HarnessToolkit: React.FC = () => (
  <Section id="harness-toolkit" ground="sunken" labelledBy="harness-title" className="bg-dot-grid overflow-hidden border-t border-line">
    <SectionHeader
      id="harness-title"
      index="03"
      eyebrow="Multi-Agent Interoperability"
      title="Harness Toolkit: Dynamic Orchestration for Autonomous Agents"
      lead="Workspaces don't run on one monolithic model. The AgentScript Harness Toolkit provides the modular substrate to connect, coordinate, and supervise swarms of specialized agents with dynamic escalation and zero schema drift."
      align="center"
    />

    {/* Status Clarity Banner */}
    <div className="flex justify-center -mt-6 mb-10">
      <span className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full border border-amber-500/30 bg-amber-500/10 text-amber-300 font-mono text-micro font-semibold uppercase tracking-wide">
        <span className="w-1.5 h-1.5 rounded-full bg-amber-400" />
        Harness & Multi-Agent Mesh: In Active Development
      </span>
    </div>

    <div className="max-w-5xl mx-auto grid grid-cols-1 md:grid-cols-2 gap-6">
      {CAPABILITIES.map((cap) => (
        <div
          key={cap.title}
          className="p-6 sm:p-7 rounded-3xl border border-line bg-surface/80 backdrop-blur-xl shadow-e1 hover:border-signal/40 transition-all flex flex-col justify-between"
        >
          <div>
            <div className="flex items-center justify-between pb-4 border-b border-line/60">
              <div className="p-3 rounded-2xl bg-inset border border-line text-signal">
                <cap.icon className="w-5 h-5" />
              </div>
              <span className="font-mono text-micro uppercase text-ink-3 font-semibold">
                {cap.subtitle}
              </span>
            </div>

            <h3 className="mt-5 text-lg font-bold text-ink">
              {cap.title}
            </h3>

            <p className="mt-2 text-meta text-ink-2 leading-relaxed">
              {cap.desc}
            </p>
          </div>

          <div className="mt-6 pt-4 border-t border-line/60 flex items-center justify-between font-mono text-micro text-ink-3">
            <span>Dynamic Configuration</span>
            <ShieldCheck className="w-3.5 h-3.5 text-signal" />
          </div>
        </div>
      ))}
    </div>
  </Section>
);
