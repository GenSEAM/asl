import React from 'react';
import { Section, SectionHeader } from './ui/primitives';
import { Bot, Cpu, Activity, CheckCircle2, AlertCircle } from 'lucide-react';

const protocolStages = [
  {
    step: '01',
    title: 'Capability Handshake',
    desc: 'Agents verify mutual capabilities, available execution targets, and streaming channels before starting work.',
    tag: 'Negotiation',
  },
  {
    step: '02',
    title: 'Structured Wire Frames',
    desc: 'Communication switches from chatty natural language to compact, balanced machine frames.',
    tag: 'Efficiency',
  },
  {
    step: '03',
    title: 'Contract Boundaries',
    desc: 'Requests adhere to typed interface schemas, preventing payload corruption and hallucinated fields.',
    tag: 'Safety',
  },
  {
    step: '04',
    title: 'Direct Dispatch',
    desc: 'Results are evaluated directly in-memory without multi-pass serialization or JSON reparsing.',
    tag: 'Execution',
  },
];

export const AgentWireProtocol: React.FC = () => (
  <Section id="a2a-protocol" variant="surface" labelledBy="a2a-title" className="overflow-hidden">

    <SectionHeader
      id="a2a-title"
      index="02"
      eyebrow="Agent to Agent"
      title="Prose is the wrong wire format between two machines."
      lead="Natural language is the right interface between a human and an agent. Between two machines, it is bloated payload that both sides have to re-parse and neither side can check. We are designing a structured wire protocol so agents can cooperate deterministically without conversational overhead."
      align="center"
    />

    <div className="max-w-5xl mx-auto">
      <div className="p-6 sm:p-8 rounded-2xl border border-line bg-surface/90 backdrop-blur-xl shadow-e3">
        <div className="flex flex-col sm:flex-row items-center justify-between gap-6 pb-8 border-b border-line">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-2xl bg-inset flex items-center justify-center border border-line">
              <Bot className="w-5 h-5 text-ink-2" />
            </div>
            <div>
              <p className="font-sans font-semibold text-ink">Planner Agent</p>
              <p className="font-mono text-micro uppercase text-ink-3">Orchestration & Task Flow</p>
            </div>
          </div>

          <div className="flex items-center gap-2.5 px-4 py-1.5 rounded-full border border-line bg-ground">
            <Activity className="w-4 h-4 text-ink-3" />
            <span className="font-mono text-micro font-semibold uppercase text-ink">
              Structured Agent Protocol
            </span>
          </div>

          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-2xl bg-inset flex items-center justify-center border border-line">
              <Cpu className="w-5 h-5 text-ink-2" />
            </div>
            <div className="text-right">
              <p className="font-sans font-semibold text-ink">Execution Specialist</p>
              <p className="font-mono text-micro uppercase text-ink-3">Target Runtime Worker</p>
            </div>
          </div>
        </div>

        <div className="mt-8 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {protocolStages.map((stage) => (
            <div
              key={stage.step}
              className="p-5 rounded-2xl border border-line bg-ground/80 backdrop-blur-sm flex flex-col justify-between"
            >
              <div>
                <div className="flex items-center justify-between">
                  <span className="font-mono text-micro font-semibold text-signal">{stage.step}</span>
                  <span className="font-mono text-micro uppercase text-ink-3">{stage.tag}</span>
                </div>
                <h3 className="mt-3 font-sans font-semibold text-ink text-base">{stage.title}</h3>
                <p className="mt-2 text-meta text-ink-2 leading-relaxed">{stage.desc}</p>
              </div>
            </div>
          ))}
        </div>

        <div className="mt-8 grid grid-cols-1 md:grid-cols-2 gap-6 pt-8 border-t border-line">
          <div className="p-6 rounded-2xl border border-line bg-inset/60">
            <div className="flex items-center justify-between">
              <span className="font-mono text-micro uppercase text-ink-3 font-semibold flex items-center gap-1.5">
                <AlertCircle className="w-3.5 h-3.5 text-ink-3" />
                Unstructured Prose
              </span>
              <span className="px-2.5 py-0.5 rounded-full bg-line text-ink-3 font-mono text-micro">
                Legacy
              </span>
            </div>
            <p className="mt-4 text-body text-ink font-medium leading-relaxed">
              “Could you please parse this JSON payload, build an FSM with idle and plan states, and return it formatted in JSON?”
            </p>
            <p className="mt-4 pt-4 border-t border-line text-meta text-ink-3 leading-relaxed">
              Unchecked prose. Re-parsed by the receiver, prone to ambiguous structures and context exhaustion.
            </p>
          </div>

          <div className="p-6 rounded-2xl border border-line bg-surface shadow-e1">
            <div className="flex items-center justify-between">
              <span className="font-mono text-micro uppercase text-ink-2 font-semibold flex items-center gap-1.5">
                <CheckCircle2 className="w-3.5 h-3.5 text-ink-3" />
                Structured Machine Frame
              </span>
              <span className="px-2.5 py-0.5 rounded-full bg-signal/10 text-signal font-mono text-micro font-semibold">
                Agent-Native
              </span>
            </div>
            <p className="mt-4 text-body text-ink font-medium leading-relaxed">
              Balanced symbolic packet with explicit signatures, typed arguments, and zero natural-language ambiguity.
            </p>
            <p className="mt-4 pt-4 border-t border-line text-meta text-ink-3 leading-relaxed">
              Direct evaluation. Evaluated into native memory structures with zero intermediary hallucination.
            </p>
          </div>
        </div>
      </div>
    </div>
  </Section>
);
