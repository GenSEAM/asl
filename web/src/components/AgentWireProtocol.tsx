import React from 'react';
import { Section, SectionHeader } from './ui/primitives';
import { Bot, Cpu, Activity, CheckCircle2, AlertCircle } from 'lucide-react';

const protocolStages = [
  {
    step: '01',
    title: 'Instant Handshake',
    desc: 'Agents verify schemas and target runtimes in a single 20-byte discovery probe.',
    tag: 'Probe',
  },
  {
    step: '02',
    title: 'ASN Wire Frames',
    desc: 'Replaces conversational English with compact S-expressions. -80% tokens.',
    tag: 'Compact',
  },
  {
    step: '03',
    title: 'Zero-Hallucination Types',
    desc: 'Typed contract boundaries guarantee no missing keys, invalid types, or parse loops.',
    tag: 'Strict',
  },
  {
    step: '04',
    title: 'Direct In-Memory Dispatch',
    desc: 'Evaluates directly in host memory (<0.05ms) without multi-pass JSON re-serialization.',
    tag: 'Fast',
  },
];

export const AgentWireProtocol: React.FC = () => (
  <Section id="a2a-protocol" variant="surface" labelledBy="a2a-title" className="overflow-hidden">
    <SectionHeader
      id="a2a-title"
      index="04"
      eyebrow="Agent-to-Agent Mesh Protocol"
      title="Machines Shouldn't Chat Like Humans."
      lead="When autonomous agents talk to each other in conversational English, you burn 80% of your token budget on polite greetings, repetitive prompts, and JSON parse failures. AgentScript Wire Frames replace conversational chat with instant, typed machine frames."
      align="center"
    />

    <div className="max-w-5xl mx-auto">
      <div className="p-6 sm:p-8 rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e3">
        {/* Agent Communication Mesh Diagram */}
        <div className="flex flex-col sm:flex-row items-center justify-between gap-6 pb-8 border-b border-line">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-2xl bg-inset flex items-center justify-center border border-line">
              <Bot className="w-5 h-5 text-signal" />
            </div>
            <div>
              <p className="font-sans font-semibold text-ink">Planner Agent (LLM)</p>
              <p className="font-mono text-micro uppercase text-ink-3">High-Reasoning Orchestrator</p>
            </div>
          </div>

          <div className="flex items-center gap-2.5 px-4 py-1.5 rounded-full border border-signal/30 bg-signal/10 text-signal">
            <Activity className="w-4 h-4 text-signal animate-pulse" />
            <span className="font-mono text-micro font-semibold uppercase tracking-wider">
              Sub-Millisecond Wire Mesh
            </span>
          </div>

          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-2xl bg-inset flex items-center justify-center border border-line">
              <Cpu className="w-5 h-5 text-emerald-400" />
            </div>
            <div className="text-right">
              <p className="font-sans font-semibold text-ink">Worker Agent (Wasm / Local)</p>
              <p className="font-mono text-micro uppercase text-ink-3">High-Speed Execution Node</p>
            </div>
          </div>
        </div>

        {/* 4 Protocol Pillars */}
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

        {/* Side-by-Side Code Comparison: Conversational English vs AgentScript Frame */}
        <div className="mt-8 grid grid-cols-1 md:grid-cols-2 gap-6 pt-8 border-t border-line">
          {/* The Chatty English & JSON Way */}
          <div className="p-6 rounded-2xl border border-rose-500/20 bg-rose-500/5">
            <div className="flex items-center justify-between pb-3 border-b border-rose-500/20">
              <span className="font-mono text-micro uppercase text-rose-400 font-semibold flex items-center gap-1.5">
                <AlertCircle className="w-3.5 h-3.5" />
                The Chatty Human Way (Conversational JSON)
              </span>
              <span className="px-2.5 py-0.5 rounded-full bg-rose-500/15 text-rose-300 font-mono text-micro">
                178 Tokens · High Latency
              </span>
            </div>
            <div className="mt-4 font-mono text-xs text-ink-2 leading-relaxed bg-ground/70 p-4 rounded-xl border border-line overflow-x-auto">
              <p className="text-ink-3">"Hi there! Could you please inspect order #892, verify if the payment cleared, and return the items formatted as strict JSON without markdown backticks? Thanks!"</p>
              <p className="mt-2 text-rose-300">{"-->"} Sure! Here is the JSON: {"\n"}{'{"order_id": 892, "status": "paid", ...}'}</p>
            </div>
            <p className="mt-3 text-micro text-ink-3">
              Unchecked prose. Fragile parser loops, token bloat, and frequent markdown formatting hallucinations.
            </p>
          </div>

          {/* The AgentScript Wire Frame Way */}
          <div className="p-6 rounded-2xl border border-emerald-500/30 bg-emerald-500/5 shadow-e1">
            <div className="flex items-center justify-between pb-3 border-b border-emerald-500/20">
              <span className="font-mono text-micro uppercase text-emerald-400 font-semibold flex items-center gap-1.5">
                <CheckCircle2 className="w-3.5 h-3.5" />
                The AgentScript Way (ASN Wire Frame)
              </span>
              <span className="px-2.5 py-0.5 rounded-full bg-emerald-500/15 text-emerald-300 font-mono text-micro font-semibold">
                22 Tokens · 0.05ms
              </span>
            </div>
            <div className="mt-4 font-mono text-xs text-purple-300 leading-relaxed bg-ground/70 p-4 rounded-xl border border-line overflow-x-auto">
              <p className="text-signal">(? order/inspect :id 892 :req [status items])</p>
              <p className="mt-2 text-emerald-400">(! order/ack :status :paid :items [(:sku "x1" :qty 2)])</p>
            </div>
            <p className="mt-3 text-micro text-emerald-400/90 font-medium">
              Zero conversational fluff. Validated against compiler schemas in one pass, evaluated in-memory.
            </p>
          </div>
        </div>
      </div>
    </div>
  </Section>
);
