import React from 'react';
import { Section, SectionHeader } from './ui/primitives';
import { Bot, Network, Cpu, ShieldCheck, ArrowRight, Activity } from 'lucide-react';

const protocolStages = [
  {
    step: '01',
    title: 'Capability Probe',
    desc: 'Agents negotiate supported capabilities: WASI preview1 runtime, schema validation, and streaming channels.',
    tag: 'Handshake',
  },
  {
    step: '02',
    title: 'Nano Mode Agreement',
    desc: 'Both agents lock into ASL Nano protocol mode, dropping natural language prose for structured machine frames.',
    tag: 'Protocol Lock',
  },
  {
    step: '03',
    title: 'Typed Interface Request',
    desc: 'Requests are passed with strictly verified type boundaries and schema contracts — preventing runtime mismatches.',
    tag: 'Zero Drift',
  },
  {
    step: '04',
    title: 'Direct AST Result',
    desc: 'Results return as balanced S-expressions evaluated in-memory without multi-pass serialization or JSON reparsing.',
    tag: '<0.02ms Return',
  },
];

export const AgentWireProtocol: React.FC = () => (
  <Section id="a2a-protocol" ground="sunken" labelledBy="a2a-title" className="bg-dot-grid overflow-hidden">
    {/* Atmospheric Glow */}
    <div className="glow-orb top-1/3 -left-48 w-96 h-96" aria-hidden="true" />

    <SectionHeader
      id="a2a-title"
      index="02"
      eyebrow="Agent to Agent"
      title="Prose is the wrong wire format between two machines."
      lead="Natural language is the right interface between an agent and a person. Between two autonomous agents it is bloated payload that both sides have to re-parse and neither side can check. The moment they connect, they lock into ASL Nano and stop talking in sentences."
      align="center"
    />

    <div className="max-w-5xl mx-auto">
      {/* Mesh Network Nodes Topology */}
      <div className="p-6 sm:p-8 rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e3">
        <div className="flex flex-col sm:flex-row items-center justify-between gap-6 pb-8 border-b border-line">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-2xl bg-inset flex items-center justify-center border border-line">
              <Bot className="w-5 h-5 text-signal" />
            </div>
            <div>
              <p className="font-sans font-bold text-ink">Orchestrator Agent</p>
              <p className="font-mono text-micro uppercase text-ink-3">Planner & Task DAG</p>
            </div>
          </div>

          <div className="flex items-center gap-3 px-4 py-2 rounded-full border border-line bg-ground">
            <Activity className="w-4 h-4 text-signal animate-pulse" />
            <span className="font-mono text-micro font-semibold uppercase text-ink">
              ASL Nano High-Speed Wire Mesh
            </span>
          </div>

          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-2xl bg-inset flex items-center justify-center border border-line">
              <Cpu className="w-5 h-5 text-signal" />
            </div>
            <div className="text-right">
              <p className="font-sans font-bold text-ink">Specialist Agent</p>
              <p className="font-mono text-micro uppercase text-ink-3">Wasm Execution Sandbox</p>
            </div>
          </div>
        </div>

        {/* 4 Protocol Pipeline Stages */}
        <div className="mt-8 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {protocolStages.map((stage) => (
            <div
              key={stage.step}
              className="p-5 rounded-2xl border border-line bg-ground/80 backdrop-blur-sm flex flex-col justify-between"
            >
              <div>
                <div className="flex items-center justify-between">
                  <span className="font-mono text-micro font-bold text-signal">{stage.step}</span>
                  <span className="font-mono text-micro uppercase text-ink-3">{stage.tag}</span>
                </div>
                <h3 className="mt-3 font-sans font-bold text-ink text-base">{stage.title}</h3>
                <p className="mt-2 text-meta text-ink-2 leading-relaxed">{stage.desc}</p>
              </div>
            </div>
          ))}
        </div>

        {/* Contrast Comparison Cards */}
        <div className="mt-8 grid grid-cols-1 md:grid-cols-2 gap-6 pt-8 border-t border-line">
          <div className="p-6 rounded-2xl border border-line bg-inset/50">
            <div className="flex items-center justify-between">
              <span className="font-mono text-micro uppercase text-ink-3 font-semibold">Natural Language Prose</span>
              <span className="px-2.5 py-1 rounded-full bg-red-500/10 text-red-600 dark:text-red-400 font-mono text-micro font-semibold">
                High Overhead
              </span>
            </div>
            <p className="mt-4 text-body text-ink font-medium">
              “Could you please parse this JSON schema, generate an FSM with idle and plan states, and return it formatted?”
            </p>
            <p className="mt-4 pt-4 border-t border-line text-meta text-ink-3">
              Unchecked prose. Re-parsed by the receiver, prone to hallucinated keys and context exhaustion.
            </p>
          </div>

          <div className="p-6 rounded-2xl border border-line bg-surface shadow-e2">
            <div className="flex items-center justify-between">
              <span className="font-mono text-micro uppercase text-signal font-semibold">ASL Nano Wire Frame</span>
              <span className="px-2.5 py-1 rounded-full bg-signal/10 text-signal font-mono text-micro font-semibold">
                -78.4% Tokens
              </span>
            </div>
            <p className="mt-4 font-sans text-body text-ink font-medium">
              Deterministic, balanced machine packet with strictly typed interface verification and zero ambiguous tokens.
            </p>
            <p className="mt-4 pt-4 border-t border-line text-meta text-ink-3">
              Single-pass execution. Directly evaluated into native memory with zero intermediary hallucination.
            </p>
          </div>
        </div>
      </div>
    </div>
  </Section>
);
