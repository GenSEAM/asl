import React from 'react';
import { Section, SectionHeader, Sexpr } from './ui/primitives';

const frames = [
  {
    step: '01',
    dir: 'out' as const,
    label: 'Probe',
    note: 'Capabilities',
    code: '(?agent/probe :proto "asl/1.0" :caps [wasm schema stream])',
  },
  {
    step: '02',
    dir: 'in' as const,
    label: 'Acknowledge',
    note: 'Mode agreed',
    code: '(!agent/ack :proto "asl/1.0" :mode :nano)',
  },
  {
    step: '03',
    dir: 'out' as const,
    label: 'Request',
    note: 'Typed',
    code: '(? agent-coder fsm/build :states ["idle" "plan" "exec" "done"])',
  },
  {
    step: '04',
    dir: 'in' as const,
    label: 'Result',
    note: 'A value',
    code: '(! agent-coder :ok (dfe State (:case idle []) (:case plan [(g Str)])))',
  },
];

const Endpoint: React.FC<{ name: string; role: string; align?: 'left' | 'right' }> = ({
  name,
  role,
  align = 'left',
}) => (
  <div className={align === 'right' ? 'text-right' : ''}>
    <p className="font-mono text-body font-medium text-ink">{name}</p>
    <p className="mt-1 font-mono text-micro uppercase text-ink-3">{role}</p>
  </div>
);

export const AgentWireProtocol: React.FC = () => (
  <Section id="a2a-protocol" ground="sunken" labelledBy="a2a-title">
    <SectionHeader
      id="a2a-title"
      index="02"
      eyebrow="Agent to agent"
      title="Prose is the wrong wire format between two machines."
      lead="Natural language is the right interface between an agent and a person. Between two agents it is payload that both sides have to re-parse and neither side can check. The moment they connect, they agree on a mode and stop talking in sentences."
      align="center"
    />

    <div className="max-w-4xl mx-auto">
      <div className="flex items-start justify-between gap-6">
        <Endpoint name="agent-orchestrator" role="Planner" />
        <div className="flex-1 pt-2.5 flex items-center gap-3">
          <span className="flex-1 h-px bg-line-strong" aria-hidden />
          <span className="font-mono text-micro uppercase text-signal">asl/1.0</span>
          <span className="flex-1 h-px bg-line-strong" aria-hidden />
        </div>
        <Endpoint name="agent-coder" role="Wasm specialist" align="right" />
      </div>

      <ol className="mt-12 space-y-px">
        {frames.map((f) => (
          <li
            key={f.step}
            className="grid grid-cols-[3rem_1fr] sm:grid-cols-[3rem_1fr_9rem] items-baseline gap-x-5 gap-y-2 py-5 border-t border-line"
          >
            <span className="font-mono text-micro text-ink-3 tabular-nums">
              {f.step} {f.dir === 'out' ? '→' : '←'}
            </span>
            <div className="min-w-0 overflow-x-auto">
              <Sexpr code={f.code} className="text-meta sm:text-body text-ink-2" />
            </div>
            <span className="col-start-2 sm:col-start-3 font-mono text-micro uppercase text-ink-3 sm:text-right whitespace-nowrap">
              {f.label} · {f.note}
            </span>
          </li>
        ))}
      </ol>

      <div className="mt-16 grid grid-cols-1 md:grid-cols-2 gap-px bg-line rounded-2xl overflow-hidden border border-line">
        <div className="bg-surface p-8">
          <p className="font-mono text-micro uppercase text-ink-3">Said in prose</p>
          <p className="mt-4 text-body text-ink-2">
            “Hello! Could you please take this specification and generate a state machine with idle
            and plan states, and return it formatted in JSON?”
          </p>
          <p className="mt-6 pt-5 border-t border-line text-body text-ink-3">
            Re-parsed by the receiver. Nothing about it can be checked before it runs.
          </p>
        </div>
        <div className="bg-surface p-8">
          <p className="font-mono text-micro uppercase text-signal">Said on the wire</p>
          <p className="mt-4 font-mono text-meta text-ink break-words">
            <span className="paren">(</span>? agent-coder fsm/build :states{' '}
            <span className="paren">[</span>"idle" "plan"<span className="paren">]</span>
            <span className="paren">)</span>
          </p>
          <p className="mt-6 pt-5 border-t border-line text-body text-ink-3">
            Balanced, typed against the callee, and compressible to its interface alone.
          </p>
        </div>
      </div>
    </div>
  </Section>
);
