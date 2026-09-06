import React, { useState } from 'react';
import { Section, SectionHeader } from '../components/ui/primitives';
import { SqlStudio } from '../components/SqlStudio';
import { AslQualityDoctor } from '../components/AslQualityDoctor';
import { GraphCanvas } from '../components/GraphCanvas';
import { SvgStudio } from '../components/SvgStudio';
import { InBrowserCodingStudio } from '../components/InBrowserCodingStudio';
import { Database, ShieldCheck, Share2, Sparkles, Terminal, CheckCircle2, Cpu } from 'lucide-react';

export const PlaygroundView: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'graph' | 'svg' | 'coder' | 'sql' | 'doctor'>('graph');

  return (
    <div className="pt-28 pb-20">
      <Section id="playground" labelledBy="playground-title">
        <SectionHeader
          id="playground-title"
          index="Interactive"
          eyebrow="Developer Playground"
          title="Interactive AgentScript Tooling & Live In-Browser Studio"
          lead="Experience real-time graph untangling with GPU acceleration, in-browser ASN vector drawing, live app & game coding with Eddie agent, SQL transpilation, and AST quality audits."
        />

        {/* Cryptographically Signed Eddie Identic & Runtime Signature Banner */}
        <div className="mb-6 p-4 rounded-2xl bg-surface/90 border border-line flex flex-wrap items-center justify-between gap-4 shadow-sm">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-signal/15 border border-signal/30 flex items-center justify-center text-signal">
              <Cpu className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="text-sm font-bold text-ink tracking-wide">EDDIE AGENTIC IDENTITY</span>
                <span className="px-2 py-0.5 rounded-full bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 font-mono text-[10px] font-bold flex items-center gap-1">
                  <CheckCircle2 className="w-2.5 h-2.5" /> SIGNED & GROUNDED
                </span>
              </div>
              <div className="text-xs font-mono text-ink-muted mt-0.5 flex flex-wrap items-center gap-2">
                <span className="text-signal">@asl:ident-eddie-0.1.0</span>
                <span>•</span>
                <span>Config: .asl.config.asn</span>
                <span>•</span>
                <span>Runtime: WebAssembly + WebGPU</span>
                <span>•</span>
                <span className="text-emerald-400">Zero-Foreign Policy Verified</span>
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2 text-xs font-mono">
            <span className="px-2.5 py-1 rounded-lg bg-surface-2 border border-line text-ink-muted">
              Wasm Linear Memory
            </span>
            <span className="px-2.5 py-1 rounded-lg bg-surface-2 border border-line text-ink-muted">
              WebGPU Pipeline
            </span>
            <span className="px-2.5 py-1 rounded-lg bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 font-bold">
              116 Test Suites 100%
            </span>
          </div>
        </div>

        {/* Tab Switcher */}
        <div className="flex flex-wrap items-center gap-2 mb-8 p-1.5 rounded-2xl bg-surface border border-line max-w-2xl shadow-e1">
          <button
            type="button"
            onClick={() => setActiveTab('graph')}
            className={`flex-1 min-w-[120px] flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl font-mono text-meta font-medium transition-all ${
              activeTab === 'graph'
                ? 'bg-signal text-white shadow-sm'
                : 'text-ink-2 hover:text-ink hover:bg-inset'
            }`}
          >
            <Share2 className="w-3.5 h-3.5" />
            <span>Untangle Graph</span>
          </button>

          <button
            type="button"
            onClick={() => setActiveTab('svg')}
            className={`flex-1 min-w-[110px] flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl font-mono text-meta font-medium transition-all ${
              activeTab === 'svg'
                ? 'bg-signal text-white shadow-sm'
                : 'text-ink-2 hover:text-ink hover:bg-inset'
            }`}
          >
            <Sparkles className="w-3.5 h-3.5" />
            <span>SVG Studio</span>
          </button>

          <button
            type="button"
            onClick={() => setActiveTab('coder')}
            className={`flex-1 min-w-[120px] flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl font-mono text-meta font-medium transition-all ${
              activeTab === 'coder'
                ? 'bg-signal text-white shadow-sm'
                : 'text-ink-2 hover:text-ink hover:bg-inset'
            }`}
          >
            <Terminal className="w-3.5 h-3.5" />
            <span>Live Coder & Games</span>
          </button>

          <button
            type="button"
            onClick={() => setActiveTab('sql')}
            className={`flex-1 min-w-[100px] flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl font-mono text-meta font-medium transition-all ${
              activeTab === 'sql'
                ? 'bg-signal text-white shadow-sm'
                : 'text-ink-2 hover:text-ink hover:bg-inset'
            }`}
          >
            <Database className="w-3.5 h-3.5" />
            <span>SQL</span>
          </button>

          <button
            type="button"
            onClick={() => setActiveTab('doctor')}
            className={`flex-1 min-w-[110px] flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl font-mono text-meta font-medium transition-all ${
              activeTab === 'doctor'
                ? 'bg-signal text-white shadow-sm'
                : 'text-ink-2 hover:text-ink hover:bg-inset'
            }`}
          >
            <ShieldCheck className="w-3.5 h-3.5" />
            <span>Doctor</span>
          </button>
        </div>

        {/* Active Studio */}
        <div className="rounded-3xl border border-line bg-surface/90 backdrop-blur-xl p-4 sm:p-6 shadow-e3">
          {activeTab === 'graph' && <GraphCanvas />}
          {activeTab === 'svg' && <SvgStudio />}
          {activeTab === 'coder' && <InBrowserCodingStudio />}
          {activeTab === 'sql' && <SqlStudio />}
          {activeTab === 'doctor' && <AslQualityDoctor />}
        </div>
      </Section>
    </div>
  );
};
