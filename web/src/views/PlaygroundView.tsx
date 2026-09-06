import React from 'react';
import { Section, SectionHeader } from '../components/ui/primitives';
import { InBrowserCompanion } from '../components/InBrowserCompanion';
import { Sparkles, Cpu, CheckCircle2 } from 'lucide-react';

export const PlaygroundView: React.FC = () => {
  return (
    <div className="pt-28 pb-20">
      <Section id="playground" labelledBy="playground-title">
        <SectionHeader
          id="playground-title"
          index="AI Companion"
          eyebrow="Developer Playground"
          title="On-Device AI Companion & Tri-Studio"
          lead="Direct developer access to the sovereign in-browser companion: generate vector badges (SVG Studio), playable HTML5 arcade toys (Games Studio), and modern responsive components (Websites Studio) with client-side verification gates."
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
                <span className="px-2 py-0.5 rounded-full bg-amber-500/15 border border-amber-500/30 text-amber-400 font-mono text-[10px] font-bold flex items-center gap-1">
                  <Sparkles className="w-2.5 h-2.5" /> IN ACTIVE DEVELOPMENT
                </span>
                <span className="px-2 py-0.5 rounded-full bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 font-mono text-[10px] font-bold flex items-center gap-1">
                  <CheckCircle2 className="w-2.5 h-2.5" /> CLIENT-SIDE READY
                </span>
              </div>
              <div className="text-xs font-mono text-ink-muted mt-0.5 flex flex-wrap items-center gap-2">
                <span className="text-signal">@asl:playground-preview</span>
                <span>•</span>
                <span>Direct Access Route (/playground)</span>
                <span>•</span>
                <span className="text-emerald-400">Zero Cloud Dependencies</span>
              </div>
            </div>
          </div>
        </div>

        <div className="mt-4">
          <InBrowserCompanion />
        </div>
      </Section>
    </div>
  );
};

export default PlaygroundView;

