import React, { useState } from 'react';
import { Section, SectionHeader } from '../components/ui/primitives';
import { SqlStudio } from '../components/SqlStudio';
import { AslQualityDoctor } from '../components/AslQualityDoctor';
import { GraphCanvas } from '../components/GraphCanvas';
import { SvgStudio } from '../components/SvgStudio';
import { InBrowserCompanion } from '../components/InBrowserCompanion';
import { Database, ShieldCheck, Share2, Sparkles, Cpu, CheckCircle2 } from 'lucide-react';

export const PlaygroundView: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'graph' | 'svg' | 'companion' | 'sql' | 'doctor'>('graph');

  return (
    <div className="pt-28 pb-20">
      <Section id="playground" labelledBy="playground-title">
        <SectionHeader
          id="playground-title"
          index="Interactive"
          eyebrow="Developer Playground"
          title="Interactive AgentScript Tooling & Live In-Browser Studio"
          lead="Experience real-time graph untangling with GPU acceleration, ASN vector drawing, local client-side WebGPU agent companion, SQL transpilation, and AST quality audits."
        />

        {/* Runtime Status Banner */}
        <div className="mb-6 p-4 rounded-2xl bg-surface/90 border border-line flex flex-wrap items-center justify-between gap-4 shadow-sm">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-signal/15 border border-signal/30 flex items-center justify-center text-signal">
              <Cpu className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="text-sm font-bold text-ink tracking-wide">AGENTSCRIPT WEB RUNTIME</span>
                <span className="px-2 py-0.5 rounded-full bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 font-mono text-[10px] font-bold flex items-center gap-1">
                  <CheckCircle2 className="w-2.5 h-2.5" /> CLIENT-SIDE READY
                </span>
              </div>
              <div className="text-xs font-mono text-ink-muted mt-0.5 flex flex-wrap items-center gap-2">
                <span className="text-signal">@asl:web-runtime-0.1.0</span>
                <span>•</span>
                <span>Wasm + WebGPU + WebGL</span>
                <span>•</span>
                <span className="text-emerald-400">Zero Cloud Dependencies</span>
              </div>
            </div>
          </div>
        </div>

        {/* Tab Navigation */}
        <div className="flex flex-wrap items-center gap-2 mb-8 p-1.5 rounded-2xl bg-surface border border-line max-w-3xl shadow-e1">
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
            onClick={() => setActiveTab('companion')}
            className={`flex-1 min-w-[130px] flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl font-mono text-meta font-medium transition-all ${
              activeTab === 'companion'
                ? 'bg-signal text-white shadow-sm'
                : 'text-ink-2 hover:text-ink hover:bg-inset'
            }`}
          >
            <Cpu className="w-3.5 h-3.5" />
            <span>AI Companion</span>
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
            <span>SQL Studio</span>
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
            <span>Quality Doctor</span>
          </button>
        </div>

        {/* Active Studio */}
        <div className="rounded-3xl border border-line bg-surface/90 backdrop-blur-xl p-4 sm:p-6 shadow-e3">
          {activeTab === 'graph' && <GraphCanvas />}
          {activeTab === 'svg' && <SvgStudio />}
          {activeTab === 'companion' && <InBrowserCompanion />}
          {activeTab === 'sql' && <SqlStudio />}
          {activeTab === 'doctor' && <AslQualityDoctor />}
        </div>
      </Section>
    </div>
  );
};

