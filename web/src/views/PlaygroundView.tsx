import React, { useState } from 'react';
import { Section, SectionHeader } from '../components/ui/primitives';
import { SqlStudio } from '../components/SqlStudio';
import { AslQualityDoctor } from '../components/AslQualityDoctor';
import { Database, ShieldCheck } from 'lucide-react';

export const PlaygroundView: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'sql' | 'doctor'>('sql');

  return (
    <div className="pt-28 pb-20">
      <Section id="playground" labelledBy="playground-title">
        <SectionHeader
          id="playground-title"
          index="Interactive"
          eyebrow="Developer Playground"
          title="Interactive AgentScript Tooling & Verification Studio"
          lead="Experience live cross-dialect SQL query generation, formal AST smell detection, and autonomous code repairs in real time."
        />

        {/* Tab Switcher */}
        <div className="flex items-center gap-3 mb-10 p-1.5 rounded-2xl bg-surface border border-line max-w-md shadow-e1">
          <button
            type="button"
            onClick={() => setActiveTab('sql')}
            className={`flex-1 flex items-center justify-center gap-2 py-2.5 px-4 rounded-xl font-mono text-meta font-medium transition-all ${
              activeTab === 'sql'
                ? 'bg-signal text-white shadow-sm'
                : 'text-ink-2 hover:text-ink hover:bg-inset'
            }`}
          >
            <Database className="w-4 h-4" />
            <span>SQL Studio</span>
          </button>

          <button
            type="button"
            onClick={() => setActiveTab('doctor')}
            className={`flex-1 flex items-center justify-center gap-2 py-2.5 px-4 rounded-xl font-mono text-meta font-medium transition-all ${
              activeTab === 'doctor'
                ? 'bg-signal text-white shadow-sm'
                : 'text-ink-2 hover:text-ink hover:bg-inset'
            }`}
          >
            <ShieldCheck className="w-4 h-4" />
            <span>Quality Doctor</span>
          </button>
        </div>

        {/* Active Studio */}
        <div className="rounded-3xl border border-line bg-surface/90 backdrop-blur-xl p-4 sm:p-6 shadow-e3">
          {activeTab === 'sql' ? <SqlStudio /> : <AslQualityDoctor />}
        </div>
      </Section>
    </div>
  );
};
